/**
 * journalInsight Cloud Function
 *
 * 2nd-gen Firebase Callable Function (Node.js 20, us-central1).
 * Generates a supportive reflection on a journal entry, or continues a
 * back-and-forth discussion about it.
 *
 * - Accepts { text: string, is_discussion?: boolean }.
 *   `text` may embed entry context and prior conversation (the client formats
 *   this). When `is_discussion` is true, respond conversationally; otherwise
 *   produce a single concise supportive insight.
 * - Returns { reply: string }. (The client also accepts `insight`/`message`,
 *   but we standardize on `reply`.)
 * - On LLM failure, returns a gentle fallback so the UI keeps working.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { VertexAI } from "@google-cloud/vertexai";
import { sanitize } from "./contentSafetyFilter";

// ─── Types ───────────────────────────────────────────────────────────────────

interface JournalInsightRequest {
  text: string;
  isDiscussion: boolean;
}

interface JournalInsightResponse {
  reply: string;
}

const FALLBACK_REPLY =
  "Thank you for sharing this. Taking a moment to reflect is a meaningful act of self-care. " +
  "Notice what you're feeling without judgment, and be gentle with yourself as you move through your day.";

// Guard against oversized prompts.
const MAX_TEXT_LENGTH = 6000;

// ─── Validation ──────────────────────────────────────────────────────────────

function validateRequest(data: unknown): JournalInsightRequest {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request body must be a JSON object.");
  }

  const req = data as Record<string, unknown>;

  if (!req.text || typeof req.text !== "string" || req.text.trim().length === 0) {
    throw new HttpsError("invalid-argument", "text is required and must be a non-empty string.");
  }

  let text = req.text as string;
  if (text.length > MAX_TEXT_LENGTH) {
    text = text.slice(0, MAX_TEXT_LENGTH);
  }

  return {
    text,
    isDiscussion: req.is_discussion === true,
  };
}

// ─── Prompt Building ─────────────────────────────────────────────────────────

function systemInstruction(isDiscussion: boolean): string {
  const base =
    "You are a warm, supportive wellness companion helping someone reflect on their journal. " +
    "Use a calm, non-judgmental, encouraging tone. Speak directly to the user with \"you\" and \"your\". " +
    "Do NOT use clinical or therapeutic language (avoid: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical). " +
    "Do NOT give medical, legal, or financial advice.";

  if (isDiscussion) {
    return (
      base +
      " You are in an ongoing conversation. Respond naturally to the user's latest message in 2-4 sentences, " +
      "referencing the journal context when helpful. Ask a gentle follow-up question when it feels supportive."
    );
  }

  return (
    base +
    " Provide a single concise supportive insight about the entry in 40-80 words. " +
    "Reflect back what you notice and offer one gentle, encouraging suggestion. Respond with plain text only."
  );
}

// ─── LLM Integration ─────────────────────────────────────────────────────────

async function callLLM(text: string, isDiscussion: boolean): Promise<string | null> {
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
      maxOutputTokens: isDiscussion ? 256 : 200,
    },
  });

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text }],
        },
      ],
      systemInstruction: {
        role: "system",
        parts: [{ text: systemInstruction(isDiscussion) }],
      },
    });

    const content = result.response.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    return content && content.length > 0 ? content : null;
  } catch (error) {
    console.error("Vertex AI call failed:", error);
    return null;
  }
}

// ─── Cloud Function ──────────────────────────────────────────────────────────

export const journalInsight = onCall<
  JournalInsightRequest,
  Promise<JournalInsightResponse>
>(
  {
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request): Promise<JournalInsightResponse> => {
    const { text, isDiscussion } = validateRequest(request.data);

    const raw = await callLLM(text, isDiscussion);
    const reply = raw ? sanitize(raw) : FALLBACK_REPLY;

    return { reply };
  }
);
