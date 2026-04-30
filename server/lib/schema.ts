import { z } from "zod";

export const BusyBlock = z.object({
  title: z.string(),
  start: z.string().datetime({ offset: true }),
  end: z.string().datetime({ offset: true }),
});
export type BusyBlock = z.infer<typeof BusyBlock>;

export const TaskInput = z.object({
  id: z.string(),
  title: z.string().min(1),
  estimatedMinutes: z.number().int().positive().max(8 * 60),
  priority: z.enum(["low", "normal", "high"]),
  deadline: z.string().datetime({ offset: true }).optional(),
  notes: z.string().optional(),
});
export type TaskInput = z.infer<typeof TaskInput>;

export const Preferences = z
  .object({
    bufferMinutes: z.number().int().min(0).max(60).default(5),
    preferMornings: z.boolean().default(true),
  })
  .default({ bufferMinutes: 5, preferMornings: true });
export type Preferences = z.infer<typeof Preferences>;

export const ScheduleRequest = z.object({
  day: z.string().datetime({ offset: true }),
  dayStart: z.string().datetime({ offset: true }),
  dayEnd: z.string().datetime({ offset: true }),
  timeZone: z.string(),
  busyBlocks: z.array(BusyBlock),
  tasks: z.array(TaskInput).min(1).max(50),
  preferences: Preferences.optional(),
});
export type ScheduleRequest = z.infer<typeof ScheduleRequest>;

export const Proposal = z.object({
  taskId: z.string(),
  start: z.string().datetime({ offset: true }),
  end: z.string().datetime({ offset: true }),
  reasoning: z.string(),
});
export type Proposal = z.infer<typeof Proposal>;

export const Unscheduled = z.object({
  taskId: z.string(),
  reason: z.string(),
});
export type Unscheduled = z.infer<typeof Unscheduled>;

export const ScheduleResponse = z.object({
  proposals: z.array(Proposal),
  unscheduled: z.array(Unscheduled),
  summary: z.string(),
});
export type ScheduleResponse = z.infer<typeof ScheduleResponse>;

export const RefineRequest = ScheduleRequest.extend({
  previous: ScheduleResponse,
  feedback: z.string().min(1).max(1000),
});
export type RefineRequest = z.infer<typeof RefineRequest>;

export const SCHEDULE_RESPONSE_JSON_SCHEMA = {
  type: "object" as const,
  properties: {
    proposals: {
      type: "array",
      items: {
        type: "object",
        properties: {
          taskId: { type: "string" },
          start: { type: "string", format: "date-time" },
          end: { type: "string", format: "date-time" },
          reasoning: { type: "string" },
        },
        required: ["taskId", "start", "end", "reasoning"],
        additionalProperties: false,
      },
    },
    unscheduled: {
      type: "array",
      items: {
        type: "object",
        properties: {
          taskId: { type: "string" },
          reason: { type: "string" },
        },
        required: ["taskId", "reason"],
        additionalProperties: false,
      },
    },
    summary: { type: "string" },
  },
  required: ["proposals", "unscheduled", "summary"],
  additionalProperties: false,
};
