import Foundation
import Testing
@testable import YCAPIKit

struct HostedAIClientTests {
    @Test
    func openAICompatibleHealthStatusAndJSONGenerationUseConfiguredSession() async throws {
        let session = makeMockedSession { request in
            if request.url?.path == "/v1/models" {
                let payload = """
                {"data":[{"id":"gpt-5-mini"}]}
                """
                return (200, Data(payload.utf8))
            }

            if request.url?.path == "/v1/chat/completions" {
                let payload = """
                {"choices":[{"message":{"content":"{\\"title\\":\\"Reusable\\",\\"bullets\\":[\\"A\\",\\"B\\"]}"}}]}
                """
                return (200, Data(payload.utf8))
            }

            Issue.record("Unexpected request path: \(request.url?.path ?? "nil")")
            return (500, Data("{}".utf8))
        }

        let configuration = HostedAIConfiguration(
            service: .openAI,
            apiKeysByService: [HostedAIService.openAI.rawValue: "test-key"]
        )

        let client = HostedAIClientFactory.makeClient(
            configuration: configuration,
            session: session
        )

        let status = await client.healthStatus()
        #expect(status.isHealthy)

        struct Response: Decodable {
            let title: String
            let bullets: [String]
        }

        let response = try await client.generateJSON(
            systemPrompt: "Return JSON only.",
            userPrompt: "Create a short outline.",
            as: Response.self
        )

        #expect(response.title == "Reusable")
        #expect(response.bullets == ["A", "B"])
    }

    @Test
    func openAICompatibleClientRetriesTransientFailureThenSucceeds() async throws {
        let completionsAttempts = LockedBox(0)
        let session = makeMockedSession { request in
            if request.url?.path == "/v1/chat/completions" {
                let attempt = completionsAttempts.withValue {
                    $0 += 1
                    return $0
                }

                if attempt == 1 {
                    let payload = """
                    {"error":{"message":"Try again later."}}
                    """
                    return (429, Data(payload.utf8))
                }

                let payload = """
                {"choices":[{"message":{"content":"Recovered after retry"}}]}
                """
                return (200, Data(payload.utf8))
            }

            Issue.record("Unexpected request path: \(request.url?.path ?? "nil")")
            return (500, Data("{}".utf8))
        }

        let configuration = HostedAIConfiguration(
            service: .openAI,
            apiKeysByService: [HostedAIService.openAI.rawValue: "test-key"]
        )

        let client = HostedAIClientFactory.makeClient(
            configuration: configuration,
            session: session,
            retryPolicy: HostedAIRetryPolicy(
                maxAttempts: 2,
                initialBackoff: 0,
                backoffMultiplier: 1,
                maxBackoff: 0
            )
        )

        let response = try await client.generateText(
            systemPrompt: "Reply with a short confirmation.",
            userPrompt: "Confirm recovery."
        )

        #expect(response == "Recovered after retry")
        #expect(completionsAttempts.snapshot() == 2)
    }
}
