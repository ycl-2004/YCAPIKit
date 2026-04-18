import Foundation

public enum HostedAIService: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case nvidia
    case openAI
    case zhipu
    case mistral
    case anthropic
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nvidia: return "NVIDIA"
        case .openAI: return "OpenAI"
        case .zhipu: return "Zhipu / BigModel"
        case .mistral: return "Mistral"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .nvidia:
            return "https://integrate.api.nvidia.com/v1"
        case .openAI:
            return "https://api.openai.com/v1"
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .anthropic:
            return "https://api.anthropic.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        }
    }

    public var defaultEnvironmentVariableNames: [String] {
        switch self {
        case .nvidia:
            return ["YCAIKIT_NVIDIA_API_KEY", "YC_NVIDIA_API_KEY", "NVIDIA_API_KEY"]
        case .openAI:
            return ["YCAIKIT_OPENAI_API_KEY", "YC_OPENAI_API_KEY", "OPENAI_API_KEY"]
        case .zhipu:
            return ["YCAIKIT_ZHIPU_API_KEY", "YC_ZHIPU_API_KEY", "ZHIPU_API_KEY", "BIGMODEL_API_KEY"]
        case .mistral:
            return ["YCAIKIT_MISTRAL_API_KEY", "YC_MISTRAL_API_KEY", "MISTRAL_API_KEY"]
        case .anthropic:
            return ["YCAIKIT_ANTHROPIC_API_KEY", "YC_ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY"]
        case .gemini:
            return ["YCAIKIT_GEMINI_API_KEY", "YC_GEMINI_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY"]
        }
    }

    public var recommendedMainModel: String {
        switch self {
        case .nvidia: return "deepseek-ai/deepseek-v3.2"
        case .openAI: return "gpt-5-mini"
        case .zhipu: return "glm-5"
        case .mistral: return "mistral-medium-2508"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    public var recommendedChunkModel: String {
        switch self {
        case .nvidia: return "mistralai/mistral-small-3.1-24b-instruct-2503"
        case .openAI: return "gpt-5-nano"
        case .zhipu: return "glm-4.5-air"
        case .mistral: return "mistral-small-2506"
        case .anthropic: return "claude-3-5-haiku-20241022"
        case .gemini: return "gemini-2.5-flash-lite"
        }
    }

    public var recommendedPolishModel: String {
        switch self {
        case .nvidia: return "mistralai/mistral-medium-3-instruct"
        case .openAI: return "gpt-4.1"
        case .zhipu: return "glm-5"
        case .mistral: return "mistral-medium-2508"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-pro"
        }
    }

    public var recommendedRepairModel: String {
        switch self {
        case .nvidia: return "qwen/qwen3-coder-480b-a35b-instruct"
        case .openAI: return "gpt-5-mini"
        case .zhipu: return "glm-5"
        case .mistral: return "mistral-small-2506"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    public var usesOpenAICompatibleTransport: Bool {
        switch self {
        case .nvidia, .openAI, .zhipu, .mistral:
            return true
        case .anthropic, .gemini:
            return false
        }
    }

    public var presets: [HostedAIModelPreset] {
        switch self {
        case .nvidia:
            return [
                HostedAIModelPreset(service: self, title: "Balanced Notes", modelName: "deepseek-ai/deepseek-v3.2", baseURL: defaultBaseURL, summary: "Strong default for long-form writing, structured output, and editing passes."),
                HostedAIModelPreset(service: self, title: "Writing + Translation", modelName: "mistralai/mistral-medium-3-instruct", baseURL: defaultBaseURL, summary: "Best fit for rewrite-heavy and multilingual workflows."),
                HostedAIModelPreset(service: self, title: "Fast Structured Output", modelName: "mistralai/mistral-small-3.1-24b-instruct-2503", baseURL: defaultBaseURL, summary: "Fast JSON-oriented output for chunking and lighter transforms."),
                HostedAIModelPreset(service: self, title: "Code + Schema", modelName: "qwen/qwen3-coder-480b-a35b-instruct", baseURL: defaultBaseURL, summary: "Good for schema transforms, code generation, and structured automation."),
            ]
        case .openAI:
            return [
                HostedAIModelPreset(service: self, title: "Balanced Notes", modelName: "gpt-5-mini", baseURL: defaultBaseURL, summary: "Fast generalist for everyday text and structured JSON tasks."),
                HostedAIModelPreset(service: self, title: "Writing + Translation", modelName: "gpt-4.1", baseURL: defaultBaseURL, summary: "Better for polish, style control, and multilingual edits."),
                HostedAIModelPreset(service: self, title: "Fast Structured Output", modelName: "gpt-5-nano", baseURL: defaultBaseURL, summary: "Low-cost chunking and cleanup for high-volume workflows."),
                HostedAIModelPreset(service: self, title: "Code + Schema", modelName: "gpt-5.2", baseURL: defaultBaseURL, summary: "Useful for code tasks, schemas, and more agent-like prompts."),
            ]
        case .zhipu:
            return [
                HostedAIModelPreset(service: self, title: "Balanced Notes", modelName: "glm-5", baseURL: defaultBaseURL, summary: "Strong Chinese-first and mixed-language default."),
                HostedAIModelPreset(service: self, title: "High Accuracy", modelName: "glm-4.7", baseURL: defaultBaseURL, summary: "Best fit for more demanding reasoning and writing tasks."),
                HostedAIModelPreset(service: self, title: "Vision + OCR", modelName: "glm-4.6v", baseURL: defaultBaseURL, summary: "Useful for visual-context workflows you may add later."),
                HostedAIModelPreset(service: self, title: "Fast Structured Output", modelName: "glm-4.5-air", baseURL: defaultBaseURL, summary: "Faster low-cost drafting and chunking."),
                HostedAIModelPreset(service: self, title: "Code + Agent", modelName: "glm-4.5", baseURL: defaultBaseURL, summary: "Good fit for coding and tool-oriented prompts."),
            ]
        case .mistral:
            return [
                HostedAIModelPreset(service: self, title: "Balanced Notes", modelName: "mistral-medium-2508", baseURL: defaultBaseURL, summary: "Good polished default for multilingual documents."),
                HostedAIModelPreset(service: self, title: "Writing + Translation", modelName: "mistral-medium-2508", baseURL: defaultBaseURL, summary: "Strong rewrite and translation profile."),
                HostedAIModelPreset(service: self, title: "Fast Structured Output", modelName: "mistral-small-2506", baseURL: defaultBaseURL, summary: "Lower-latency drafting and chunk summarization."),
                HostedAIModelPreset(service: self, title: "Code + Automation", modelName: "devstral-small-2505", baseURL: defaultBaseURL, summary: "Good for code-oriented cleanup and automation prompts."),
            ]
        case .anthropic:
            return [
                HostedAIModelPreset(service: self, title: "Balanced Notes", modelName: "claude-sonnet-4-20250514", baseURL: defaultBaseURL, summary: "Strong general Claude default."),
                HostedAIModelPreset(service: self, title: "Writing + Translation", modelName: "claude-sonnet-4-20250514", baseURL: defaultBaseURL, summary: "Good for polish, tone, and multilingual rewrites."),
                HostedAIModelPreset(service: self, title: "Fast Structured Output", modelName: "claude-3-5-haiku-20241022", baseURL: defaultBaseURL, summary: "Faster and cheaper for chunking or cleanup."),
                HostedAIModelPreset(service: self, title: "Max Reasoning", modelName: "claude-opus-4-1-20250805", baseURL: defaultBaseURL, summary: "Higher-end reasoning when cost and speed matter less."),
            ]
        case .gemini:
            return [
                HostedAIModelPreset(service: self, title: "Balanced Notes", modelName: "gemini-2.5-flash", baseURL: defaultBaseURL, summary: "Strong price-performance for everyday generation."),
                HostedAIModelPreset(service: self, title: "Writing + Translation", modelName: "gemini-2.5-pro", baseURL: defaultBaseURL, summary: "Best Gemini fit for polish and translation."),
                HostedAIModelPreset(service: self, title: "Fast Structured Output", modelName: "gemini-2.5-flash-lite", baseURL: defaultBaseURL, summary: "Fastest low-cost chunking and cleanup."),
                HostedAIModelPreset(service: self, title: "High Accuracy", modelName: "gemini-2.5-pro", baseURL: defaultBaseURL, summary: "Best fit for harder reasoning or coding tasks."),
            ]
        }
    }
}

public struct HostedAIModelPreset: Equatable, Identifiable, Sendable {
    public let service: HostedAIService
    public let title: String
    public let modelName: String
    public let baseURL: String
    public let summary: String

    public init(service: HostedAIService, title: String, modelName: String, baseURL: String, summary: String) {
        self.service = service
        self.title = title
        self.modelName = modelName
        self.baseURL = baseURL
        self.summary = summary
    }

    public var id: String { "\(service.rawValue):\(modelName)" }
}

public enum HostedAIRoute: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case primary
    case chunk
    case polish
    case repair

    public var id: String { rawValue }
}

public struct HostedAIHealthStatus: Equatable, Sendable {
    public var isHealthy: Bool
    public var summary: String
    public var detail: String?

    public init(isHealthy: Bool, summary: String, detail: String? = nil) {
        self.isHealthy = isHealthy
        self.summary = summary
        self.detail = detail
    }
}

public struct HostedAIConfiguration: Codable, Equatable, Sendable {
    public var service: HostedAIService
    public var baseURL: String
    public var primaryModel: String
    public var apiKeysByService: [String: String]
    public var enableWorkflowRouting: Bool
    public var chunkModel: String
    public var polishModel: String
    public var repairModel: String

    public init(
        service: HostedAIService = .openAI,
        baseURL: String? = nil,
        primaryModel: String? = nil,
        apiKeysByService: [String: String] = [:],
        enableWorkflowRouting: Bool = true,
        chunkModel: String? = nil,
        polishModel: String? = nil,
        repairModel: String? = nil
    ) {
        self.service = service
        self.baseURL = baseURL ?? service.defaultBaseURL
        self.primaryModel = primaryModel ?? service.recommendedMainModel
        self.apiKeysByService = apiKeysByService
        self.enableWorkflowRouting = enableWorkflowRouting
        self.chunkModel = chunkModel ?? service.recommendedChunkModel
        self.polishModel = polishModel ?? service.recommendedPolishModel
        self.repairModel = repairModel ?? service.recommendedRepairModel
    }

    public static func recommended(service: HostedAIService = .openAI, enableWorkflowRouting: Bool = true) -> HostedAIConfiguration {
        HostedAIConfiguration(
            service: service,
            enableWorkflowRouting: enableWorkflowRouting
        )
    }

    public static func inferService(from baseURL: String) -> HostedAIService {
        let normalized = baseURL.lowercased()
        if normalized.contains("open.bigmodel.cn") { return .zhipu }
        if normalized.contains("api.openai.com") { return .openAI }
        if normalized.contains("api.mistral.ai") { return .mistral }
        if normalized.contains("api.anthropic.com") { return .anthropic }
        if normalized.contains("generativelanguage.googleapis.com") { return .gemini }
        return .nvidia
    }

    public var selectedServiceAPIKey: String {
        get { apiKeysByService[service.rawValue] ?? "" }
        set { setAPIKey(newValue, for: service) }
    }

    public func resolvedAPIKey(
        for service: HostedAIService? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let targetService = service ?? self.service
        let stored = apiKeysByService[targetService.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty {
            return stored
        }

        for key in targetService.defaultEnvironmentVariableNames {
            let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }

        return ""
    }

    public func resolvedModel(for route: HostedAIRoute) -> String {
        guard enableWorkflowRouting else { return primaryModel }

        switch route {
        case .primary:
            return primaryModel
        case .chunk:
            return chunkModel
        case .polish:
            return polishModel
        case .repair:
            return repairModel
        }
    }

    public mutating func setAPIKey(_ apiKey: String, for service: HostedAIService) {
        apiKeysByService[service.rawValue] = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func applyServiceDefaults(_ service: HostedAIService, resetRoutingModels: Bool = true) {
        self.service = service
        baseURL = service.defaultBaseURL
        primaryModel = service.recommendedMainModel
        if resetRoutingModels {
            chunkModel = service.recommendedChunkModel
            polishModel = service.recommendedPolishModel
            repairModel = service.recommendedRepairModel
        }
    }

    public mutating func applyPreset(_ preset: HostedAIModelPreset) {
        service = preset.service
        baseURL = preset.baseURL
        primaryModel = preset.modelName
        if enableWorkflowRouting {
            chunkModel = preset.service.recommendedChunkModel
            polishModel = preset.service.recommendedPolishModel
            repairModel = preset.service.recommendedRepairModel
        }
    }
}
