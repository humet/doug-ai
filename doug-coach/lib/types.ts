import { z } from "zod";

export const RecipeMethodStepSchema = z.object({
  stepTypeId: z.string(),
  label: z.string(),
  classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
  baseDurationMinutes: z.number(),
  flexRangeMin: z.number().optional(),
  flexRangeMax: z.number().optional(),
});

export const RecipeIngredientsSchema = z.object({
  flourGrams: z.number(),
  waterGrams: z.number(),
  saltGrams: z.number(),
  levainGrams: z.number(),
  extras: z
    .array(z.object({ name: z.string(), grams: z.number() }))
    .optional(),
});

export const BakeContextSchema = z.object({
  recipeId: z.string(),
  recipeName: z.string(),
  hydrationPercent: z.number(),
  kitchenTempCelsius: z.number(),
  targetBreadReadyTime: z.string().datetime(),
  recipeMethod: z.array(RecipeMethodStepSchema).optional(),
  recipeIngredients: RecipeIngredientsSchema.optional(),
  steps: z.array(
    z.object({
      stepTypeId: z.string(),
      label: z.string(),
      classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
      status: z.enum(["upcoming", "active", "done", "skipped"]),
      computedStartTime: z.string().datetime(),
      computedEndTime: z.string().datetime(),
      durationMinutes: z.number(),
      flexRangeMin: z.number().optional(),
      flexRangeMax: z.number().optional(),
    })
  ),
  temperatureReadings: z.array(
    z.object({
      timestamp: z.string().datetime(),
      temperatureCelsius: z.number(),
      accumulatedDegreeHours: z.number(),
      associatedStepTypeId: z.string().optional(),
    })
  ),
  degreeHourTarget: z.number(),
  delays: z.array(
    z.object({
      stepLabel: z.string(),
      delayMinutes: z.number(),
    })
  ),
});

export const StarterContextSchema = z.object({
  storageType: z.enum(["fridge", "counter"]),
  maintenanceCycleDays: z.number(),
  healthStatus: z.enum(["readyToBake", "needsFeed", "needsRevival"]),
  daysSinceLastFeed: z.number().nullable(),
  recentFeeds: z.array(
    z.object({
      timestamp: z.string().datetime(),
      ratio: z.string(),
      flourType: z.string(),
      kitchenTempCelsius: z.number(),
      timeToPeakMinutes: z.number().nullable(),
    })
  ),
  revivalPlan: z
    .object({
      isActive: z.boolean(),
      currentStep: z.number(),
      totalSteps: z.number(),
      peakTimeTrend: z.array(z.number()),
    })
    .nullable(),
});

export const AvailabilityContextSchema = z.object({
  unavailableWindows: z.array(
    z.object({
      start: z.string().datetime(),
      end: z.string().datetime(),
      label: z.string().optional(),
    })
  ),
});

export const ChatRequestSchema = z.object({
  messages: z.array(
    z.object({
      role: z.enum(["user", "assistant"]),
      content: z.string(),
    })
  ),
  currentTime: z.string().datetime(),
  context: BakeContextSchema.nullable(),
  starterContext: StarterContextSchema.nullable(),
  availabilityContext: AvailabilityContextSchema.nullable(),
});

export type BakeContext = z.infer<typeof BakeContextSchema>;
export type StarterContext = z.infer<typeof StarterContextSchema>;
export type AvailabilityContext = z.infer<typeof AvailabilityContextSchema>;
export type ChatRequest = z.infer<typeof ChatRequestSchema>;
