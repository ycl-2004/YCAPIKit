# YCAIKit

> A resilient, observable hosted-LLM runtime for SwiftUI apps.

YCAIKit provides a reusable AI runtime layer that standardizes multi-provider LLM integration, reliability handling, structured output, and observability — so each app does not need to rebuild these systems from scratch.

---

## TL;DR

YCAIKit gives you:

* multi-provider LLM integration (OpenAI, Gemini, Anthropic, NVIDIA, Mistral, Zhipu)
* built-in retry, backoff, and fallback orchestration
* route-based model selection (`primary / chunk / polish / repair`)
* structured JSON validation with recovery
* request-level observability (latency, retries, fallback paths)

Designed as an **AI runtime layer**, not just an API wrapper.

---

## Quick Start

### 1. Add the package

```swift
.package(path: "../Packages/YCAIKit")
```

```swift
.product(name: "YCAIKit", package: "YCAIKit")
```

---

### 2. Add settings UI

```swift
import SwiftUI
import YCAIKit

struct SettingsScreen: View {
    @State private var configuration = HostedAIConfiguration.recommended(service: .openAI)

    var body: some View {
        Form {
            HostedAISettingsSection(configuration: $configuration)
        }
    }
}
```

---

### 3. Generate text

```swift
let client = HostedAIClientFactory.makeClient(configuration: configuration)

let result = try await client.generateText(
    systemPrompt: "You summarize clearly.",
    userPrompt: "Summarize this in 5 bullet points."
)
```

---

### 4. Generate structured JSON

```swift
struct Outline: Decodable {
    let title: String
    let bullets: [String]
}

let outline = try await client.generateJSON(
    systemPrompt: "Return JSON only.",
    userPrompt: "Create a short outline.",
    as: Outline.self
)
```

---

## Example Use Cases

YCAIKit is designed for production-style AI workflows:

* summarizing long documents with `chunk + polish` routing
* extracting structured JSON for downstream automation
* retrying and failing over when providers degrade
* switching providers without rewriting app logic
* monitoring latency and failures in production

Example scenarios:

* A notes app chunks large input, summarizes each part, then polishes the result.
* A backend tool extracts structured JSON and falls back to a repair route on failure.
* A mobile app switches providers during outages without impacting user flows.

---

## Why YCAIKit Exists

Most apps add AI features by calling provider APIs directly.

This leads to:

* duplicated API wiring across apps
* inconsistent retry and fallback behavior
* poor visibility into failures and latency
* fragile structured-output parsing
* no standardized model routing

YCAIKit solves these problems once and makes them reusable across applications.

---

## Design Philosophy

YCAIKit is built around:

* **App-agnostic** — no assumptions about product logic
* **Reliability-first** — failures are expected and handled
* **Structured over raw text** — machine-usable output matters
* **Explicit routing** — apps control cost / latency tradeoffs
* **Observable by default** — every request can be traced

---

## Architecture Overview

```
App Layer
   ↓
HostedAIRuntime
   ↓
HostedAIClient
   ↓
Provider Transport (OpenAI / Anthropic / Gemini / OpenAI-compatible)
   ↓
LLM APIs

Cross-cutting concerns:
- Retry / Backoff
- Fallback Routing
- Structured Output Parsing
- Request Tracing
```

---

## Core Runtime Capabilities

### Reliability

* configurable retry policies
* exponential backoff
* transient failure detection (timeouts, 429, 5xx)
* request timeouts and resource limits

---

### Fallback Routing

* provider fallback (e.g., OpenAI → Gemini)
* model fallback
* route fallback (`primary → repair`)
* configurable fallback strategies

---

### Structured Output

* JSON schema decoding
* code fence stripping
* partial JSON extraction
* repair-route recovery on failure

---

### Observability

Each request exposes:

* provider + model
* selected route
* retry count
* fallback index
* request duration
* outcome (success / failure)
* error category

This enables:

* latency dashboards
* failure monitoring
* provider comparison
* fallback-rate tracking

---

### Adaptive Routing (Future-ready)

The runtime already surfaces signals for:

* latency-aware provider selection
* failure-driven fallback decisions
* cost vs quality optimization
* dynamic routing strategies

---

## End-to-End Request Flow

1. App calls `HostedAIRuntime.generateText` or `generateJSON`
2. Runtime selects provider and route model
3. Request is sent via `HostedAIClient`
4. Transport applies timeout and retry policy
5. Response is validated (JSON if needed)
6. On failure:

   * retry → fallback route → fallback provider
7. Trace is emitted
8. Final result returned to the app

---

## Failure Scenarios And Recovery

YCAIKit assumes LLM systems fail.

Common failure modes:

* timeouts or network instability
* rate limiting (`429`)
* invalid structured output
* model unavailability

Recovery flow:

1. request fails
2. retry with backoff
3. fallback to:

   * repair route, or
   * backup provider
4. JSON validation may trigger repair route
5. trace captures retry + fallback path

This ensures continuity under degraded conditions.

---

## Comparison

| Capability         | Raw API Usage  | YCAIKit              |
| ------------------ | -------------- | -------------------- |
| Retry handling     | manual         | built-in             |
| Fallback routing   | custom per app | configurable runtime |
| Structured JSON    | fragile        | validated + repair   |
| Provider switching | invasive       | configuration-driven |
| Routing            | manual         | built-in             |
| Observability      | ad hoc         | trace hooks          |

---

## Benchmark Readiness

YCAIKit does not include fixed benchmarks, but exposes signals to measure:

* p50 / p95 latency
* retry rate
* fallback rate
* JSON failure rate
* provider reliability

This enables future evaluation dashboards.

---

## Test Coverage

Includes tests for:

* API key resolution
* environment fallback
* route model selection
* provider inference
* health checks
* JSON decoding (mocked)
* retry recovery (429)
* provider fallback
* repair-route fallback
* trace retry counts

---

## Supported Providers

* OpenAI-compatible APIs

  * OpenAI
  * NVIDIA
  * Mistral
  * Zhipu

* Native APIs

  * Anthropic
  * Google Gemini

---

## Environment Variables

* OpenAI: `YCAIKIT_OPENAI_API_KEY`, `OPENAI_API_KEY`
* Anthropic: `YCAIKIT_ANTHROPIC_API_KEY`
* Gemini: `YCAIKIT_GEMINI_API_KEY`, `GOOGLE_API_KEY`
* NVIDIA: `YCAIKIT_NVIDIA_API_KEY`
* Mistral: `YCAIKIT_MISTRAL_API_KEY`
* Zhipu: `YCAIKIT_ZHIPU_API_KEY`, `BIGMODEL_API_KEY`

---

## Route-Based Model Split

Supports:

* `primary`
* `chunk`
* `polish`
* `repair`

Used to balance:

* cost
* latency
* output quality

---

## Scope Boundaries

YCAIKit is **not**:

* a memory system
* a conversation/session manager
* a vector database
* an agent framework
* a training system

It is a **hosted-LLM runtime layer**.

---

## Future Work

* adaptive provider selection
* streaming response support
* token-aware context management
* per-user preference memory
* evaluation / benchmarking harness

---

## Talking Points

This project can be discussed as:

* multi-provider LLM runtime design
* retry + fallback strategies for unreliable systems
* structured-output validation pipelines
* observability for AI systems
* foundations for adaptive routing
