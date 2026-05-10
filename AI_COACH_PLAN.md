# AI Coach — Implementation Plan

## Overview

A baking coach powered by Claude, accessed through an in-app chat with contextual shortcut buttons. The coach can reason about the user's bake, starter, and schedule — and propose structured actions the user confirms before they're applied.

The backend is a Vercel AI SDK 6 API deployed to the Dexerto Vercel org. The iOS app sends bake context + messages and receives streamed responses with optional structured actions.

## Architecture

```
┌─────────────┐       HTTPS / SSE        ┌──────────────────────┐
│   iOS App   │ ◄──────────────────────► │  Vercel API Route    │
│             │  POST bake context +      │  (AI SDK 6)          │
│  ChatView   │  chat messages            │                      │
│  + buttons  │                           │  ToolLoopAgent       │
│             │  ◄─── streamed text +     │  + Claude Sonnet     │
│             │       action cards        │  + tool definitions  │
└─────────────┘                           │  + Zod schemas       │
                                          └──────────────────────┘
```

- **iOS app** sends the full bake/starter context + conversation history per request
- **Vercel API route** runs a `ToolLoopAgent` with Claude that can call tools
- **Tools** return structured JSON (Zod-validated) — the iOS app renders them as action cards
- **No server-side state** — conversation history lives in the app (SwiftData), sent with each request
- **Offline fallback** — static advice from staleness thresholds and existing offline logic

## Project Structure

```
doug/
├── Doug/                    # Existing iOS app
├── doug-coach/              # New — Vercel API
│   ├── api/
│   │   └── chat.ts          # Main chat endpoint
│   ├── lib/
│   │   ├── agent.ts         # ToolLoopAgent configuration
│   │   ├── tools.ts         # Tool definitions with Zod schemas
│   │   ├── prompt.ts        # System prompt
│   │   └── types.ts         # Shared TypeScript types
│   ├── package.json
│   ├── tsconfig.json
│   └── vercel.json
├── Doug.xcodeproj
└── ...
```

## Backend — Vercel AI SDK 6

### API Route: `POST /api/chat`

Request body from the iOS app:

```typescript
interface ChatRequest {
  messages: Message[]           // Conversation history
  context: BakeContext | null   // Current bake state (null if no active bake)
  starterContext: StarterContext | null
  availabilityContext: AvailabilityContext
}
```

### Bake Context (sent with every request during active bake)

```typescript
const BakeContextSchema = z.object({
  recipeId: z.string(),
  recipeName: z.string(),
  hydrationPercent: z.number(),
  kitchenTempCelsius: z.number(),
  targetBreadReadyTime: z.string().datetime(),
  steps: z.array(z.object({
    stepTypeId: z.string(),
    label: z.string(),
    classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
    status: z.enum(["upcoming", "active", "done", "skipped"]),
    computedStartTime: z.string().datetime(),
    computedEndTime: z.string().datetime(),
    durationMinutes: z.number(),
    flexRangeMin: z.number().optional(),
    flexRangeMax: z.number().optional(),
  })),
  temperatureReadings: z.array(z.object({
    timestamp: z.string().datetime(),
    temperatureCelsius: z.number(),
    accumulatedDegreeHours: z.number(),
    associatedStepTypeId: z.string().optional(),
  })),
  degreeHourTarget: z.number(),
  delays: z.array(z.object({
    stepLabel: z.string(),
    delayMinutes: z.number(),
  })),
})
```

### Starter Context

```typescript
const StarterContextSchema = z.object({
  storageType: z.enum(["fridge", "counter"]),
  maintenanceCycleDays: z.number(),
  healthStatus: z.enum(["readyToBake", "needsFeed", "needsRevival"]),
  daysSinceLastFeed: z.number().nullable(),
  recentFeeds: z.array(z.object({
    timestamp: z.string().datetime(),
    ratio: z.string(),                    // e.g. "1:5:5"
    flourType: z.string(),
    kitchenTempCelsius: z.number(),
    timeToPeakMinutes: z.number().nullable(),
  })),
  revivalPlan: z.object({
    isActive: z.boolean(),
    currentStep: z.number(),
    totalSteps: z.number(),
    peakTimeTrend: z.array(z.number()),   // minutes per feed
  }).nullable(),
})
```

### Tool Definitions

The agent has tools that return structured actions. These are NOT executed server-side — they're returned to the iOS app as action proposals.

```typescript
// Schedule adjustment tools — return proposals, not mutations
const tools = {
  adjustStepDuration: tool({
    description: "Propose changing a step's duration",
    parameters: z.object({
      stepTypeId: z.string(),
      newDurationMinutes: z.number(),
      reason: z.string(),
    }),
  }),

  delayStep: tool({
    description: "Propose delaying a step and cascading downstream",
    parameters: z.object({
      stepTypeId: z.string(),
      delayMinutes: z.number(),
      reason: z.string(),
    }),
  }),

  skipStep: tool({
    description: "Propose skipping a step entirely",
    parameters: z.object({
      stepTypeId: z.string(),
      reason: z.string(),
    }),
  }),

  addStep: tool({
    description: "Propose inserting a new step (e.g. room-temp proof instead of cold retard)",
    parameters: z.object({
      afterStepTypeId: z.string(),
      newStepLabel: z.string(),
      durationMinutes: z.number(),
      classification: z.enum(["handsOn", "passiveFlexible", "passiveFixed"]),
      reason: z.string(),
    }),
  }),

  resolveConflicts: tool({
    description: "Propose flex-step adjustments to clear all availability conflicts",
    parameters: z.object({
      adjustments: z.array(z.object({
        stepTypeId: z.string(),
        newDurationMinutes: z.number(),
      })),
      reason: z.string(),
    }),
  }),

  suggestFeedChange: tool({
    description: "Suggest a change to the next starter feed",
    parameters: z.object({
      ratio: z.string(),
      flourType: z.string(),
      reason: z.string(),
    }),
  }),
}
```

### Agent Configuration

```typescript
const coach = new ToolLoopAgent({
  model: anthropic("claude-sonnet-4-5-20250514"),
  instructions: systemPrompt,   // Sourdough expert, knows the app's data model
  tools,
  output: Output.object({
    schema: z.object({
      message: z.string(),      // The conversational response
      actions: z.array(z.object({
        toolName: z.string(),
        parameters: z.record(z.unknown()),
        displaySummary: z.string(),
      })).optional(),
    }),
  }),
})
```

### System Prompt (summary)

The system prompt establishes the coach as a sourdough expert who:
- Has access to the user's full bake context, starter history, and availability
- Reasons about dough behaviour, not just schedules
- Returns structured tool calls when actions are needed
- Never adjusts the schedule directly — always proposes
- Provides offline-appropriate advice (no "go Google it")
- Keeps responses concise — this is a mobile chat, not an essay
- Knows the app's step types, classifications, and flex ranges

## iOS App Changes

### New Files

```
Doug/
├── Services/
│   └── CoachService.swift        # HTTP client for the Vercel API
├── ViewModels/
│   └── CoachViewModel.swift      # Chat state, message history, action handling
├── Views/
│   └── Coach/
│       ├── CoachChatView.swift    # Full chat view (sheet)
│       ├── CoachMessageBubble.swift
│       ├── CoachActionCard.swift  # Inline action proposal with confirm/dismiss
│       └── CoachEntryButton.swift # FAB or contextual button to open chat
└── Models/
    └── SwiftData/
        └── CoachMessage.swift    # Persisted chat messages per bake
```

### CoachService

- Sends `ChatRequest` as JSON to `POST /api/chat`
- Streams the response via SSE (or receives full JSON for v1 simplicity)
- Parses action proposals from the structured output
- Falls back gracefully when offline

### CoachViewModel

- Holds `[CoachMessage]` for the current conversation
- Manages pending action proposals
- When user confirms an action, calls the appropriate ScheduleViewModel method:
  - `adjustStepDuration` → `extendStep` / `shortenStep`
  - `delayStep` → `delayStep`
  - `skipStep` → mark step as `.skipped`, cascade
  - `resolveConflicts` → batch adjust flex steps, cascade

### Entry Points (contextual buttons)

| Location | Button | Pre-filled context |
|----------|--------|--------------------|
| Staleness warning (NowStepHero) | "What should I do?" | "I'm {X} minutes late for {step}. Kitchen is {temp}°C. What should I do?" |
| Conflict banner | "Fix this" | "These steps have moved into unavailable time: {list}. Can you adjust the schedule?" |
| Revival plan (not improving) | "Help with revival" | "My starter is on day {N} of revival. Peak times: {trend}. Is this normal?" |
| Active bake header | Chat icon | Opens chat with no pre-fill — open-ended |
| Completed bake summary | "How did it go?" | "Here's my completed bake data: {summary}. What went well and what should I change next time?" |
| Settings / Starter tab | Chat icon | Opens chat with starter context only — for general questions |

### CoachActionCard (inline in chat)

When the AI proposes actions, they render as a card in the chat:

```
┌─────────────────────────────────────┐
│  Proposed changes                   │
│                                     │
│  ☐ Shorten autolyse to 30min       │
│    "Saves time without impact"      │
│                                     │
│  ☐ Extend cold retard to 14h       │
│    "Pushes shape to 7am tomorrow"   │
│                                     │
│  ☐ Skip stretch & fold 4           │
│    "Dough is developed enough"      │
│                                     │
│  [ Apply ]           [ Dismiss ]    │
└─────────────────────────────────────┘
```

Each action has a checkbox — the user can deselect individual items before applying. The "Apply" button executes only the checked actions via ScheduleViewModel.

## Phases

### Phase 1 — Backend + Chat Shell
- Set up `doug-coach/` Vercel project
- Implement `POST /api/chat` with ToolLoopAgent + Claude
- System prompt + tool definitions
- iOS: CoachService, CoachViewModel, basic CoachChatView
- iOS: Open chat from active bake header (open-ended only)
- No actions yet — text advice only

### Phase 2 — Structured Actions
- Add tool definitions that return action proposals
- iOS: CoachActionCard with confirm/dismiss
- Wire confirmed actions to ScheduleViewModel methods
- Add `skipStep` method to ScheduleViewModel (doesn't exist yet)

### Phase 3 — Contextual Entry Points
- Staleness "What should I do?" button
- Conflict banner "Fix this" button
- Revival "Help with revival" button
- Post-bake "How did it go?" button
- Pre-fill logic for each entry point

### Phase 4 — Starter & General
- Starter-specific advice (feed changes, revival coaching)
- Condition adaptation ("it's 35°C today")
- General open-ended questions about sourdough
- suggestFeedChange tool + confirmation flow

## Environment & Deployment

- **Vercel project:** `doug-coach` in the Dexerto Vercel org
- **Environment variables:** `ANTHROPIC_API_KEY` (server-side only — not in the iOS app for coach calls)
- **API URL:** Configured in iOS via xcconfig (`COACH_API_URL`)
- **Auth:** API key or short-lived token from the app to authenticate requests (prevents abuse). Simple approach for v1: a shared secret in xcconfig sent as a Bearer token.
- **Rate limiting:** Vercel edge middleware, per-device rate limit

## Key Principles

1. **AI reasons, scheduler executes.** The coach never touches time arithmetic. It proposes intents; the app's deterministic logic applies them.
2. **User always confirms.** No auto-applied AI suggestions. Every schedule change goes through a confirmation card.
3. **Context is king.** The coach's value comes from knowing the full bake state — temps, delays, availability, recipe. Generic advice is useless.
4. **Offline graceful.** When the API is unreachable, the app falls back to static staleness advice and mechanical conflict detection. No broken states.
5. **Prompts live server-side.** The system prompt, tool definitions, and reasoning can be improved without shipping app updates.
