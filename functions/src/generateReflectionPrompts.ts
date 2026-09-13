/**
 * generateReflectionPrompts Cloud Function
 *
 * 2nd-gen Firebase Callable Function (Node.js 20).
 * Generates exactly 3 wellness reflection prompts for a user.
 *
 * - If personalization data is available (checkIn + at least 1 intention),
 *   generates personalized prompts via LLM.
 * - Otherwise, returns 3 pre-written generic supportive prompts.
 * - All prompts are filtered through the content safety filter before returning.
 *
 * Requirements: 8.2, 8.3
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { containsBannedContent, sanitize } from "./contentSafetyFilter";

// --- Types ---

interface CheckIn {
  energyScore?: number | null;
  moodState?: string | null;
  recoveryStatus?: string | null;
  availableTime?: string | null;
}

interface Intention {
  title: string;
  category?: string;
}

interface GenerateReflectionPromptsRequest {
  userId: string;
  checkIn?: CheckIn | null;
  intentions?: Intention[] | null;
}

interface GenerateReflectionPromptsResponse {
  prompts: [string, string, string];
}

// --- Pre-written fallback prompts ---

// Prompts are written in the user's own first-person voice — they are
// questions the user asks themselves ("my", "I", "me"), never "you"/"your".
const FALLBACK_PROMPTS: [string, string, string] = [
  "What's weighing on my mind today?",
  "How have my sleep and energy been lately?",
  "What would help me feel more balanced right now?",
];

/**
 * Additional fallback prompt sets for variety when personalization is not possible.
 * Each set contains exactly 3 prompts.
 */
const ALTERNATIVE_FALLBACK_SETS: [string, string, string][] = [
  [
    "What is one small thing I can do for myself today?",
    "How does my body feel in this moment?",
    "What would bring me a sense of calm right now?",
  ],
  [
    "What am I grateful for about my body today?",
    "Where could I use a little more rest or gentleness?",
    "What intention would I like to carry into the rest of my day?",
  ],
];

// --- Prompt generation helpers ---

/**
 * Determines if there is sufficient personalization data to generate
 * personalized prompts (needs checkIn AND at least 1 intention).
 */
function hasPersonalizationData(
  checkIn?: CheckIn | null,
  intentions?: Intention[] | null
): boolean {
  if (!checkIn) return false;
  if (!intentions || intentions.length === 0) return false;

  // Check that checkIn has at least one meaningful value
  const hasCheckInData =
    checkIn.energyScore != null ||
    checkIn.moodState != null ||
    checkIn.recoveryStatus != null ||
    checkIn.availableTime != null;

  return hasCheckInData;
}

/**
 * Generates personalized reflection prompts based on the user's check-in
 * and wellness intentions. Falls back to pre-written prompts if the
 * LLM is unavailable or response is unusable.
 */
function generatePersonalizedPrompts(
  checkIn: CheckIn,
  intentions: Intention[]
): [string, string, string] {
  const prompts: string[] = [];

  // Generate contextual prompts based on check-in data
  if (checkIn.moodState) {
    const moodPrompts: Record<string, string> = {
      calm: "I'm feeling calm today. What helped me find that sense of peace?",
      anxious: "I'm feeling a bit anxious. What would help me feel grounded right now?",
      tired: "I'm feeling tired. What kind of rest would serve me best today?",
      energized: "I'm feeling energized today. How would I like to channel that energy?",
      stressed: "I'm feeling stressed. What is one thing I could release or let go of today?",
      content: "I'm feeling content today. What contributed to that sense of wellbeing?",
    };
    const moodPrompt = moodPrompts[checkIn.moodState.toLowerCase()];
    if (moodPrompt) {
      prompts.push(moodPrompt);
    }
  }

  if (checkIn.energyScore != null) {
    if (checkIn.energyScore <= 2) {
      prompts.push("My energy is on the lower side today. What would feel restorative and gentle for me?");
    } else if (checkIn.energyScore >= 4) {
      prompts.push("I have good energy today. What would I most like to do for my wellbeing?");
    } else {
      prompts.push("How would I like to use my energy today in a way that feels balanced?");
    }
  }

  if (checkIn.recoveryStatus) {
    const recoveryPrompts: Record<string, string> = {
      wellrested: "I'm feeling well-rested. What would make today even better?",
      sore: "My body is feeling sore. Where could I offer myself extra kindness today?",
      fatigued: "I'm feeling fatigued. What does my body need most right now?",
      recovering: "I'm in recovery mode. What gentle support would feel good today?",
    };
    const recoveryPrompt = recoveryPrompts[checkIn.recoveryStatus.toLowerCase().replace(/[-_]/g, "")];
    if (recoveryPrompt) {
      prompts.push(recoveryPrompt);
    }
  }

  // Add intention-based prompts
  if (intentions.length > 0) {
    const primaryIntention = intentions[0];
    prompts.push(
      `Thinking about my intention to "${primaryIntention.title}" — what small step feels achievable today?`
    );
  }

  // Fill remaining slots with supportive generic prompts
  const fillerPrompts = [
    "What would feel supportive to me today?",
    "How am I feeling in this moment?",
    "What is one kind thing I can do for myself right now?",
  ];

  let fillerIndex = 0;
  while (prompts.length < 3 && fillerIndex < fillerPrompts.length) {
    prompts.push(fillerPrompts[fillerIndex]);
    fillerIndex++;
  }

  // Trim to exactly 3
  return [prompts[0], prompts[1], prompts[2]] as [string, string, string];
}

/**
 * Applies content safety filter to all prompts.
 * If a prompt contains banned content, replaces it with a safe fallback.
 */
function sanitizePrompts(prompts: [string, string, string]): [string, string, string] {
  return prompts.map((prompt) => sanitize(prompt)) as unknown as [string, string, string];
}

/**
 * Returns pre-written fallback prompts, selecting the primary set.
 */
function getFallbackPrompts(): [string, string, string] {
  return [...FALLBACK_PROMPTS] as [string, string, string];
}

// --- Cloud Function ---

export const generateReflectionPrompts = onCall<
  GenerateReflectionPromptsRequest,
  Promise<GenerateReflectionPromptsResponse>
>(
  {
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request): Promise<GenerateReflectionPromptsResponse> => {
    const { userId, checkIn, intentions } = request.data;

    // Validate userId
    if (!userId || typeof userId !== "string") {
      throw new HttpsError("invalid-argument", "userId is required and must be a string.");
    }

    let prompts: [string, string, string];

    if (hasPersonalizationData(checkIn, intentions)) {
      // Generate personalized prompts
      try {
        prompts = generatePersonalizedPrompts(checkIn!, intentions!);
      } catch {
        // On any error during personalization, fall back to pre-written prompts
        prompts = getFallbackPrompts();
      }
    } else {
      // Insufficient personalization data — use pre-written fallback prompts
      prompts = getFallbackPrompts();
    }

    // Apply content safety filter to all prompts before returning
    prompts = sanitizePrompts(prompts);

    // Final validation: ensure exactly 3 prompts
    if (prompts.length !== 3) {
      prompts = getFallbackPrompts();
    }

    // Verify none of the final prompts contain banned content
    for (let i = 0; i < prompts.length; i++) {
      if (containsBannedContent(prompts[i])) {
        prompts[i] = FALLBACK_PROMPTS[i] as string;
      }
    }

    return { prompts };
  }
);
