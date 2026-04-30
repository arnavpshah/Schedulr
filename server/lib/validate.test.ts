import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { validateAndRepair } from "./validate.js";
import type { ScheduleRequest, ScheduleResponse, TaskInput } from "./schema.js";

function iso(hour: number, minute = 0): string {
  return `2026-04-30T${pad(hour)}:${pad(minute)}:00-07:00`;
}
function pad(n: number): string {
  return n.toString().padStart(2, "0");
}

function task(id: string, mins: number, deadline?: string): TaskInput {
  return {
    id,
    title: `Task ${id}`,
    estimatedMinutes: mins,
    priority: "normal",
    ...(deadline ? { deadline } : {}),
  };
}

function baseRequest(overrides: Partial<ScheduleRequest> = {}): ScheduleRequest {
  return {
    day: iso(0),
    dayStart: iso(9),
    dayEnd: iso(17),
    timeZone: "America/Los_Angeles",
    busyBlocks: [],
    tasks: [task("a", 60)],
    preferences: { bufferMinutes: 5, preferMornings: true },
    ...overrides,
  };
}

function response(overrides: Partial<ScheduleResponse> = {}): ScheduleResponse {
  return {
    proposals: [],
    unscheduled: [],
    summary: "test",
    ...overrides,
  };
}

describe("validateAndRepair", () => {
  it("accepts a valid proposal", () => {
    const req = baseRequest();
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10), end: iso(11), reasoning: "morning" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 1);
    assert.equal(out.unscheduled.length, 0);
  });

  it("rejects proposals that overlap a busy block", () => {
    const req = baseRequest({
      busyBlocks: [{ title: "Standup", start: iso(10), end: iso(10, 30) }],
    });
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10, 15), end: iso(11, 15), reasoning: "x" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 0);
    assert.equal(out.unscheduled.length, 1);
    assert.match(out.unscheduled[0]!.reason, /busy block/);
  });

  it("rejects proposals that violate buffer with a busy block", () => {
    const req = baseRequest({
      busyBlocks: [{ title: "Standup", start: iso(10), end: iso(10, 30) }],
    });
    const res = response({
      proposals: [
        // ends at 9:58, busy starts at 10:00 — only 2 min gap, buffer is 5
        { taskId: "a", start: iso(8, 58), end: iso(9, 58), reasoning: "x" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 0);
    assert.equal(out.unscheduled.length, 1);
  });

  it("rejects proposals that overlap each other", () => {
    const req = baseRequest({
      tasks: [task("a", 60), task("b", 60)],
    });
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10), end: iso(11), reasoning: "x" },
        { taskId: "b", start: iso(10, 30), end: iso(11, 30), reasoning: "y" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 1);
    assert.equal(out.proposals[0]!.taskId, "a");
    assert.equal(out.unscheduled.length, 1);
    assert.equal(out.unscheduled[0]!.taskId, "b");
  });

  it("rejects proposals outside the day window", () => {
    const req = baseRequest();
    const res = response({
      proposals: [
        { taskId: "a", start: iso(8), end: iso(9), reasoning: "early" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 0);
    assert.match(out.unscheduled[0]!.reason, /working window/);
  });

  it("rejects proposals that miss a deadline", () => {
    const req = baseRequest({
      tasks: [task("a", 60, iso(11))],
    });
    const res = response({
      proposals: [
        { taskId: "a", start: iso(11), end: iso(12), reasoning: "late" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 0);
    assert.match(out.unscheduled[0]!.reason, /deadline/);
  });

  it("rejects proposals with mismatched durations", () => {
    const req = baseRequest({
      tasks: [task("a", 60)],
    });
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10), end: iso(10, 45), reasoning: "short" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 0);
    assert.match(out.unscheduled[0]!.reason, /60 min/);
  });

  it("rejects proposals referencing unknown task ids", () => {
    const req = baseRequest();
    const res = response({
      proposals: [
        { taskId: "ghost", start: iso(10), end: iso(11), reasoning: "x" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 0);
    assert.match(out.unscheduled[0]!.reason, /unknown task/);
  });

  it("rejects duplicate scheduling of the same task", () => {
    const req = baseRequest();
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10), end: iso(11), reasoning: "first" },
        { taskId: "a", start: iso(13), end: iso(14), reasoning: "again" },
      ],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 1);
    assert.equal(out.unscheduled.length, 1);
    assert.match(out.unscheduled[0]!.reason, /more than once/);
  });

  it("fills in tasks the model silently dropped", () => {
    const req = baseRequest({
      tasks: [task("a", 60), task("b", 30)],
    });
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10), end: iso(11), reasoning: "ok" },
      ],
      // model didn't mention b
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 1);
    assert.equal(out.unscheduled.length, 1);
    assert.equal(out.unscheduled[0]!.taskId, "b");
    assert.match(out.unscheduled[0]!.reason, /not addressed/);
  });

  it("preserves explicit unscheduled entries from the model", () => {
    const req = baseRequest({
      tasks: [task("a", 60), task("b", 600)],
    });
    const res = response({
      proposals: [
        { taskId: "a", start: iso(10), end: iso(11), reasoning: "ok" },
      ],
      unscheduled: [{ taskId: "b", reason: "Too long for the day" }],
    });
    const out = validateAndRepair(req, res);
    assert.equal(out.proposals.length, 1);
    assert.equal(out.unscheduled.length, 1);
    assert.equal(out.unscheduled[0]!.reason, "Too long for the day");
  });
});
