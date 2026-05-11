import { tool } from "ai";
import { z } from "zod";

export const coachTools = {
  adjustStepDuration: tool({
    description: "Propose changing a step's duration",
    inputSchema: z.object({
      stepTypeId: z.string(),
      newDurationMinutes: z.number(),
      reason: z.string(),
    }),
  }),

  delayStep: tool({
    description: "Propose delaying a step and cascading downstream",
    inputSchema: z.object({
      stepTypeId: z.string(),
      delayMinutes: z.number(),
      reason: z.string(),
    }),
  }),

  skipStep: tool({
    description: "Propose skipping a step entirely",
    inputSchema: z.object({
      stepTypeId: z.string(),
      reason: z.string(),
    }),
  }),

  addStep: tool({
    description:
      "Propose inserting a new step (e.g. room-temp proof instead of cold retard)",
    inputSchema: z.object({
      afterStepTypeId: z.string(),
      newStepLabel: z.string(),
      durationMinutes: z.number(),
      classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
      reason: z.string(),
    }),
  }),

  resolveConflicts: tool({
    description:
      "Propose flex-step adjustments to clear all availability conflicts",
    inputSchema: z.object({
      adjustments: z.array(
        z.object({
          stepTypeId: z.string(),
          newDurationMinutes: z.number(),
        })
      ),
      reason: z.string(),
    }),
  }),

  suggestFeedChange: tool({
    description: "Suggest a change to the next starter feed",
    inputSchema: z.object({
      ratio: z.string(),
      flourType: z.string(),
      reason: z.string(),
    }),
  }),
};
