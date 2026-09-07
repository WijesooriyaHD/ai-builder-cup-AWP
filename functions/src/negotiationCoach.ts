/**
 * negotiationCoach Cloud Function
 *
 * 2nd-gen Firebase Callable Function (Node.js 20, us-central1).
 * Powers the "Negotiation Lab" salary-negotiation roleplay: the model plays a
 * recruiter responding to the user's messages, and may append a single coaching
 * hint in the form "[Tip: ...]" which the client parses out and shows separately.
 *
 * - Accepts { messages: [{ role: 'user' | 'assistant', content: string }] }.
 * - Returns { reply: string }.
 * - On LLM failure, returns a safe fallback reply so the UI keeps working.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { VertexAI } from "@google-cloud/vertexai";
import { sanitize } from "./contentSafetyFilter";

// ─── Types ───────────────────────────────────────────────────────────────────

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface NegotiationCoachRequest {
  messages: ChatMessage[];
}

interface NegotiationCoachResponse {
  reply: string;
}

const FALLBACK_REPLY =
  "That's a fair point. Help me understand the value you'd bring so we can find a number that works for both of us. " +
  "[Tip: Anchor with market data and tie your ask to measurable impact.]";

// Cap history to keep the prompt bounded.
const MAX_MESSAGES = 20;

// ─── Validation ──────────────────────────────────────────────────────────────

function validateRequest(data: unknown): NegotiationCoachRequest {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request body must be a JSON object.");
  }

  const req = data as Record<string, unknown>;

  if (!Array.isArray(req.messages)) {
    throw new HttpsError("invalid-argument", "messages is required and must be an array.");
  }

  const messages: ChatMessage[] = (req.messages as unknown[])
    .map((m) => {
      const mm = (m ?? {}) as Record<string, unknown>;
      const role = mm.role === "assistant" ? "assistant" : "user";
      const content = typeof mm.content === "string" ? mm.content : "";
      return { role, content } as ChatMessage;
    })
    .filter((m) => m.content.trim().length > 0)
    .slice(-MAX_MESSAGES);

  return { messages };
}

// ─── Prompt Building ─────────────────────────────────────────────────────────

const SYSTEM_INSTRUCTION =
  "You are a sharp but supportive salary-negotiation coach roleplaying as a hiring recruiter. " +
  "Respond in character as the recruiter to the candidate's latest message: be realistic, " +
  "occasionally push back on their ask, and keep replies to 1-3 sentences. " +
  "After your recruiter reply, you MAY append exactly one coaching hint in the form " +
  "\"[Tip: ...]\" that teaches the candidate a negotiation tactic. Keep the whole response under 80 words. " +
  "Stay professional and encouraging. Do not use clinical or therapeutic language.";

function buildConversation(messages: ChatMessage[]): { role: string; parts: { text: string }[] }[] {
  // Map assistant→model for Vertex; ensure the conversation starts with a user turn.
  const mapped = messages.map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: m.content }],
  }));

  while (mapped.length > 0 && mapped[0].role !== "user") {
    mapped.shift();
  }

  // Fallback so we always send at least one user turn.
  if (mapped.length === 0) {
    mapped.push({
      role: "user",
      parts: [{ text: "Let's begin the salary negotiation." }],
    });
  }

  return mapped;
}

// ─── LLM Integration ─────────────────────────────────────────────────────────

async function callLLM(messages: ChatMessage[]): Promise<string | null> {
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
      temperature: 0.8,
      maxOutputTokens: 256,
    },
  });

  try {
    const result = await model.generateContent({
      contents: buildConversation(messages),
      systemInstruction: {
        role: "system",
        parts: [{ text: SYSTEM_INSTRUCTION }],
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

export const negotiationCoach = onCall<
  NegotiationCoachRequest,
  Promise<NegotiationCoachResponse>
>(
  {
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request): Promise<NegotiationCoachResponse> => {
    const { messages } = validateRequest(request.data);

    const raw = await callLLM(messages);
    const reply = raw ? sanitize(raw) : FALLBACK_REPLY;

    return { reply };
  }
);
