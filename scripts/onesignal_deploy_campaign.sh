#!/usr/bin/env bash
#
# Creates and deploys the Wellness Pal re-engagement campaign via the
# OneSignal REST API.
#
# WHY A SCRIPT RATHER THAN THE DASHBOARD
# The award asks for a campaign created through the OneSignal API, MCP, or
# dashboard. Doing it through the API makes the campaign reproducible and
# reviewable — it lives in version control next to the app that reports the
# events it targets, rather than only as clicks someone made once.
#
# THE API KEY IS A PASSWORD. Anyone holding it can send notifications to every
# user of this app, so it must never be committed, pasted into a chat, or left
# anywhere it can be read back.
#
# This script never stores it. It offers three ways in, best first:
#
#   1. Secure prompt (recommended) — nothing is typed on the command line, so
#      nothing lands in shell history:
#        ./scripts/onesignal_deploy_campaign.sh
#
#   2. A gitignored local file, for repeated runs:
#        echo 'ONESIGNAL_REST_KEY=os_v2_app_...' > .onesignal.env
#        ./scripts/onesignal_deploy_campaign.sh
#
#   3. An environment variable already exported by a secrets manager.
#
# Note on `export ONESIGNAL_REST_KEY=...` typed by hand: your shell writes that
# line to its history file, leaving the key readable on disk long afterwards.
# Prefer option 1 or 2.
#
# Add --dry-run to print the request without sending it or asking for a key.
#
set -euo pipefail

# The App ID is a PUBLIC client identifier — it already ships inside the app
# binary (see kOneSignalAppId in lib/main.dart), so it is safe in source.
APP_ID="b9e6a19e-8072-4118-bf06-0fd21868cb2e"

DRY_RUN=false
TEST_MODE=false
case "${1:-}" in
  --dry-run) DRY_RUN=true ;;
  --test)    TEST_MODE=true ;;
esac

# Resolve the key: existing environment, then a gitignored local file, then a
# secure prompt. Never echoed, never written anywhere by this script.
ENV_FILE="$(dirname "$0")/../.onesignal.env"

if [[ "$DRY_RUN" == false ]]; then
  if [[ -z "${ONESIGNAL_REST_KEY:-}" && -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
    # A file holding a placeholder or a truncated paste is worse than no file:
    # it silently shadows the prompt and fails later as a confusing 401. Check
    # it looks like a key before trusting it, and fall through to the prompt
    # if it does not.
    if [[ ${#ONESIGNAL_REST_KEY} -lt 40 || "$ONESIGNAL_REST_KEY" == *"..."* ]]; then
      echo "WARNING: $(basename "$ENV_FILE") does not contain a usable key" >&2
      echo "  (${#ONESIGNAL_REST_KEY} characters — a real key is much longer)." >&2
      echo "  Ignoring it and asking instead." >&2
      ONESIGNAL_REST_KEY=""
    else
      echo "Using key from $(basename "$ENV_FILE")"
    fi
  fi

  if [[ -z "${ONESIGNAL_REST_KEY:-}" ]]; then
    echo "OneSignal App API key (input hidden — paste and press Enter)."
    echo "Create one at: OneSignal → Settings → Keys & IDs → Add API key"
    # -s keeps it off the screen; reading into a variable keeps it out of the
    # process list and out of shell history.
    read -r -s -p "Key: " ONESIGNAL_REST_KEY
    echo
  fi

  if [[ -z "${ONESIGNAL_REST_KEY:-}" ]]; then
    echo "ERROR: no key provided." >&2
    exit 1
  fi

  # Current OneSignal App API keys start with os_v2_app_. A legacy key still
  # works but authenticates differently, so warn rather than fail silently.
  if [[ "$ONESIGNAL_REST_KEY" != os_v2_app_* ]]; then
    echo "WARNING: key does not start with 'os_v2_app_'." >&2
    echo "  Legacy REST API keys use 'Authorization: Basic', not 'Key'." >&2
    echo "  If this returns 401/403, that mismatch is why." >&2
  fi
fi

# ---------------------------------------------------------------------------
# The campaign: "Your streak is waiting"
#
# Targeted, not broadcast. The filters below are the whole point — every one
# of them exists so the message only reaches someone it would actually help:
#
#   notifications_enabled = true   the user has not muted us
#   notify_check_in       = true   they want check-in reminders specifically
#   current_streak > 0             they have a streak worth protecting
#   last_session > 48h             they have actually drifted away
#
# Those first two tags are written by the app whenever preferences change, so
# this campaign can never reach someone who turned notifications off — the
# same rule the app enforces locally, enforced again at the delivery layer.
#
# The data payload is what makes the tap useful: NotificationRouter reads it
# and opens the Check-in screen directly, rather than dropping the user on
# whatever screen they last had open.
# ---------------------------------------------------------------------------

# The production filter set. The 48-hour clause is the one that matters most:
# it is what makes this a re-engagement message rather than a broadcast.
FILTERS='[
    { "field": "tag", "key": "notifications_enabled", "relation": "=", "value": "true" },
    { "operator": "AND" },
    { "field": "tag", "key": "notify_check_in", "relation": "=", "value": "true" },
    { "operator": "AND" },
    { "field": "tag", "key": "current_streak", "relation": ">", "value": "0" },
    { "operator": "AND" },
    { "field": "last_session", "relation": ">", "hours_ago": "48" }
  ]'
CAMPAIGN_NAME="Wellness Pal · Streak Re-engagement"
DELIVERY='"delayed_option": "timezone",
  "delivery_time_of_day": "6:00PM"'

if [[ "$TEST_MODE" == true ]]; then
  # --test keeps the preference gates (so a muted user is still unreachable,
  # which is the behaviour worth proving) but drops the 48-hour lapse clause.
  # Nobody has been away two days on the day you build the thing, and a
  # campaign that matches nobody is never created — so without this there is
  # nothing to show in the dashboard.
  echo "TEST MODE: sending now, without the 48-hour lapse filter."
  FILTERS='[
    { "field": "tag", "key": "notifications_enabled", "relation": "=", "value": "true" },
    { "operator": "AND" },
    { "field": "tag", "key": "notify_check_in", "relation": "=", "value": "true" }
  ]'
  CAMPAIGN_NAME="Wellness Pal · Streak Re-engagement (test)"
  DELIVERY='"delayed_option": "immediate"'
fi

read -r -d '' PAYLOAD <<JSON || true
{
  "app_id": "${APP_ID}",
  "name": "${CAMPAIGN_NAME}",
  "target_channel": "push",
  "filters": ${FILTERS},
  "headings": { "en": "Your streak is waiting 🌿" },
  "contents": { "en": "You've been building something good. A quick check-in keeps it going." },
  "data": {
    "notification_type": "check_in",
    "deep_link": "/check-in"
  },
  "ios_badgeType": "Increase",
  "ios_badgeCount": 1,
  ${DELIVERY}
}
JSON

if [[ "$DRY_RUN" == true ]]; then
  echo "DRY RUN — request that would be sent to OneSignal:"
  echo "$PAYLOAD"
  exit 0
fi

echo "Deploying campaign to OneSignal app ${APP_ID}…"

RESPONSE=$(curl --silent --show-error --fail-with-body \
  --request POST 'https://api.onesignal.com/notifications' \
  --header "Authorization: Key ${ONESIGNAL_REST_KEY}" \
  --header 'Content-Type: application/json' \
  --data "$PAYLOAD") || {
    echo "Campaign creation FAILED. Response above." >&2
    exit 1
  }

echo "$RESPONSE"
echo
echo "Done. Check OneSignal → Messages → Push for the campaign."
echo "If 'recipients' is 0, no user currently matches the filters — that is"
echo "the targeting working, not an error. Lower the last_session threshold"
echo "to test, or use the in-app Developer panel to exercise delivery."
