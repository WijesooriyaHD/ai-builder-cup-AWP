/**
 * generateWeeklySummary Cloud Function
 *
 * 2nd-gen Firebase Callable Function (Node.js 20, us-central1).
 * Generates an 80–200 word weekly wellness reflection summary.
 *
 * - Only called when the user has Premium and ≥ 3 journal entries in the week.
 * - Accepts userId, weekStartDate, and entryIds.
 * - Uses OpenAI to generate a supportive weekly reflection.
 * - Applies content safety filter before returning.
 * - Returns a pre-written fallback summary if LLM fails.
 *
 * Requirements: 8.8
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { VertexAI } from "@google-cloud/vertexai";
import { containsBannedContent, sanitize } from "./contentSafetyFilter";

// ─── Types ───────────────────────────────────────────────────────────────────

interface GenerateWeeklySummaryRequest {
  userId: string;
  weekStartDate: string;
  entryIds: string[];
}

interface GenerateWeeklySummaryResponse {
  summary: string;
}

// ─── Fallback Summary ────────────────────────────────────────────────────────

const FALLBACK_SUMMARY =
  "This week you showed up for yourself in meaningful ways. " +
  "Each reflection you wrote is a step toward deeper self-awareness and wellness. " +
  "Whether your week felt smooth or challenging, the act of pausing to reflect " +
  "shows real commitment to your wellbeing. Take a moment to appreciate the care " +
  "you have given yourself. As you move into the next week, carry forward the " +
  "insights that resonated most and release anything that no longer serves you. " +
  "You are building a practice of presence, one week at a time.";

// ─── Validation ──────────────────────────────────────────────────────────────

function validateRequest(data: unknown): GenerateWeeklySummaryRequest {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request body must be a JSON object.");
  }

  const req = data as Record<string, unknown>;

  if (!req.userId || typeof req.userId !== "string") {
    throw new HttpsError("invalid-argument", "userId is required and must be a string.");
  }

  if (!req.weekStartDate || typeof req.weekStartDate !== "string") {
    throw new HttpsError("invalid-argument", "weekStartDate is required and must be a string.");
  }

  // Validate weekStartDate format (YYYY-MM-DD)
  const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
  if (!dateRegex.test(req.weekStartDate)) {
    throw new HttpsError(
      "invalid-argument",
      "weekStartDate must be in YYYY-MM-DD format."
    );
  }

  if (!Array.isArray(req.entryIds)) {
    throw new HttpsError("invalid-argument", "entryIds is required and must be an array.");
  }

  const entryIds = req.entryIds as unknown[];
  if (entryIds.length < 3) {
    throw new HttpsError(
      "failed-precondition",
      "At least 3 journal entries are required to generate a weekly summary."
    );
  }

  // Validate that all entryIds are strings
  const validEntryIds = entryIds.filter(
    (id): id is string => typeof id === "string" && id.length > 0
  );

  if (validEntryIds.length < 3) {
    throw new HttpsError(
      "failed-precondition",
      "At least 3 valid journal entry IDs are required."
    );
  }

  return {
    userId: req.userId as string,
    weekStartDate: req.weekStartDate as string,
    entryIds: validEntryIds,
  };
}

// ─── Prompt Building ─────────────────────────────────────────────────────────

function buildPrompt(request: GenerateWeeklySummaryRequest): string {
  const { weekStartDate, entryIds } = request;

  return `You are a warm, supportive wellness reflection companion. Generate a weekly wellness reflection summary for a user who completed ${entryIds.length} journal reflections during the week starting ${weekStartDate}.

REQUIREMENTS:
- Write a supportive, personalized weekly wellness reflection summary.
- The summary MUST be between 80 and 200 words (inclusive).
- Acknowledge the user's commitment to reflecting on their wellness.
- Offer gentle encouragement for the coming week.
- The tone must be calm, warm, supportive, intelligent, and non-judgmental.
- Do NOT use clinical or therapeutic language. Avoid words like: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical.
- Do NOT mention specific entry content (you don't have access to it).
- Do NOT count calories, steps, or use competitive/streak-based language.
- Frame reflections around self-awareness, growth, and gentle progress.

Write the summary as a single paragraph of flowing prose. Do not use bullet points or numbered lists.

Respond ONLY with the summary text, no JSON wrapping or additional formatting.`;
}

// ─── LLM Integration ─────────────────────────────────────────────────────────

async function callLLM(prompt: string): Promise<string | null> {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!projectId) {
    console.warn("GCP project ID not available. Returning null to trigger fallback.");
    return null;
  }

  const vertexAI = new VertexAI({
    project: projectId,
    location: "us-central1",
  });

  const model = vertexAI.getGenerativeModel({
    model: "gemini-2.0-flash-001",
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 400,
    },
  });

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: prompt }],
        },
      ],
      systemInstruction: {
        role: "system",
        parts: [{ text: "You are a wellness reflection companion. Write warm, supportive weekly summaries. Respond only with the summary text." }],
      },
    });

    const response = result.response;
    const content = response.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!content || content.length === 0) return null;

    return content;
  } catch (error) {
    console.error("Vertex AI call failed:", error);
    return null;
  }
}

// ─── Word Count Validation ───────────────────────────────────────────────────

function countWords(text: string): number {
  return text.split(/\s+/).filter((word) => word.length > 0).length;
}

function enforceWordCount(text: string): string {
  const wordCount = countWords(text);

  // If within range, return as-is
  if (wordCount >= 80 && wordCount <= 200) {
    return text;
  }

  // If too short or too long, use fallback
  return FALLBACK_SUMMARY;
}

// ─── Cloud Function ──────────────────────────────────────────────────────────

export const generateWeeklySummary = onCall<
  GenerateWeeklySummaryRequest,
  Promise<GenerateWeeklySummaryResponse>
>(
  {
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request): Promise<GenerateWeeklySummaryResponse> => {
    // Validate request data
    const validatedRequest = validateRequest(request.data);

    // Build the LLM prompt
    const prompt = buildPrompt(validatedRequest);

    // Call the LLM
    let summary = await callLLM(prompt);

    // If LLM fails, use fallback
    if (!summary) {
      return { summary: FALLBACK_SUMMARY };
    }

    // Enforce word count constraints (80–200 words)
    summary = enforceWordCount(summary);

    // Apply content safety filter
    summary = sanitize(summary);

    // Final verification: if sanitize replaced with generic fallback
    // (which is short), use our domain-specific fallback instead
    if (containsBannedContent(summary)) {
      return { summary: FALLBACK_SUMMARY };
    }

    return { summary };
  }
);
