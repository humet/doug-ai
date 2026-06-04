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
    .array(
      z.object({
        name: z.string(),
        grams: z.number(),
        // When the extra goes into the dough.
        incorporation: z.enum(["mix", "fold", "topping"]).optional(),
      })
    )
    .optional(),
  // Flour blend by type (e.g. whole wheat vs white). Present only when the
  // recipe specifies more than one flour.
  flourBreakdown: z
    .array(z.object({ name: z.string(), grams: z.number() }))
    .optional(),
});

export const BakeContextSchema = z.object({
  recipeId: z.string(),
  recipeName: z.string(),
  hydrationPercent: z.number(),
  kitchenTempCelsius: z.number(),
  targetBreadReadyTime: z.string().datetime({ offset: true }),
  recipeMethod: z.array(RecipeMethodStepSchema).optional(),
  recipeIngredients: RecipeIngredientsSchema.optional(),
  steps: z.array(
    z.object({
      stepTypeId: z.string(),
      label: z.string(),
      classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
      status: z.enum(["upcoming", "active", "done", "skipped"]),
      computedStartTime: z.string().datetime({ offset: true }),
      computedEndTime: z.string().datetime({ offset: true }),
      durationMinutes: z.number(),
      flexRangeMin: z.number().optional(),
      flexRangeMax: z.number().optional(),
    })
  ),
  temperatureReadings: z.array(
    z.object({
      timestamp: z.string().datetime({ offset: true }),
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
      timestamp: z.string().datetime({ offset: true }),
      ratio: z.string(),
      flourType: z.string(),
      kitchenTempCelsius: z.number(),
      timeToPeakMinutes: z.number().nullable(),
      intent: z.string().optional(),
      starterGrams: z.number().nullable().optional(),
      flourGrams: z.number().nullable().optional(),
      waterGrams: z.number().nullable().optional(),
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
      start: z.string().datetime({ offset: true }),
      end: z.string().datetime({ offset: true }),
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
  currentTime: z.string().datetime({ offset: true }),
  timeZone: z.string().optional(),
  context: BakeContextSchema.nullable(),
  starterContext: StarterContextSchema.nullable(),
  availabilityContext: AvailabilityContextSchema.nullable(),
});

export type BakeContext = z.infer<typeof BakeContextSchema>;
export type StarterContext = z.infer<typeof StarterContextSchema>;
export type AvailabilityContext = z.infer<typeof AvailabilityContextSchema>;
export type ChatRequest = z.infer<typeof ChatRequestSchema>;
