import Testing
@testable import YCAIKit

struct HostedAIConfigurationTests {
    @Test
    func selectedServiceUsesThatServicesStoredAPIKey() {
        var configuration = HostedAIConfiguration(
            service: .openAI,
            apiKeysByService: [
                HostedAIService.openAI.rawValue: "openai-key",
                HostedAIService.gemini.rawValue: "gemini-key",
            ]
        )

        #expect(configuration.selectedServiceAPIKey == "openai-key")
        #expect(configuration.resolvedAPIKey() == "openai-key")

        configuration.service = .gemini

        #expect(configuration.selectedServiceAPIKey == "gemini-key")
        #expect(configuration.resolvedAPIKey() == "gemini-key")
    }

    @Test
    func environmentFallbackWorksWhenNoStoredKeyExists() {
        let configuration = HostedAIConfiguration(service: .anthropic)

        let key = configuration.resolvedAPIKey(
            environment: ["ANTHROPIC_API_KEY": "env-anthropic-key"]
        )

        #expect(key == "env-anthropic-key")
    }

    @Test
    func applyServiceDefaultsResetsBaseURLAndRouteModels() {
        var configuration = HostedAIConfiguration(service: .openAI)

        configuration.applyServiceDefaults(.gemini)

        #expect(configuration.service == .gemini)
        #expect(configuration.baseURL == HostedAIService.gemini.defaultBaseURL)
        #expect(configuration.primaryModel == HostedAIService.gemini.recommendedMainModel)
        #expect(configuration.chunkModel == HostedAIService.gemini.recommendedChunkModel)
        #expect(configuration.polishModel == HostedAIService.gemini.recommendedPolishModel)
        #expect(configuration.repairModel == HostedAIService.gemini.recommendedRepairModel)
    }

    @Test
    func nonPrimaryRoutesFallBackToPrimaryWhenRoutingDisabled() {
        let configuration = HostedAIConfiguration(
            service: .openAI,
            enableWorkflowRouting: false
        )

        #expect(configuration.resolvedModel(for: .primary) == configuration.primaryModel)
        #expect(configuration.resolvedModel(for: .chunk) == configuration.primaryModel)
        #expect(configuration.resolvedModel(for: .polish) == configuration.primaryModel)
        #expect(configuration.resolvedModel(for: .repair) == configuration.primaryModel)
    }

    @Test
    func inferServiceFromBaseURLMatchesKnownProviders() {
        #expect(HostedAIConfiguration.inferService(from: "https://api.openai.com/v1") == .openAI)
        #expect(HostedAIConfiguration.inferService(from: "https://api.anthropic.com") == .anthropic)
        #expect(HostedAIConfiguration.inferService(from: "https://generativelanguage.googleapis.com") == .gemini)
    }
}
