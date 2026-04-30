import Anthropic from "@anthropic-ai/sdk";
import {
  SCHEDULE_RESPONSE_JSON_SCHEMA,
  ScheduleResponse,
  type ScheduleRequest,
} from "./schema.js";

const anthropic = new Anthropic();

const SYSTEM_PROMPT = `You are Schedulr, an AI scheduling assistant. Given a user's day window, the busy blocks already on their calendar, and a list of tasks with estimated durations, you produce a concrete schedule that fits the tasks into the gaps.

Hard rules:
- Never overlap a busy block. Treat busy blocks as immovable.
- Stay strictly within the user's dayStart/dayEnd window.
- Each scheduled task must consume exactly its estimatedMinutes (start→end).
- Leave a buffer of at least preferences.bufferMinutes between adjacent items (busy or scheduled).
- Respect deadlines: a task with a deadline must finish on or before it.
- If a task cannot fit, place it in "unscheduled" with a brief reason. Never invent a slot that breaks the rules.

Soft preferences (apply in this priority order):
1. High-priority tasks first; place them in deeper, less interruptible blocks.
2. If preferences.preferMornings is true, schedule high-priority tasks before noon when possible.
3. Group similar tasks together when it doesn't conflict with priority.
4. Prefer larger uninterrupted blocks for tasks > 60 minutes.
5. Minimize fragmented short slots (<15 min unused gaps).

Output format:
- "proposals": one entry per task you schedule, with ISO 8601 datetimes including timezone offset, and a one-sentence reasoning.
- "unscheduled": tasks you couldn't fit, each with a reason.
- "summary": a 1-2 sentence overview of the resulting day.

Always return valid JSON matching the schema. Use ISO 8601 datetimes with the same timezone offset as the input dayStart/dayEnd.`;

export type Usage = {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number | null;
  cache_creation_input_tokens: number | null;
};

export async function callScheduler(
  userPrompt: string,
): Promise<{ schedule: ScheduleResponse; usage: Usage }> {
  const response = await anthropic.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 8000,
    thinking: { type: "adaptive" },
    output_config: {
      effort: "high",
      format: {
        type: "json_schema",
        schema: SCHEDULE_RESPONSE_JSON_SCHEMA,
      },
    },
    system: [
      {
        type: "text",
        text: SYSTEM_PROMPT,
        cache_control: { type: "ephemeral" },
      },
    ],
    messages: [{ role: "user", content: userPrompt }],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new SchedulerError("no_text_block_in_response", 502);
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(textBlock.text);
  } catch {
    throw new SchedulerError("model_returned_invalid_json", 502);
  }

  const parsed = ScheduleResponse.safeParse(parsedJson);
  if (!parsed.success) {
    throw new SchedulerError("model_response_failed_schema", 502);
  }

  return {
    schedule: parsed.data,
    usage: {
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      cache_read_input_tokens: response.usage.cache_read_input_tokens,
      cache_creation_input_tokens: response.usage.cache_creation_input_tokens,
    },
  };
}

export class SchedulerError extends Error {
  constructor(
    public code: string,
    public status: number,
  ) {
    super(code);
  }
}

export function buildSchedulePrompt(
  body: ScheduleRequest,
  prefs: { bufferMinutes: number; preferMornings: boolean },
): string {
  return [
    `Day: ${body.day}`,
    `Time zone: ${body.timeZone}`,
    `Working window: ${body.dayStart} → ${body.dayEnd}`,
    `Buffer between items: ${prefs.bufferMinutes} min`,
    `Prefer mornings for high-priority: ${prefs.preferMornings}`,
    "",
    "Existing busy blocks (do not overlap):",
    body.busyBlocks.length === 0
      ? "  (none)"
      : body.busyBlocks
          .map((b) => `  - ${b.start} → ${b.end} — ${b.title}`)
          .join("\n"),
    "",
    "Tasks to schedule:",
    body.tasks
      .map((t) => {
        const parts = [
          `  - id=${t.id}`,
          `title="${t.title}"`,
          `${t.estimatedMinutes} min`,
          `priority=${t.priority}`,
        ];
        if (t.deadline) parts.push(`deadline=${t.deadline}`);
        if (t.notes) parts.push(`notes="${t.notes}"`);
        return parts.join(" ");
      })
      .join("\n"),
    "",
    "Produce the schedule now.",
  ].join("\n");
}

export { Anthropic };
