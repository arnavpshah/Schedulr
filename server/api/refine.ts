import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireApiKey } from "../lib/auth.js";
import {
  Anthropic,
  buildSchedulePrompt,
  callScheduler,
  SchedulerError,
} from "../lib/anthropic.js";
import { RefineRequest, type ScheduleResponse } from "../lib/schema.js";
import { validateAndRepair } from "../lib/validate.js";

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  const parsed = RefineRequest.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      error: "invalid_request",
      issues: parsed.error.issues,
    });
    return;
  }

  const body = parsed.data;
  const prefs = body.preferences ?? { bufferMinutes: 5, preferMornings: true };
  const basePrompt = buildSchedulePrompt(body, prefs);
  const userPrompt = [
    basePrompt,
    "",
    "Previous schedule (the user has now provided feedback below — produce a revised schedule):",
    formatPrevious(body.previous),
    "",
    `User feedback: ${body.feedback.trim()}`,
    "",
    "Produce the revised schedule now. Apply all hard rules from scratch — do not assume the previous schedule was valid.",
  ].join("\n");

  try {
    const { schedule, usage } = await callScheduler(userPrompt, { endpoint: "refine" });
    const repaired = validateAndRepair(body, schedule);
    res.status(200).json({ ...repaired, usage });
  } catch (err) {
    if (err instanceof SchedulerError) {
      res.status(err.status).json({ error: err.code });
      return;
    }
    if (err instanceof Anthropic.APIError) {
      res.status(err.status ?? 500).json({ error: "anthropic_api_error" });
      return;
    }
    console.error("refine_internal_error", err);
    res.status(500).json({ error: "internal_error" });
  }
}

function formatPrevious(prev: ScheduleResponse): string {
  const lines: string[] = [];
  if (prev.proposals.length === 0) {
    lines.push("  (no proposals)");
  } else {
    for (const p of prev.proposals) {
      lines.push(`  - taskId=${p.taskId} ${p.start} → ${p.end} — ${p.reasoning}`);
    }
  }
  if (prev.unscheduled.length > 0) {
    lines.push("  Previously unscheduled:");
    for (const u of prev.unscheduled) {
      lines.push(`    - taskId=${u.taskId} reason=${u.reason}`);
    }
  }
  if (prev.summary) {
    lines.push(`  Previous summary: ${prev.summary}`);
  }
  return lines.join("\n");
}
