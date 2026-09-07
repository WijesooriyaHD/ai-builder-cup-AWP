/**
 * Server-side Content Safety Filter.
 * Mirrors the client-side Dart implementation.
 * Ensures no clinical/therapeutic language appears in AI-generated responses.
 */

const BANNED_WORDS: string[] = [
  "diagnose",
  "diagnoses",
  "diagnosing",
  "treat",
  "treatment",
  "treating",
  "treated",
  "therapy",
  "therapeutic",
  "therapist",
  "therapists",
  "disorder",
  "disorders",
  "symptom",
  "symptoms",
  "condition",
  "conditions",
  "clinical",
  "clinically",
];

const FALLBACK_MESSAGE =
  "We're here to support your wellness journey. How are you feeling right now?";

/**
 * Checks whether the given text contains any banned clinical/therapeutic words.
 */
export function containsBannedContent(text: string): boolean {
  const lower = text.toLowerCase();
  return BANNED_WORDS.some((word) => {
    const regex = new RegExp(`\\b${word}\\b`, "i");
    return regex.test(lower);
  });
}

/**
 * Returns the original text if safe, or the fallback message if banned content is detected.
 */
export function sanitize(text: string): string {
  return containsBannedContent(text) ? FALLBACK_MESSAGE : text;
}

/**
 * Sanitizes all string fields in a DailyPlan response object.
 * Applies content safety filter to todaysFocus, aiInsight, and all action titles.
 */
export function sanitizePlanResponse(plan: Record<string, unknown>): Record<string, unknown> {
  const sanitized = { ...plan };

  if (typeof sanitized.todaysFocus === "string") {
    sanitized.todaysFocus = sanitize(sanitized.todaysFocus);
  }

  if (typeof sanitized.aiInsight === "string") {
    sanitized.aiInsight = sanitize(sanitized.aiInsight);
  }

  if (Array.isArray(sanitized.actions)) {
    sanitized.actions = (sanitized.actions as Record<string, unknown>[]).map((action) => {
      const sanitizedAction = { ...action };
      if (typeof sanitizedAction.title === "string") {
        sanitizedAction.title = sanitize(sanitizedAction.title);
      }
      return sanitizedAction;
    });
  }

  return sanitized;
}
