/**
 * Firebase Cloud Functions for AI Wellness Pal.
 * All functions are 2nd-gen Callable Functions (Node.js 20).
 *
 * Only functions the app actually calls are exported (and so deployed).
 * The plan, reflection-prompt, weekly-summary, wellness-insight, dream-task
 * and negotiation-coach generators now run client-side through Firebase AI
 * Logic (App Check enforced); their old callable versions are no longer
 * exported so they can't be invoked directly and run up Gemini costs.
 */

export { journalInsight } from "./journalInsight";
export { sendReengagementPush } from "./sendReengagementPush";
