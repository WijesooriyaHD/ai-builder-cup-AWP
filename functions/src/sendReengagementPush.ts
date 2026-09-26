/**
 * Re-engagement pushes for users who have drifted away.
 *
 * WHY THIS LIVES ON THE SERVER
 * The app can schedule its own reminders locally while it is installed and
 * running — and it does, for everything it can decide on-device. But a user who
 * has not opened the app for days is exactly the user whose app is not running
 * to schedule anything. Reaching them needs something outside the device, which
 * is this function plus the OneSignal REST API.
 *
 * WHAT IT DOES NOT DO
 * It does not decide *what* wellness means — Firestore already holds the check-in
 * history and the user's notification preferences, and this function only reads
 * them. Keeping the judgement in the data rather than in the delivery layer is
 * what lets the same rules apply whether a reminder goes out locally or remotely.
 *
 * SAFETY RULES BAKED IN
 *  - Never messages a user whose master switch or check_in category is off.
 *  - Never messages more than once per QUIET_DAYS window (a `last_reengaged_at`
 *    stamp), so a lapsed user gets a nudge, not a campaign.
 *  - Never messages someone who has been away so long they have effectively
 *    churned (MAX_LAPSED_DAYS) — at that point a push is spam, not a service.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// The OneSignal REST API Key. Stored as a Firebase secret, never in source:
//   firebase functions:secrets:set ONESIGNAL_REST_KEY
const ONESIGNAL_REST_KEY = defineSecret("ONESIGNAL_REST_KEY");

/** Public client identifier — the same App ID the Flutter app initializes with. */
const ONESIGNAL_APP_ID = "b9e6a19e-8072-4118-bf06-0fd21868cb2e";

/** Days of silence before we send anything. */
const LAPSED_DAYS = 2;

/** Past this many days we stop nudging — they have moved on. */
const MAX_LAPSED_DAYS = 30;

/** Minimum days between two re-engagement pushes to the same person. */
const QUIET_DAYS = 5;

/** Safety valve so a query bug cannot message the entire user base at once. */
const MAX_PER_RUN = 500;

if (admin.apps.length === 0) {
  admin.initializeApp();
}

interface OneSignalPayload {
  app_id: string;
  include_aliases: { external_id: string[] };
  target_channel: "push";
  headings: { en: string };
  contents: { en: string };
  data: Record<string, string>;
}

/**
 * Sends one push via the OneSignal REST API.
 *
 * Targets by `external_id`, which is the Firebase UID the app sets with
 * `OneSignal.login()` — so this addresses the person, not a device, and
 * reaches them on whichever devices they have.
 */
async function sendPush(
  restKey: string,
  externalId: string,
  heading: string,
  content: string,
  data: Record<string, string>
): Promise<boolean> {
  const payload: OneSignalPayload = {
    app_id: ONESIGNAL_APP_ID,
    include_aliases: { external_id: [externalId] },
    target_channel: "push",
    headings: { en: heading },
    contents: { en: content },
    data,
  };

  try {
    const response = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Key ${restKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const body = await response.text();
      logger.warn(`OneSignal rejected push for ${externalId}`, {
        status: response.status,
        body,
      });
      return false;
    }
    return true;
  } catch (error) {
    logger.error(`OneSignal request failed for ${externalId}`, error);
    return false;
  }
}

/** Whole days between two dates. */
function daysBetween(from: Date, to: Date): number {
  const ms = to.getTime() - from.getTime();
  return Math.floor(ms / (1000 * 60 * 60 * 24));
}

/**
 * Runs once a day and nudges users who have lapsed.
 *
 * 10:00 UTC is a deliberately conservative default: it avoids the middle of the
 * night for most of the app's user base. Per-user local timing is the obvious
 * next step — the app already records check-in times for exactly that purpose
 * (see `user_behavior_profile`), so this can graduate to "their usual hour"
 * without changing the surrounding structure.
 */
export const sendReengagementPush = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "UTC",
    secrets: [ONESIGNAL_REST_KEY],
    // A slow, chatty job: plenty of time, minimal memory.
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const restKey = ONESIGNAL_REST_KEY.value();
    const now = new Date();

    // Only users who have ever checked in — someone who has not started yet
    // needs onboarding, which is a Journey's job, not a re-engagement push.
    const snapshot = await db
      .collection("users")
      .where("last_active_date", "!=", null)
      .limit(MAX_PER_RUN)
      .get();

    let considered = 0;
    let sent = 0;
    let skipped = 0;

    for (const doc of snapshot.docs) {
      considered++;
      const data = doc.data();

      // --- Preference gate. The same preferences the app enforces locally. ---
      const prefs = data.notification_preferences ?? {};
      const masterEnabled = prefs.master_enabled !== false;
      const checkInEnabled = prefs.categories?.check_in !== false;
      if (!masterEnabled || !checkInEnabled) {
        skipped++;
        continue;
      }

      // --- How long since they checked in? ---
      const lastActiveRaw = data.last_active_date;
      if (typeof lastActiveRaw !== "string") {
        skipped++;
        continue;
      }
      const lastActive = new Date(lastActiveRaw);
      if (Number.isNaN(lastActive.getTime())) {
        skipped++;
        continue;
      }

      const lapsed = daysBetween(lastActive, now);
      if (lapsed < LAPSED_DAYS || lapsed > MAX_LAPSED_DAYS) {
        skipped++;
        continue;
      }

      // --- Have we already nudged them recently? ---
      const lastNudgeRaw = data.last_reengaged_at;
      if (typeof lastNudgeRaw === "string") {
        const lastNudge = new Date(lastNudgeRaw);
        if (
          !Number.isNaN(lastNudge.getTime()) &&
          daysBetween(lastNudge, now) < QUIET_DAYS
        ) {
          skipped++;
          continue;
        }
      }

      // --- Compose. A preserved streak is the strongest reason to return, so
      // lead with it when there is one. ---
      const streak = typeof data.current_streak === "number"
        ? data.current_streak
        : 0;

      const heading =
        streak > 1 ? "Your streak is waiting 🌿" : "How are you feeling? 🌿";
      const content =
        streak > 1
          ? `You built a ${streak}-day streak. A quick check-in keeps it going.`
          : "Take a moment to check in with yourself today.";

      const ok = await sendPush(restKey, doc.id, heading, content, {
        notification_type: "check_in",
        deep_link: "/check-in",
      });

      if (ok) {
        sent++;
        // Stamp it so QUIET_DAYS is honoured on the next run.
        await doc.ref.set(
          { last_reengaged_at: now.toISOString() },
          { merge: true }
        );
      }
    }

    logger.info("Re-engagement run complete", { considered, sent, skipped });
  }
);
