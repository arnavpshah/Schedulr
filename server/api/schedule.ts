import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireApiKey } from "../lib/auth.js";
import {
  Anthropic,
  buildSchedulePrompt,
  callScheduler,
  SchedulerError,
} from "../lib/anthropic.js";
import { ScheduleRequest } from "../lib/schema.js";
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

  const parsed = ScheduleRequest.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      error: "invalid_request",
      issues: parsed.error.issues,
    });
    return;
  }

  const body = parsed.data;
  const prefs = body.preferences ?? { bufferMinutes: 5, preferMornings: true };
  const userPrompt = buildSchedulePrompt(body, prefs);

  try {
    const { schedule, usage } = await callScheduler(userPrompt);
    const repaired = validateAndRepair(body, schedule);
    res.status(200).json({ ...repaired, usage });
  } catch (err) {
    if (err instanceof SchedulerError) {
      res.status(err.status).json({ error: err.code });
      return;
    }
    if (err instanceof Anthropic.APIError) {
      res.status(err.status ?? 500).json({
        error: "anthropic_api_error",
        message: err.message,
      });
      return;
    }
    res.status(500).json({
      error: "internal_error",
      message: err instanceof Error ? err.message : String(err),
    });
  }
}
