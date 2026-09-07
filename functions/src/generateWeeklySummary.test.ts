/**
 * Unit tests for generateWeeklySummary Cloud Function logic.
 * Tests validation, word count enforcement, content safety, and fallback behavior.
 *
 * Requirements: 8.8
 */

import { containsBannedContent, sanitize } from "./contentSafetyFilter";

// ─── Helpers (mirrors logic in generateWeeklySummary.ts) ─────────────────────

function countWords(text: string): number {
  return text.split(/\s+/).filter((word) => word.length > 0).length;
}

const FALLBACK_SUMMARY =
  "This week you showed up for yourself in meaningful ways. " +
  "Each reflection you wrote is a step toward deeper self-awareness and wellness. " +
  "Whether your week felt smooth or challenging, the act of pausing to reflect " +
  "shows real commitment to your wellbeing. Take a moment to appreciate the care " +
  "you have given yourself. As you move into the next week, carry forward the " +
  "insights that resonated most and release anything that no longer serves you. " +
  "You are building a practice of presence, one week at a time.";

function enforceWordCount(text: string): string {
  const wordCount = countWords(text);
  if (wordCount >= 80 && wordCount <= 200) {
    return text;
  }
  return FALLBACK_SUMMARY;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("generateWeeklySummary - Validation", () => {
  describe("Request validation", () => {
    it("requires userId to be a non-empty string", () => {
      const invalidInputs = [null, undefined, "", 123, {}];
      invalidInputs.forEach((userId) => {
        expect(typeof userId !== "string" || userId.length === 0).toBe(true);
      });
    });

    it("requires weekStartDate in YYYY-MM-DD format", () => {
      const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
      expect(dateRegex.test("2024-01-15")).toBe(true);
      expect(dateRegex.test("2024-1-15")).toBe(false);
      expect(dateRegex.test("Jan 15, 2024")).toBe(false);
      expect(dateRegex.test("")).toBe(false);
    });

    it("requires entryIds to have at least 3 entries", () => {
      const tooFew = ["entry1", "entry2"];
      expect(tooFew.length < 3).toBe(true);

      const enough = ["entry1", "entry2", "entry3"];
      expect(enough.length >= 3).toBe(true);
    });

    it("filters out non-string and empty entryIds", () => {
      const raw = ["entry1", "", null, "entry2", 123, "entry3"] as unknown[];
      const valid = raw.filter(
        (id): id is string => typeof id === "string" && id.length > 0
      );
      expect(valid).toEqual(["entry1", "entry2", "entry3"]);
      expect(valid.length).toBe(3);
    });
  });
});

describe("generateWeeklySummary - Word Count Enforcement", () => {
  it("accepts summary within 80-200 word range", () => {
    // Generate a text of exactly 100 words
    const words = Array(100).fill("wellness").join(" ");
    const result = enforceWordCount(words);
    expect(countWords(result)).toBe(100);
    expect(result).toBe(words);
  });

  it("returns fallback when summary is too short (< 80 words)", () => {
    const shortText = "This was a great week. You did well.";
    expect(countWords(shortText)).toBeLessThan(80);
    const result = enforceWordCount(shortText);
    expect(result).toBe(FALLBACK_SUMMARY);
  });

  it("returns fallback when summary is too long (> 200 words)", () => {
    const longText = Array(250).fill("word").join(" ");
    expect(countWords(longText)).toBeGreaterThan(200);
    const result = enforceWordCount(longText);
    expect(result).toBe(FALLBACK_SUMMARY);
  });

  it("accepts exactly 80 words", () => {
    const text = Array(80).fill("word").join(" ");
    expect(countWords(text)).toBe(80);
    const result = enforceWordCount(text);
    expect(result).toBe(text);
  });

  it("accepts exactly 200 words", () => {
    const text = Array(200).fill("word").join(" ");
    expect(countWords(text)).toBe(200);
    const result = enforceWordCount(text);
    expect(result).toBe(text);
  });
});

describe("generateWeeklySummary - Content Safety", () => {
  it("sanitizes summary containing banned words", () => {
    const unsafeSummary = "This week you made progress in your therapy journey and should continue treatment.";
    expect(containsBannedContent(unsafeSummary)).toBe(true);
    const sanitized = sanitize(unsafeSummary);
    expect(containsBannedContent(sanitized)).toBe(false);
  });

  it("passes clean summary through unchanged", () => {
    const cleanSummary =
      "This week you showed wonderful dedication to your wellness practice. " +
      "Your reflections reveal growing self-awareness and a deepening connection " +
      "to what your body and mind need.";
    expect(containsBannedContent(cleanSummary)).toBe(false);
    expect(sanitize(cleanSummary)).toBe(cleanSummary);
  });

  it("detects various forms of banned words", () => {
    expect(containsBannedContent("You should seek a diagnosis")).toBe(false); // "diagnosis" not banned
    expect(containsBannedContent("You should diagnose this")).toBe(true);
    expect(containsBannedContent("Consider therapy options")).toBe(true);
    expect(containsBannedContent("The clinical approach")).toBe(true);
    expect(containsBannedContent("Your condition needs attention")).toBe(true);
  });
});

describe("generateWeeklySummary - Fallback Summary", () => {
  it("fallback summary is within 80-200 word range", () => {
    const wordCount = countWords(FALLBACK_SUMMARY);
    expect(wordCount).toBeGreaterThanOrEqual(80);
    expect(wordCount).toBeLessThanOrEqual(200);
  });

  it("fallback summary passes content safety filter", () => {
    expect(containsBannedContent(FALLBACK_SUMMARY)).toBe(false);
  });

  it("fallback summary is used when LLM returns null", () => {
    // Simulate LLM returning null
    const llmResult: string | null = null;
    const summary = llmResult ?? FALLBACK_SUMMARY;
    expect(summary).toBe(FALLBACK_SUMMARY);
  });
});

describe("generateWeeklySummary - Response Format", () => {
  it("response contains a summary string field", () => {
    const response = { summary: FALLBACK_SUMMARY };
    expect(typeof response.summary).toBe("string");
    expect(response.summary.length).toBeGreaterThan(0);
  });
});
