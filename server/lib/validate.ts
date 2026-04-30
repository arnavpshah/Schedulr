import type {
  Proposal,
  ScheduleRequest,
  ScheduleResponse,
  TaskInput,
  Unscheduled,
} from "./schema.js";

const DURATION_TOLERANCE_MS = 60_000;

export function validateAndRepair(
  request: ScheduleRequest,
  response: ScheduleResponse,
): ScheduleResponse {
  const prefs = request.preferences ?? { bufferMinutes: 5, preferMornings: true };
  const bufferMs = prefs.bufferMinutes * 60_000;
  const dayStart = ts(request.dayStart);
  const dayEnd = ts(request.dayEnd);
  const tasksById = new Map<string, TaskInput>();
  for (const task of request.tasks) tasksById.set(task.id, task);

  const accepted: Proposal[] = [];
  const rejected: Unscheduled[] = [];
  const seenTaskIds = new Set<string>();

  const sortedProposals = [...response.proposals].sort(
    (a, b) => ts(a.start) - ts(b.start),
  );

  const busyIntervals = request.busyBlocks
    .map((b) => ({ start: ts(b.start), end: ts(b.end) }))
    .filter((b) => Number.isFinite(b.start) && Number.isFinite(b.end));

  for (const proposal of sortedProposals) {
    const task = tasksById.get(proposal.taskId);
    if (!task) {
      rejected.push({
        taskId: proposal.taskId,
        reason: "Proposal references unknown task id.",
      });
      continue;
    }

    if (seenTaskIds.has(proposal.taskId)) {
      rejected.push({
        taskId: proposal.taskId,
        reason: "Task was scheduled more than once.",
      });
      continue;
    }

    const start = ts(proposal.start);
    const end = ts(proposal.end);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
      rejected.push({
        taskId: proposal.taskId,
        reason: "Proposal had invalid start/end times.",
      });
      continue;
    }

    if (start < dayStart || end > dayEnd) {
      rejected.push({
        taskId: proposal.taskId,
        reason: "Proposal fell outside the working window.",
      });
      continue;
    }

    const expectedMs = task.estimatedMinutes * 60_000;
    if (Math.abs(end - start - expectedMs) > DURATION_TOLERANCE_MS) {
      rejected.push({
        taskId: proposal.taskId,
        reason: `Duration did not match estimated ${task.estimatedMinutes} min.`,
      });
      continue;
    }

    if (task.deadline) {
      const deadline = ts(task.deadline);
      if (Number.isFinite(deadline) && end > deadline) {
        rejected.push({
          taskId: proposal.taskId,
          reason: "Proposal finished after the task deadline.",
        });
        continue;
      }
    }

    const busyConflict = busyIntervals.find((b) =>
      overlapsWithBuffer(start, end, b.start, b.end, bufferMs),
    );
    if (busyConflict) {
      rejected.push({
        taskId: proposal.taskId,
        reason: "Proposal overlapped (or violated buffer with) a busy block.",
      });
      continue;
    }

    const acceptedConflict = accepted.find((p) =>
      overlapsWithBuffer(start, end, ts(p.start), ts(p.end), bufferMs),
    );
    if (acceptedConflict) {
      rejected.push({
        taskId: proposal.taskId,
        reason: "Proposal overlapped (or violated buffer with) another scheduled task.",
      });
      continue;
    }

    accepted.push(proposal);
    seenTaskIds.add(proposal.taskId);
  }

  const existingUnscheduled = response.unscheduled.filter(
    (u) => !seenTaskIds.has(u.taskId) && tasksById.has(u.taskId),
  );

  const allRejectedIds = new Set([
    ...existingUnscheduled.map((u) => u.taskId),
    ...rejected.map((r) => r.taskId),
  ]);
  for (const task of request.tasks) {
    if (!seenTaskIds.has(task.id) && !allRejectedIds.has(task.id)) {
      rejected.push({
        taskId: task.id,
        reason: "Task was not addressed in the model output.",
      });
      allRejectedIds.add(task.id);
    }
  }

  return {
    proposals: accepted,
    unscheduled: [...existingUnscheduled, ...rejected],
    summary: response.summary,
  };
}

function ts(iso: string): number {
  return new Date(iso).getTime();
}

function overlapsWithBuffer(
  aStart: number,
  aEnd: number,
  bStart: number,
  bEnd: number,
  bufferMs: number,
): boolean {
  return aStart < bEnd + bufferMs && bStart < aEnd + bufferMs;
}
