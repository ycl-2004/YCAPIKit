# YCAPIKit

![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)
![SPM](https://img.shields.io/badge/SPM-supported-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)

> A resilient, observable hosted-LLM runtime for SwiftUI apps.

YCAPIKit is a reusable AI runtime layer that standardizes multi-provider LLM integration, reliability handling, structured output, and observability — so each app does not need to rebuild these systems from scratch.

---

## TL;DR

YCAPIKit provides:

* Multi-provider LLM integration (OpenAI, Gemini, Anthropic, NVIDIA, Mistral, Zhipu)
* Built-in retry, backoff, and fallback orchestration
* Route-based model selection (`primary / chunk / polish / repair`)
* Structured JSON validation with automatic recovery
* Request-level observability (latency, retry count, fallback path)

Designed as an **AI runtime layer**, not just an API wrapper.

---

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/ycl-2004/YCAPIKit.git", branch: "main")
```

Then add the product:

```swift
.product(name: "YCAPIKit", package: "YCAPIKit")
```

---

## Quick Start

### 1. Configure

```swift
import YCAPIKit

var configuration = HostedAIConfiguration.recommended(service: .openAI)
```

---

### 2. Create Client

```swift
let client = HostedAIClientFactory.makeClient(configuration: configuration)
```

---

### 3. Generate Text

```swift
let result = try await client.generateText(
    systemPrompt: "You summarize clearly.",
    userPrompt: "Summarize this in 5 bullet points."
)
```

---

### 4. Generate Structured JSON

```swift
struct Outline: Decodable {
    let title: String
    let bullets: [String]
}

let outline = try await client.generateJSON(
    systemPrompt: "Return JSON only.",
    userPrompt: "Create a short project outline.",
    as: Outline.self
)
```

---

## Example Use Cases

YCAPIKit is designed for production-style AI workflows:

* Summarizing long documents using `chunk + polish` routing
* Extracting structured JSON for downstream automation
* Retrying and failing over when providers degrade
* Switching providers without rewriting app logic
* Monitoring latency and failures in production

---

## Why YCAPIKit Exists

Most apps integrate AI by directly calling provider APIs.

This leads to:

* duplicated API wiring across apps
* inconsistent retry and fallback logic
* fragile structured-output parsing
* poor visibility into failures and latency
* no standardized model routing strategy

YCAPIKit solves these problems once and makes them reusable.

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
* timeout handling
* transient failure recovery (429, network errors)

---

### Fallback Routing

* provider fallback (e.g., OpenAI → Gemini)
* model fallback
* route fallback (`primary → repair`)

---

### Structured Output

* JSON schema decoding
* code fence stripping
* partial JSON extraction
* repair-route recovery

---

### Observability

Each request captures:

* provider and model
* route
* retry count
* fallback path
* latency
* outcome

Enables:

* latency monitoring
* failure tracking
* provider comparison

---

### Adaptive Routing (Future-ready)

Signals can be used for:

* latency-aware provider selection
* failure-driven routing
* cost optimization

---

## End-to-End Request Flow

1. App calls runtime (`generateText` / `generateJSON`)
2. Runtime selects provider and route model
3. Request sent via client
4. Retry + timeout applied
5. Response validated
6. Failure → retry / fallback / repair
7. Trace emitted
8. Result returned

---

## Failure Scenarios and Recovery

YCAPIKit assumes LLM systems fail.

Handles:

* timeouts
* rate limiting (`429`)
* malformed JSON
* provider outages

Recovery strategy:

* retry with backoff
* fallback route
* fallback provider
* repair JSON

---

## Comparison

| Capability         | Raw API | YCAPIKit           |
| ------------------ | ------- | ------------------ |
| Retry handling     | manual  | built-in           |
| Fallback           | none    | automatic          |
| Structured JSON    | fragile | validated + repair |
| Provider switching | hard    | configurable       |
| Observability      | minimal | built-in           |

---

## Project Structure

```
YCAPIKit/
├── Package.swift
├── README.md
├── Sources/
│   └── YCAPIKit/
├── Tests/
│   └── YCAPIKitTests/
```

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

* OPENAI_API_KEY
* ANTHROPIC_API_KEY
* GOOGLE_API_KEY / GEMINI_API_KEY
* NVIDIA_API_KEY
* MISTRAL_API_KEY
* ZHIPU_API_KEY

---

## Scope Boundaries

YCAPIKit is **not**:

* a memory system
* an agent framework
* a vector database
* a training system

It is a **hosted-LLM runtime layer**.

---

## Test Coverage

Includes tests for:

* retry handling
* provider fallback
* JSON repair
* routing logic
* configuration resolution

---

## Future Work

* streaming support
* adaptive routing
* evaluation harness
* token-aware context management

---

## License

MIT License
