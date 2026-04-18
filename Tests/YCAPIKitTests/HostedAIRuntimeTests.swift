import Foundation
import Testing
@testable import YCAPIKit

struct HostedAIRuntimeTests {
    @Test
    func runtimeTraceCapturesRetryCountForRecoveredRequest() async throws {
        let traces = LockedBox<[HostedAIRequestTrace]>([])
        let attempts = LockedBox(0)
        let session = makeMockedSession { request in
            guard request.url?.path == "/v1/chat/completions" else {
                Issue.record("Unexpected request path: \(request.url?.path ?? "nil")")
                return (500, Data("{}".utf8))
            }

            let attempt = attempts.withValue {
                $0 += 1
                return $0
            }

            if attempt == 1 {
                let payload = """
                {"error":{"message":"gateway timeout"}}
                """
                return (504, Data(payload.utf8))
            }

            let payload = """
            {"choices":[{"message":{"content":"Recovered on retry"}}]}
            """
            return (200, Data(payload.utf8))
        }

        let configuration = HostedAIConfiguration(
            service: .openAI,
            apiKeysByService: [HostedAIService.openAI.rawValue: "openai-key"]
        )

        let runtime = HostedAIRuntime(
            configuration: configuration,
            retryPolicy: HostedAIRetryPolicy(
                maxAttempts: 2,
                initialBackoff: 0,
                backoffMultiplier: 1,
                maxBackoff: 0
            ),
            session: session
        ) { trace in
            traces.withValue { $0.append(trace) }
        }

        let response = try await runtime.generateText(
            systemPrompt: "Reply with a short recovery confirmation.",
            userPrompt: "Confirm recovery."
        )

        let capturedTraces = traces.snapshot()
        #expect(response == "Recovered on retry")
        #expect(capturedTraces.count == 1)
        #expect(capturedTraces[0].outcome == .success)
        #expect(capturedTraces[0].retryCount == 1)
    }

    @Test
    func runtimeFallsBackToSecondaryProviderAndEmitsTraceEvents() async throws {
        let traces = LockedBox<[HostedAIRequestTrace]>([])
        let session = makeMockedSession { request in
            switch request.url?.path {
            case "/v1/chat/completions":
                let payload = """
                {"error":{"message":"gateway timeout"}}
                """
                return (503, Data(payload.utf8))
            case "/v1beta/models/gemini-2.5-flash:generateContent":
                let payload = """
                {"candidates":[{"content":{"parts":[{"text":"Gemini fallback success"}]}}]}
                """
                return (200, Data(payload.utf8))
            default:
                Issue.record("Unexpected request path: \(request.url?.path ?? "nil")")
                return (500, Data("{}".utf8))
            }
        }

        let primary = HostedAIConfiguration(
            service: .openAI,
            apiKeysByService: [HostedAIService.openAI.rawValue: "openai-key"]
        )
        let fallback = HostedAIConfiguration(
            service: .gemini,
            apiKeysByService: [HostedAIService.gemini.rawValue: "gemini-key"]
        )

        let runtime = HostedAIRuntime(
            configuration: primary,
            fallbackTargets: [HostedAIRequestTarget(configuration: fallback)],
            retryPolicy: HostedAIRetryPolicy(
                maxAttempts: 1,
                initialBackoff: 0,
                backoffMultiplier: 1,
                maxBackoff: 0
            ),
            session: session
        ) { trace in
            traces.withValue { $0.append(trace) }
        }

        let response = try await runtime.generateText(
            systemPrompt: "Reply with the final fallback result.",
            userPrompt: "Return a short status line."
        )

        let capturedTraces = traces.snapshot()
        #expect(response == "Gemini fallback success")
        #expect(capturedTraces.count == 2)
        #expect(capturedTraces[0].service == .openAI)
        #expect(capturedTraces[0].outcome == .failure)
        #expect(capturedTraces[0].fallbackIndex == 0)
        #expect(capturedTraces[0].retryCount == 0)
        #expect(capturedTraces[0].errorCategory == .requestFailed)
        #expect(capturedTraces[1].service == .gemini)
        #expect(capturedTraces[1].outcome == .success)
        #expect(capturedTraces[1].fallbackIndex == 1)
        #expect(capturedTraces[1].retryCount == 0)
    }

    @Test
    func runtimeCanFallbackFromPrimaryToRepairRouteForInvalidJSON() async throws {
        let completionsAttempts = LockedBox(0)
        let session = makeMockedSession { request in
            guard request.url?.path == "/v1/chat/completions" else {
                Issue.record("Unexpected request path: \(request.url?.path ?? "nil")")
                return (500, Data("{}".utf8))
            }

            let attempt = completionsAttempts.withValue {
                $0 += 1
                return $0
            }

            if attempt == 1 {
                let payload = """
                {"choices":[{"message":{"content":"This is not valid JSON."}}]}
                """
                return (200, Data(payload.utf8))
            }

            if attempt == 2 {
                let payload = """
                {"choices":[{"message":{"content":"{\\"title\\":\\"Repair\\",\\"bullets\\":[\\"Fallback\\",\\"Worked\\"]}"}}]}
                """
                return (200, Data(payload.utf8))
            }

            Issue.record("Unexpected request attempt: \(attempt)")
            return (500, Data("{}".utf8))
        }

        let configuration = HostedAIConfiguration(
            service: .openAI,
            primaryModel: "gpt-5-mini",
            apiKeysByService: [HostedAIService.openAI.rawValue: "openai-key"],
            enableWorkflowRouting: true,
            repairModel: "gpt-5-nano"
        )

        let runtime = HostedAIRuntime(
            configuration: configuration,
            fallbackTargets: [
                HostedAIRequestTarget(configuration: configuration, route: .repair)
            ],
            fallbackPolicy: HostedAIFallbackPolicy(conditions: [.invalidResponse]),
            retryPolicy: HostedAIRetryPolicy(
                maxAttempts: 1,
                initialBackoff: 0,
                backoffMultiplier: 1,
                maxBackoff: 0
            ),
            session: session
        )

        struct Response: Decodable {
            let title: String
            let bullets: [String]
        }

        let response = try await runtime.generateJSON(
            systemPrompt: "Return JSON only.",
            userPrompt: "Create a short outline.",
            as: Response.self
        )

        #expect(response.title == "Repair")
        #expect(response.bullets == ["Fallback", "Worked"])
        #expect(completionsAttempts.snapshot() == 2)
    }
}
