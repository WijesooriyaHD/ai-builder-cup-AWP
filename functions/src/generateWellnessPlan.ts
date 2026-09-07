import { onCall, HttpsError } from "firebase-functions/v2/https";
import { VertexAI } from "@google-cloud/vertexai";
import { v4 as uuidv4 } from "uuid";
import { sanitizePlanResponse, containsBannedContent, sanitize } from "./contentSafetyFilter";

// ─── Types ───────────────────────────────────────────────────────────────────

interface CheckInData {
  energyScore?: number | null;
  moodState?: string | null;
  recoveryStatus?: string | null;
  availableTime?: string | null;
}

interface IntentionData {
  id: string;
  title: string;
  category: string;
}

interface RecentPlanData {
  date: string;
  completedActions?: string[];
}

interface GeneratePlanRequest {
  userId: string;
  checkIn: CheckInData;
  intentions: IntentionData[];
  recentPlans: RecentPlanData[];
}

interface WellnessAction {
  id: string;
  title: string;
  durationMinutes: number;
  category: string;
  intensityLevel: string;
}

interface DailyPlanResponse {
  id: string;
  date: string;
  todaysFocus: string;
  actions: WellnessAction[];
  totalTime: number;
  aiInsight?: string;
}

// ─── Validation ──────────────────────────────────────────────────────────────

const VALID_MOOD_STATES = ["calm", "anxious", "tired", "energized", "stressed", "content"];
const VALID_RECOVERY_STATUSES = ["wellRested", "sore", "fatigued", "recovering"];
const VALID_TIME_RANGES = ["under10", "range10_20", "range20_40", "range40_60", "over60"];
const VALID_CATEGORIES = [
  "flexibility", "stress", "sleep", "movement", "recovery",
  "energy", "mentalClarity", "mindfulness", "general",
];
const VALID_INTENSITY_LEVELS = ["low", "medium", "high"];

function validateRequest(data: unknown): GeneratePlanRequest {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request body must be a JSON object.");
  }

  const req = data as Record<string, unknown>;

  if (!req.userId || typeof req.userId !== "string") {
    throw new HttpsError("invalid-argument", "userId is required and must be a string.");
  }

  if (!req.checkIn || typeof req.checkIn !== "object") {
    throw new HttpsError("invalid-argument", "checkIn is required and must be an object.");
  }

  const checkIn = req.checkIn as Record<string, unknown>;

  // Validate energyScore if provided
  if (checkIn.energyScore != null) {
    const energy = Number(checkIn.energyScore);
    if (!Number.isInteger(energy) || energy < 1 || energy > 5) {
      throw new HttpsError("invalid-argument", "energyScore must be an integer between 1 and 5.");
    }
  }

  // Validate moodState if provided
  if (checkIn.moodState != null && typeof checkIn.moodState === "string") {
    if (!VALID_MOOD_STATES.includes(checkIn.moodState)) {
      throw new HttpsError("invalid-argument", `moodState must be one of: ${VALID_MOOD_STATES.join(", ")}`);
    }
  }

  // Validate recoveryStatus if provided
  if (checkIn.recoveryStatus != null && typeof checkIn.recoveryStatus === "string") {
    if (!VALID_RECOVERY_STATUSES.includes(checkIn.recoveryStatus)) {
      throw new HttpsError("invalid-argument", `recoveryStatus must be one of: ${VALID_RECOVERY_STATUSES.join(", ")}`);
    }
  }

  // Validate availableTime if provided
  if (checkIn.availableTime != null && typeof checkIn.availableTime === "string") {
    if (!VALID_TIME_RANGES.includes(checkIn.availableTime)) {
      throw new HttpsError("invalid-argument", `availableTime must be one of: ${VALID_TIME_RANGES.join(", ")}`);
    }
  }

  // Validate intentions array
  if (!Array.isArray(req.intentions)) {
    throw new HttpsError("invalid-argument", "intentions must be an array.");
  }

  // Validate recentPlans array
  if (!Array.isArray(req.recentPlans)) {
    throw new HttpsError("invalid-argument", "recentPlans must be an array.");
  }

  return {
    userId: req.userId as string,
    checkIn: {
      energyScore: checkIn.energyScore != null ? Number(checkIn.energyScore) : null,
      moodState: (checkIn.moodState as string) || null,
      recoveryStatus: (checkIn.recoveryStatus as string) || null,
      availableTime: (checkIn.availableTime as string) || null,
    },
    intentions: (req.intentions as Record<string, unknown>[]).map((i) => ({
      id: String(i.id || ""),
      title: String(i.title || ""),
      category: String(i.category || "general"),
    })),
    recentPlans: (req.recentPlans as Record<string, unknown>[]).map((p) => ({
      date: String(p.date || ""),
      completedActions: Array.isArray(p.completedActions)
        ? (p.completedActions as string[])
        : [],
    })),
  };
}

// ─── Prompt Building ─────────────────────────────────────────────────────────

function getTimeUpperBound(availableTime: string | null | undefined): number {
  switch (availableTime) {
    case "under10": return 10;
    case "range10_20": return 20;
    case "range20_40": return 40;
    case "range40_60": return 60;
    case "over60": return 90;
    default: return 30; // default moderate time
  }
}

function buildPrompt(request: GeneratePlanRequest): string {
  const { checkIn, intentions, recentPlans } = request;

  const energyLabel = checkIn.energyScore != null
    ? `Energy: ${checkIn.energyScore}/5`
    : "Energy: not provided";
  const moodLabel = checkIn.moodState ? `Mood: ${checkIn.moodState}` : "Mood: not provided";
  const recoveryLabel = checkIn.recoveryStatus
    ? `Recovery: ${checkIn.recoveryStatus}`
    : "Recovery: not provided";
  const timeLabel = checkIn.availableTime
    ? `Available time: ${checkIn.availableTime}`
    : "Available time: not provided";

  const maxTime = getTimeUpperBound(checkIn.availableTime);
  const actionCount = "2 to 4";

  const intensityConstraint = (checkIn.energyScore != null && checkIn.energyScore <= 2)
    ? "IMPORTANT: The user has low energy. Do NOT include any action with intensityLevel 'high'. Only use 'low' or 'medium' intensity."
    : "";

  const intentionsList = intentions.length > 0
    ? intentions.map((i) => `- ${i.title} (${i.category})`).join("\n")
    : "- No specific intentions set";

  const recentPlansSummary = recentPlans.length > 0
    ? recentPlans.slice(0, 7).map((p) =>
        `- ${p.date}: completed [${(p.completedActions || []).join(", ")}]`
      ).join("\n")
    : "No recent plan history";

  return `You are a supportive wellness planning assistant. Generate a personalized daily wellness plan.

USER STATE:
${energyLabel}
${moodLabel}
${recoveryLabel}
${timeLabel}

WELLNESS INTENTIONS:
${intentionsList}

RECENT PLAN HISTORY (last 7 days):
${recentPlansSummary}

CONSTRAINTS:
- Generate exactly ${actionCount} wellness actions.
- Total time of all actions MUST NOT exceed ${maxTime} minutes.
- Each action must have: id (short unique string), title, durationMinutes, category, intensityLevel.
- Valid categories: ${VALID_CATEGORIES.join(", ")}
- Valid intensity levels: low, medium, high
${intensityConstraint}
- Provide a "todaysFocus" label (2-5 words) that captures the theme of today's plan.
- Optionally provide an "aiInsight" (30-80 words) explaining the reasoning behind today's plan.
- Do NOT use clinical or therapeutic language. Avoid words like: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical.
- The tone must be calm, supportive, and non-judgmental.

Respond ONLY with valid JSON in this exact format:
{
  "todaysFocus": "string",
  "actions": [
    { "id": "string", "title": "string", "durationMinutes": number, "category": "string", "intensityLevel": "string" }
  ],
  "aiInsight": "string or null"
}`;
}

// ─── Constraint Enforcement ──────────────────────────────────────────────────

function enforceConstraints(
  plan: Record<string, unknown>,
  request: GeneratePlanRequest
): DailyPlanResponse {
  const today = new Date().toISOString().split("T")[0];
  const planId = `plan_${uuidv4().slice(0, 8)}`;

  let actions: WellnessAction[] = [];

  if (Array.isArray(plan.actions)) {
    actions = (plan.actions as Record<string, unknown>[]).map((a, idx) => ({
      id: typeof a.id === "string" ? a.id : `a${idx + 1}`,
      title: typeof a.title === "string" ? a.title : "Wellness Activity",
      durationMinutes: typeof a.durationMinutes === "number" ? Math.max(1, Math.round(a.durationMinutes)) : 5,
      category: (typeof a.category === "string" && VALID_CATEGORIES.includes(a.category))
        ? a.category : "general",
      intensityLevel: (typeof a.intensityLevel === "string" && VALID_INTENSITY_LEVELS.includes(a.intensityLevel))
        ? a.intensityLevel : "low",
    }));
  }

  // Constraint: 2–4 actions
  if (actions.length < 2) {
    // Pad with filler actions
    while (actions.length < 2) {
      actions.push({
        id: `a${actions.length + 1}`,
        title: "5-Minute Deep Breathing",
        durationMinutes: 5,
        category: "mindfulness",
        intensityLevel: "low",
      });
    }
  } else if (actions.length > 4) {
    actions = actions.slice(0, 4);
  }

  // Constraint: if energyScore ≤ 2, no high-intensity actions
  const energyScore = request.checkIn.energyScore;
  if (energyScore != null && energyScore <= 2) {
    actions = actions.map((action) => {
      if (action.intensityLevel === "high") {
        return { ...action, intensityLevel: "medium" };
      }
      return action;
    });
  }

  // Constraint: if availableTime = "under10", totalTime ≤ 10
  const maxTime = getTimeUpperBound(request.checkIn.availableTime);
  let totalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);

  if (request.checkIn.availableTime === "under10" && totalTime > 10) {
    // Scale down durations proportionally
    const scale = 10 / totalTime;
    actions = actions.map((action) => ({
      ...action,
      durationMinutes: Math.max(1, Math.floor(action.durationMinutes * scale)),
    }));
    totalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);

    // If still over due to rounding, trim the last action
    while (totalTime > 10 && actions.length > 2) {
      const last = actions[actions.length - 1];
      if (last.durationMinutes > 1) {
        actions[actions.length - 1] = { ...last, durationMinutes: last.durationMinutes - 1 };
      } else {
        actions.pop();
      }
      totalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);
    }
  } else if (totalTime > maxTime) {
    // General time constraint: scale down if exceeding max
    const scale = maxTime / totalTime;
    actions = actions.map((action) => ({
      ...action,
      durationMinutes: Math.max(1, Math.floor(action.durationMinutes * scale)),
    }));
    totalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);
  }

  // Ensure totalTime = sum of durationMinutes (recalculate)
  totalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);

  const todaysFocus = typeof plan.todaysFocus === "string" && plan.todaysFocus.length > 0
    ? plan.todaysFocus
    : "Daily Wellness";

  const aiInsight = typeof plan.aiInsight === "string" && plan.aiInsight.length > 0
    ? plan.aiInsight
    : undefined;

  return {
    id: planId,
    date: today,
    todaysFocus,
    actions,
    totalTime,
    ...(aiInsight ? { aiInsight } : {}),
  };
}

// ─── LLM Integration ─────────────────────────────────────────────────────────

async function callLLM(prompt: string): Promise<Record<string, unknown> | null> {
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
      maxOutputTokens: 800,
      responseMimeType: "application/json",
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
        parts: [{ text: "You are a wellness planning assistant. Respond only with valid JSON." }],
      },
    });

    const response = result.response;
    const content = response.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!content) return null;

    return JSON.parse(content) as Record<string, unknown>;
  } catch (error) {
    console.error("Vertex AI call failed:", error);
    return null;
  }
}

// ─── Fallback Plan ───────────────────────────────────────────────────────────

function generateFallbackPlan(request: GeneratePlanRequest): DailyPlanResponse {
  const energyScore = request.checkIn.energyScore ?? 3;
  const isLowEnergy = energyScore <= 2;
  const availableTime = request.checkIn.availableTime || "range20_40";
  const maxTime = getTimeUpperBound(availableTime);

  let actions: WellnessAction[];
  let todaysFocus: string;

  if (isLowEnergy) {
    todaysFocus = "Gentle Recovery";
    actions = [
      { id: "f1", title: "5-Minute Deep Breathing", durationMinutes: 5, category: "mindfulness", intensityLevel: "low" },
      { id: "f2", title: "Gentle Stretching", durationMinutes: Math.min(5, maxTime - 5), category: "flexibility", intensityLevel: "low" },
    ];
  } else if (energyScore >= 4) {
    todaysFocus = "Active Wellness";
    actions = [
      { id: "f1", title: "Morning Movement Flow", durationMinutes: Math.min(15, maxTime - 5), category: "movement", intensityLevel: "medium" },
      { id: "f2", title: "Breathwork Cool-Down", durationMinutes: 5, category: "mindfulness", intensityLevel: "low" },
    ];
  } else {
    todaysFocus = "Balanced Wellness";
    actions = [
      { id: "f1", title: "10-Minute Gentle Walk", durationMinutes: Math.min(10, maxTime - 5), category: "movement", intensityLevel: "low" },
      { id: "f2", title: "5-Minute Mindful Breathing", durationMinutes: 5, category: "mindfulness", intensityLevel: "low" },
    ];
  }

  // Ensure total doesn't exceed max time
  const totalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);
  if (totalTime > maxTime) {
    const scale = maxTime / totalTime;
    actions = actions.map((a) => ({
      ...a,
      durationMinutes: Math.max(1, Math.floor(a.durationMinutes * scale)),
    }));
  }

  const finalTotalTime = actions.reduce((sum, a) => sum + a.durationMinutes, 0);

  return {
    id: `plan_${uuidv4().slice(0, 8)}`,
    date: new Date().toISOString().split("T")[0],
    todaysFocus,
    actions,
    totalTime: finalTotalTime,
  };
}

// ─── Cloud Function ──────────────────────────────────────────────────────────

export const generateWellnessPlan = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "256MiB",
    minInstances: 0,
  },
  async (request) => {
    // Validate request data
    const validatedRequest = validateRequest(request.data);

    // Build the LLM prompt
    const prompt = buildPrompt(validatedRequest);

    // Call the LLM
    let rawPlan = await callLLM(prompt);

    // If LLM fails, use fallback
    if (!rawPlan) {
      const fallback = generateFallbackPlan(validatedRequest);
      return fallback;
    }

    // Enforce constraints on the LLM output
    const plan = enforceConstraints(rawPlan, validatedRequest);

    // Apply content safety filter to all string fields
    const safePlan = sanitizePlanResponse(plan as unknown as Record<string, unknown>);

    // Final validation: if any field was replaced by fallback due to banned content,
    // double-check it doesn't still contain banned words
    if (typeof safePlan.todaysFocus === "string" && containsBannedContent(safePlan.todaysFocus)) {
      safePlan.todaysFocus = "Daily Wellness";
    }

    if (typeof safePlan.aiInsight === "string" && containsBannedContent(safePlan.aiInsight)) {
      delete safePlan.aiInsight;
    }

    return safePlan as unknown as DailyPlanResponse;
  }
);
