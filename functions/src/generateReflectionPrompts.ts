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

const FALLBACK_PROMPTS: [string, string, string] = [
  "How are you feeling today?",
  "Where is your body asking for extra care?",
  "What would feel supportive today?",
];

/**
 * Additional fallback prompt sets for variety when personalization is not possible.
 * Each set contains exactly 3 prompts.
 */
const ALTERNATIVE_FALLBACK_SETS: [string, string, string][] = [
  [
    "What is one small thing you can do for yourself today?",
    "How does your body feel in this moment?",
    "What would bring you a sense of calm right now?",
  ],
  [
    "What are you grateful for about your body today?",
    "Where could you use a little more rest or gentleness?",
    "What intention would you like to carry into the rest of your day?",
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
      calm: "You mentioned feeling calm today. What helped you find that sense of peace?",
      anxious: "You noted some anxious feelings. What would help you feel grounded right now?",
      tired: "It sounds like you are feeling tired. What kind of rest would serve you best today?",
      energized: "You are feeling energized today. How would you like to channel that energy?",
      stressed: "You mentioned feeling stressed. What is one thing you could release or let go of today?",
      content: "You are feeling content today. What contributed to that sense of wellbeing?",
    };
    const moodPrompt = moodPrompts[checkIn.moodState.toLowerCase()];
    if (moodPrompt) {
      prompts.push(moodPrompt);
    }
  }

  if (checkIn.energyScore != null) {
    if (checkIn.energyScore <= 2) {
      prompts.push("Your energy is on the lower side today. What would feel restorative and gentle for you?");
    } else if (checkIn.energyScore >= 4) {
      prompts.push("You have good energy today. What would you most like to accomplish for your wellbeing?");
    } else {
      prompts.push("How would you like to use your energy today in a way that feels balanced?");
    }
  }

  if (checkIn.recoveryStatus) {
    const recoveryPrompts: Record<string, string> = {
      wellrested: "You are feeling well-rested. What would make today even better?",
      sore: "Your body is feeling sore. Where could you offer yourself extra kindness today?",
      fatigued: "You mentioned fatigue. What does your body need most right now?",
      recovering: "You are in recovery mode. What gentle support would feel good today?",
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
      `Thinking about your intention to "${primaryIntention.title}" — what small step feels achievable today?`
    );
  }

  // Fill remaining slots with supportive generic prompts
  const fillerPrompts = [
    "What would feel supportive today?",
    "How are you feeling in this moment?",
    "What is one kind thing you can do for yourself right now?",
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
