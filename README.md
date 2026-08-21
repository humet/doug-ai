# Doug

Doug is a native iOS baking companion for planning and adapting sourdough bread bakes in the real world.

Instead of treating a recipe as a fixed timeline, Doug models the bake as a schedule with fermentation state, temperatures, starter/levain readiness, flexible steps, ingredient timing, and the baker's actual availability. An AI coach sits on top of that structured state so its advice is grounded in what is really happening to the dough rather than a generic recipe prompt.

## Why I built it

I started baking sourdough during lockdown and have kept at it ever since. I’ve used some very good baking apps along the way, but they tend to make the same assumption: that the baker is available whenever the recipe says they should be.

Real life does not work like that.

A stretch and fold might land during the school run. A meeting might overrun. Dinner plans change. The dough might ferment faster than expected. Most baking apps can tell you what should happen next, but they are much less useful when the human’s schedule changes.

Doug started as an attempt to solve that problem. Instead of treating a bake as a fixed sequence of timers, it models the process alongside the baker’s availability and adapts the schedule when reality changes.

The AI coach sits on top of that model to help explain the options and trade-offs, but the underlying timings, fermentation state and baking calculations remain deterministic.

## What it models

The native app includes domain logic for things such as:

- target-time scheduling across multi-stage bakes
- levain build/peak timing and starter state
- temperature-aware fermentation
- accumulated degree-hours during bulk fermentation
- live extrapolation beyond the last logged temperature reading
- recipe hydration and flour composition
- ingredient incorporation timing (mix, fold, topping)
- flexible/passive steps such as cold retard
- cascading schedule changes when steps finish early or late
- unavailable windows in the baker's day
- water-temperature recommendations
- persistent bake state and live activity updates

The goal is not to make an LLM perform baking arithmetic. The deterministic domain layer computes the facts; the coach receives those facts as context.

## AI coach

`doug-coach/` is a small TypeScript backend built with the Vercel AI SDK and AI Gateway.

It:

- validates the iOS payload with Zod
- builds a system prompt from the current bake/starter/availability state
- streams coaching responses back to the app over SSE
- exposes constrained tools/actions to the model
- can protect the endpoint with an optional bearer token

The coach currently routes through Vercel AI Gateway to Gemini.

## Architecture

```text
Native iOS app
    │
    ├── recipe + fermentation domain model
    ├── schedule builder / adjustment logic
    ├── persistent bake state
    ├── temperature + degree-hour calculations
    │
    └── structured bake context
             │
             ▼
       Doug Coach API
       (TypeScript + Zod)
             │
             ▼
      Vercel AI Gateway
             │
             ▼
        AI baking coach
```

The useful design boundary is between **facts** and **judgment**. Timing, temperatures, durations, ingredient quantities, and schedule state are computed in code. The model is used for explanation, prioritisation, and contextual coaching.

## Engineering examples

Some of the more interesting problems in the project have been about keeping the model and the real-world bake aligned:

- fixing a levain schedule that could accidentally create an idle gap or stretch a fixed fermentation phase to absorb calendar slack
- modelling blended flours explicitly so both the UI and coach know a dough is, for example, 40% whole wheat rather than simply “500g flour”
- carrying ingredient incorporation timing into both the deterministic steps and the AI context
- feeding the coach live extrapolated degree-hours so it does not reason from a stale reading captured at the final fold
- self-healing persisted schedule state when earlier logic produced an invalid duration

These changes are backed by focused domain tests rather than prompt-only fixes.

## Stack

### iOS

- Swift
- SwiftUI
- SwiftData
- Swift Testing
- Activity/live-state integrations

### Coach backend

- TypeScript
- Vercel AI SDK
- Vercel AI Gateway
- Zod
- Vercel Functions / Node

## Local coach development

```bash
cd doug-coach
npm install
cp .env.example .env
npm run dev
```

The development server exposes:

```text
POST http://localhost:3000/api/chat
```

Environment variables are documented in [`doug-coach/.env.example`](doug-coach/.env.example).

## Development approach

Doug is a personal project developed heavily with AI coding agents. I use agents for implementation and investigation, but keep the domain rules, architecture, and verification explicit in code and tests.

The project is a good example of where I find AI-assisted engineering most useful: the agent can move quickly across Swift and TypeScript, while deterministic domain modelling and tests provide the boundary for what “correct” means.

## Public-repository note

Local Xcode user data, environment files, Claude Code local memory/settings, and `Secrets.xcconfig` are intentionally ignored. The public repository should contain code and non-sensitive configuration only; deployments need their own AI Gateway credentials and optional coach API token.
