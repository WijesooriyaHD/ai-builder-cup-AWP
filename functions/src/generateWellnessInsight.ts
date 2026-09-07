/**
 * generateWellnessInsight Cloud Function
 *
 * 2nd-gen Firebase Callable Function (Node.js 20).
 * Generates a 30–80 word personalized wellness insight explaining the reasoning
 * behind today's plan.
 *
 * - Accepts userId, planId, and planSummary.
 * - Calls OpenAI to generate a concise insight string.
 * - Applies content safety filter before returning.
 * - Returns null/empty insight on LLM failure.
 *
 * Requirements: 3.12
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { VertexAI } from "@google-cloud/vertexai";
import { containsBannedContent, sanitize } from "./contentSafetyFilter";

// ─── Types ───────────────────────────────────────────────────────────────────

interface GenerateWellnessInsightRequest {
  userId: string;
  planId: string;
  // Always a string internally — the request may send it as an object
  // (a structured plan/reflection summary) or a plain string; we normalize.
  planSummary: string;
}

interface GenerateWellnessInsightResponse {
  insight: string;
}

// ─── Validation ──────────────────────────────────────────────────────────────

/**
 * Normalizes an incoming planSummary into a readable string prompt fragment.
 * Accepts a plain string, or a structured object such as
 *   { todaysFocus, actions: [{title, category, durationMinutes}], totalTime }
 * or the reflection shape { entryTitle, entryContent }.
 */
function normalizePlanSummary(value: unknown): string | null {
  if (typeof value === "string") {
    return value.trim().length > 0 ? value.trim() : null;
  }
  if (value && typeof value === "object") {
    const obj = value as Record<string, unknown>;

    // Reflection-context shape.
    if (typeof obj.entryContent === "string") {
      const title = typeof obj.entryTitle === "string" && obj.entryTitle.trim()
        ? `Title: ${obj.entryTitle}\n`
        : "";
      return `${title}Reflection: ${obj.entryContent}`.trim();
    }

    // Daily-plan shape.
    const parts: string[] = [];
    if (typeof obj.todaysFocus === "string") {
      parts.push(`Today's focus: ${obj.todaysFocus}`);
    }
    if (Array.isArray(obj.actions)) {
      const actionLines = (obj.actions as unknown[])
        .map((a) => {
          const am = (a ?? {}) as Record<string, unknown>;
          const title = typeof am.title === "string" ? am.title : "";
          const category = typeof am.category === "string" ? ` (${am.category})` : "";
          const dur = typeof am.durationMinutes === "number" ? ` — ${am.durationMinutes} min` : "";
          return title ? `- ${title}${category}${dur}` : "";
        })
        .filter((l) => l.length > 0);
      if (actionLines.length > 0) {
        parts.push(`Actions:\n${actionLines.join("\n")}`);
      }
    }
    if (typeof obj.totalTime === "number") {
      parts.push(`Total time: ${obj.totalTime} min`);
    }

    const joined = parts.join("\n");
    return joined.trim().length > 0 ? joined : null;
  }
  return null;
}

function validateRequest(data: unknown): GenerateWellnessInsightRequest {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request body must be a JSON object.");
  }

  const req = data as Record<string, unknown>;

  if (!req.userId || typeof req.userId !== "string") {
    throw new HttpsError("invalid-argument", "userId is required and must be a string.");
  }

  // planId is optional: the reflection-insight path does not send one.
  const planId = typeof req.planId === "string" ? req.planId : "";

  const planSummary = normalizePlanSummary(req.planSummary);
  if (!planSummary) {
    throw new HttpsError(
      "invalid-argument",
      "planSummary is required and must be a non-empty string or object."
    );
  }

  return {
    userId: req.userId as string,
    planId,
    planSummary,
  };
}

// ─── Prompt Building ─────────────────────────────────────────────────────────

function buildPrompt(planSummary: string): string {
  return `You are a supportive wellness companion. Based on the following daily wellness plan summary, generate a brief personalized insight explaining why this plan was chosen for the user today.

PLAN SUMMARY:
${planSummary}

CONSTRAINTS:
- Your response must be between 30 and 80 words.
- Use a calm, supportive, and non-judgmental tone.
- Explain the reasoning behind today's plan choices.
- Do NOT use clinical or therapeutic language. Avoid words like: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical.
- Do NOT mention calorie counts, step counts, streaks, or productivity metrics.
- Speak directly to the user using "you" and "your".

Respond ONLY with the insight text (no JSON, no quotes, no labels). Just the plain text insight.`;
}

// ─── LLM Integration ─────────────────────────────────────────────────────────

async function callLLM(prompt: string): Promise<string | null> {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!projectId) {
    console.warn("GCP project ID not available. Returning null.");
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
      maxOutputTokens: 150,
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
        parts: [{ text: "You are a supportive wellness companion. Respond only with plain text, no JSON or formatting." }],
      },
    });

    const response = result.response;
    const content = response.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!content) return null;

    return content;
  } catch (error) {
    console.error("Vertex AI call failed:", error);
    return null;
  }
}

// ─── Word Count Validation ───────────────────────────────────────────────────

/**
 * Checks if the insight falls within the 30–80 word range.
 * If too long, trims to 80 words. If too short, returns null to indicate failure.
 */
function enforceWordCount(insight: string): string | null {
  const words = insight.split(/\s+/).filter((w) => w.length > 0);

  if (words.length < 30) {
    // Too short — treat as a failure
    return null;
  }

  if (words.length > 80) {
    // Trim to 80 words and add trailing period if missing
    const trimmed = words.slice(0, 80).join(" ");
    return trimmed.endsWith(".") ? trimmed : trimmed + ".";
  }

  return insight;
}

// ─── Cloud Function ──────────────────────────────────────────────────────────

export const generateWellnessInsight = onCall<
  GenerateWellnessInsightRequest,
  Promise<GenerateWellnessInsightResponse>
>(
  {
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request): Promise<GenerateWellnessInsightResponse> => {
    // Validate request data
    const validatedRequest = validateRequest(request.data);

    // Build the LLM prompt
    const prompt = buildPrompt(validatedRequest.planSummary);

    // Call the LLM
    let insight = await callLLM(prompt);

    // If LLM fails, return empty insight
    if (!insight) {
      return { insight: "" };
    }

    // Enforce word count constraints (30–80 words)
    insight = enforceWordCount(insight);

    // If word count enforcement failed (too short), return empty
    if (!insight) {
      return { insight: "" };
    }

    // Apply content safety filter
    insight = sanitize(insight);

    // Double-check: if sanitize replaced with fallback but it still has issues
    if (containsBannedContent(insight)) {
      return { insight: "" };
    }

    return { insight };
  }
);
