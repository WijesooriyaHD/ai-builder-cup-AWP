/**
 * generateDreamTasks Cloud Function
 *
 * 2nd-gen Firebase Callable Function (Node.js 20).
 * Breaks a user's wellness intention (e.g. "Learn Yoga") into a sequence of
 * small, actionable daily steps spanning the requested number of days.
 *
 * - Accepts `dream` (the intention title) and `days` (plan length).
 * - Calls Vertex AI (Gemini) to generate the step list.
 * - Applies the content safety filter to every step title.
 * - Falls back to a simple generated sequence if the LLM fails, so the
 *   client always receives usable tasks.
 *
 * Returns: { tasks: Array<{ title: string; isCompleted: boolean }> }
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { VertexAI } from "@google-cloud/vertexai";
import { containsBannedContent, sanitize } from "./contentSafetyFilter";

// ─── Types ───────────────────────────────────────────────────────────────────

interface GenerateDreamTasksRequest {
  dream: string;
  days: number;
}

interface DreamTask {
  title: string;
  duration: number;
  isCompleted: boolean;
}

// Default per-step duration in minutes (the client falls back to this too).
const DEFAULT_STEP_DURATION_MINUTES = 15;

interface GenerateDreamTasksResponse {
  tasks: DreamTask[];
}

// Clamp bounds for the number of steps we will generate.
const MIN_DAYS = 1;
const MAX_DAYS = 30;

// ─── Validation ──────────────────────────────────────────────────────────────

function validateRequest(data: unknown): GenerateDreamTasksRequest {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request body must be a JSON object.");
  }

  const req = data as Record<string, unknown>;

  if (!req.dream || typeof req.dream !== "string" || req.dream.trim().length === 0) {
    throw new HttpsError("invalid-argument", "dream is required and must be a non-empty string.");
  }

  // days is optional; default to 7 and clamp to [MIN_DAYS, MAX_DAYS].
  let days = 7;
  if (req.days !== undefined && req.days !== null) {
    const parsed = typeof req.days === "number" ? req.days : Number(req.days);
    if (Number.isFinite(parsed)) {
      days = Math.min(MAX_DAYS, Math.max(MIN_DAYS, Math.round(parsed)));
    }
  }

  return {
    dream: (req.dream as string).trim(),
    days,
  };
}

// ─── Prompt Building ─────────────────────────────────────────────────────────

function buildPrompt(dream: string, days: number): string {
  return `You are a supportive wellness companion. A user has set this wellness intention:

"${dream}"

Break this intention into exactly ${days} small, encouraging daily steps that gradually build toward it. Each step should be a single short action the user can complete in one day.

CONSTRAINTS:
- Return exactly ${days} steps, ordered from easiest first to most advanced last.
- Each step title must be 3 to 8 words, action-oriented, and beginner-friendly.
- Keep a calm, supportive, non-judgmental wellness tone.
- Do NOT use clinical or therapeutic language (avoid: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical).
- Do NOT mention calorie counts, step counts, streaks, or productivity metrics.

Respond ONLY with a valid JSON array of strings, e.g.:
["Set up a calm practice space", "Follow a 10-minute beginner flow"]
No markdown, no code fences, no extra text.`;
}

// ─── LLM Integration ─────────────────────────────────────────────────────────

async function callLLM(prompt: string): Promise<string[] | null> {
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
      maxOutputTokens: 1024,
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
        parts: [
          {
            text: "You are a supportive wellness companion. Respond ONLY with a JSON array of short step strings. No prose, no markdown, no code fences.",
          },
        ],
      },
    });

    const content = result.response.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!content) return null;

    return parseSteps(content);
  } catch (error) {
    console.error("Vertex AI call failed:", error);
    return null;
  }
}

/**
 * Parses the LLM output into a list of step strings.
 * Tolerates code fences and surrounding prose by extracting the JSON array.
 */
function parseSteps(raw: string): string[] | null {
  try {
    // Strip common markdown code-fence wrappers.
    let text = raw.replace(/```json/gi, "").replace(/```/g, "").trim();

    // Extract the first JSON array substring if extra text surrounds it.
    const start = text.indexOf("[");
    const end = text.lastIndexOf("]");
    if (start !== -1 && end !== -1 && end > start) {
      text = text.substring(start, end + 1);
    }

    const parsed = JSON.parse(text);
    if (!Array.isArray(parsed)) return null;

    const steps = parsed
      .map((item) => (typeof item === "string" ? item.trim() : String(item ?? "").trim()))
      .filter((s) => s.length > 0);

    return steps.length > 0 ? steps : null;
  } catch (error) {
    console.error("Failed to parse LLM step output:", error);
    return null;
  }
}

// ─── Fallback ────────────────────────────────────────────────────────────────

/**
 * Generates a simple, generic step sequence so the client always gets tasks
 * even when the LLM is unavailable.
 */
function buildFallbackSteps(dream: string, days: number): string[] {
  const templates = [
    `Reflect on why "${dream}" matters to you`,
    "Take one small step toward it today",
    "Set aside a few calm minutes to practice",
    "Notice how it makes you feel",
    "Build a gentle daily habit around it",
    "Celebrate a small win",
    "Keep going at your own pace",
  ];

  const steps: string[] = [];
  for (let i = 0; i < days; i++) {
    steps.push(templates[i % templates.length]);
  }
  return steps;
}

// ─── Task Assembly ───────────────────────────────────────────────────────────

/**
 * Normalizes raw step strings into DreamTask objects: sanitizes each title,
 * drops empties, and enforces exactly `days` tasks (pad with fallbacks / trim).
 */
function assembleTasks(rawSteps: string[], dream: string, days: number): DreamTask[] {
  const cleaned = rawSteps
    .map((title) => sanitize(title))
    .filter((title) => title.length > 0 && !containsBannedContent(title));

  const fallback = buildFallbackSteps(dream, days).map((t) => sanitize(t));

  // Pad if the LLM returned fewer than requested.
  while (cleaned.length < days) {
    cleaned.push(fallback[cleaned.length % fallback.length]);
  }

  // Trim if it returned more than requested.
  const finalTitles = cleaned.slice(0, days);

  return finalTitles.map((title) => ({
    title,
    duration: DEFAULT_STEP_DURATION_MINUTES,
    isCompleted: false,
  }));
}

// ─── Cloud Function ──────────────────────────────────────────────────────────

export const generateDreamTasks = onCall<
  GenerateDreamTasksRequest,
  Promise<GenerateDreamTasksResponse>
>(
  {
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request): Promise<GenerateDreamTasksResponse> => {
    const { dream, days } = validateRequest(request.data);

    const prompt = buildPrompt(dream, days);
    const llmSteps = await callLLM(prompt);

    // Use LLM output when available, otherwise fall back to a generic sequence.
    const rawSteps = llmSteps ?? buildFallbackSteps(dream, days);

    const tasks = assembleTasks(rawSteps, dream, days);

    return { tasks };
  }
);
