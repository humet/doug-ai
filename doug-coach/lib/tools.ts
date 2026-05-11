import { tool } from "ai";
import { z } from "zod";

export const coachTools = {
  adjustStepDuration: tool({
    description: "Propose changing a step's duration. Use when the baker needs to shorten or extend a step to fix timing, adapt to temperature, or recover from delays.",
    inputSchema: z.object({
      stepTypeId: z.string().describe("The step type ID to adjust"),
      newDurationMinutes: z.number().describe("New total duration in minutes"),
      reason: z.string().describe("Brief explanation for the baker"),
    }),
    execute: async ({ stepTypeId, newDurationMinutes, reason }) =>
      `Proposed: set ${stepTypeId} to ${newDurationMinutes}min. ${reason}`,
  }),

  delayStep: tool({
    description: "Propose delaying a step and cascading all downstream steps. Use when the baker is running late and needs the schedule shifted forward.",
    inputSchema: z.object({
      stepTypeId: z.string().describe("The step type ID to delay"),
      delayMinutes: z.number().describe("Minutes to push forward"),
      reason: z.string().describe("Brief explanation for the baker"),
    }),
    execute: async ({ stepTypeId, delayMinutes, reason }) =>
      `Proposed: delay ${stepTypeId} by ${delayMinutes}min. ${reason}`,
  }),

  skipStep: tool({
    description: "Propose skipping a step entirely and cascading downstream. Use when a step is no longer needed due to timing, temperature, or dough condition.",
    inputSchema: z.object({
      stepTypeId: z.string().describe("The step type ID to skip"),
      reason: z.string().describe("Brief explanation for the baker"),
    }),
    execute: async ({ stepTypeId, reason }) =>
      `Proposed: skip ${stepTypeId}. ${reason}`,
  }),

  addStep: tool({
    description: "Propose inserting a new step after an existing one. Use sparingly — only when the bake genuinely needs a step not in the original recipe.",
    inputSchema: z.object({
      afterStepTypeId: z.string().describe("Insert after this step"),
      newStepLabel: z.string().describe("Human-readable name"),
      durationMinutes: z.number(),
      classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
      reason: z.string().describe("Brief explanation for the baker"),
    }),
    execute: async ({ newStepLabel, durationMinutes, reason }) =>
      `Proposed: add "${newStepLabel}" (${durationMinutes}min). ${reason}`,
  }),

  resolveConflicts: tool({
    description: "Propose batch adjustments to flex steps to clear all scheduling conflicts at once. Use when multiple steps have moved into unavailable windows.",
    inputSchema: z.object({
      adjustments: z.array(
        z.object({
          stepTypeId: z.string(),
          newDurationMinutes: z.number(),
        })
      ),
      reason: z.string().describe("Brief explanation of the overall strategy"),
    }),
    execute: async ({ adjustments, reason }) =>
      `Proposed: adjust ${adjustments.length} steps. ${reason}`,
  }),

  suggestFeedChange: tool({
    description: "Suggest a change to the next starter feed ratio or flour type.",
    inputSchema: z.object({
      ratio: z.string().describe("Feed ratio e.g. '1:5:5'"),
      flourType: z.string().describe("Flour type e.g. 'whole wheat'"),
      reason: z.string().describe("Brief explanation for the baker"),
    }),
    execute: async ({ ratio, flourType, reason }) =>
      `Suggested: feed ${ratio} with ${flourType}. ${reason}`,
  }),
};
