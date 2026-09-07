import { containsBannedContent, sanitize, sanitizePlanResponse } from "./contentSafetyFilter";

describe("ContentSafetyFilter", () => {
  describe("containsBannedContent", () => {
    it("detects banned word 'therapy'", () => {
      expect(containsBannedContent("Try some therapy today")).toBe(true);
    });

    it("detects banned word 'diagnose'", () => {
      expect(containsBannedContent("We can diagnose your issues")).toBe(true);
    });

    it("detects banned word 'clinical'", () => {
      expect(containsBannedContent("A clinical approach works best")).toBe(true);
    });

    it("detects inflected forms like 'treating'", () => {
      expect(containsBannedContent("Treating your condition")).toBe(true);
    });

    it("detects 'disorders'", () => {
      expect(containsBannedContent("Managing sleep disorders")).toBe(true);
    });

    it("detects 'symptoms'", () => {
      expect(containsBannedContent("Watch for symptoms")).toBe(true);
    });

    it("is case-insensitive", () => {
      expect(containsBannedContent("THERAPY is great")).toBe(true);
      expect(containsBannedContent("Clinical Assessment")).toBe(true);
    });

    it("returns false for safe text", () => {
      expect(containsBannedContent("How are you feeling today?")).toBe(false);
    });

    it("returns false for empty string", () => {
      expect(containsBannedContent("")).toBe(false);
    });

    it("does not match partial words (e.g., 'condition' inside 'unconditional')", () => {
      // 'unconditional' contains 'condition' but with word boundary check it should not match
      // NOTE: actually 'conditional' does not match since we check 'condition' with \b
      expect(containsBannedContent("I love unconditionally")).toBe(false);
    });
  });

  describe("sanitize", () => {
    it("returns original text if safe", () => {
      const text = "Take a gentle walk today";
      expect(sanitize(text)).toBe(text);
    });

    it("returns fallback message if banned content found", () => {
      const text = "This therapy session will help";
      expect(sanitize(text)).toBe(
        "We're here to support your wellness journey. How are you feeling right now?"
      );
    });
  });

  describe("sanitizePlanResponse", () => {
    it("sanitizes todaysFocus if it contains banned words", () => {
      const plan = {
        id: "plan_123",
        todaysFocus: "Therapy Recovery",
        actions: [{ id: "a1", title: "Stretch", durationMinutes: 5 }],
        totalTime: 5,
      };
      const result = sanitizePlanResponse(plan);
      expect(result.todaysFocus).toBe(
        "We're here to support your wellness journey. How are you feeling right now?"
      );
    });

    it("sanitizes action titles if they contain banned words", () => {
      const plan = {
        id: "plan_123",
        todaysFocus: "Gentle Recovery",
        actions: [
          { id: "a1", title: "Diagnose your stress levels", durationMinutes: 5 },
          { id: "a2", title: "Gentle Breathing", durationMinutes: 5 },
        ],
        totalTime: 10,
      };
      const result = sanitizePlanResponse(plan);
      const actions = result.actions as Array<Record<string, unknown>>;
      expect(actions[0].title).toBe(
        "We're here to support your wellness journey. How are you feeling right now?"
      );
      expect(actions[1].title).toBe("Gentle Breathing");
    });

    it("sanitizes aiInsight if it contains banned words", () => {
      const plan = {
        id: "plan_123",
        todaysFocus: "Daily Wellness",
        actions: [],
        totalTime: 0,
        aiInsight: "This clinical approach addresses your condition.",
      };
      const result = sanitizePlanResponse(plan);
      expect(result.aiInsight).toBe(
        "We're here to support your wellness journey. How are you feeling right now?"
      );
    });

    it("preserves safe content unchanged", () => {
      const plan = {
        id: "plan_123",
        todaysFocus: "Gentle Movement",
        actions: [{ id: "a1", title: "Morning Stretch", durationMinutes: 10 }],
        totalTime: 10,
        aiInsight: "Today focuses on gentle mobility to support your flexibility goal.",
      };
      const result = sanitizePlanResponse(plan);
      expect(result.todaysFocus).toBe("Gentle Movement");
      expect(result.aiInsight).toBe(
        "Today focuses on gentle mobility to support your flexibility goal."
      );
    });
  });
});
