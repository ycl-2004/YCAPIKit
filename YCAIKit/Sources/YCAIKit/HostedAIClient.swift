import Foundation

public struct HostedAIGenerationOptions: Equatable, Sendable {
    public var temperature: Double?
    public var maxTokens: Int?

    public init(temperature: Double? = nil, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    public static let `default` = HostedAIGenerationOptions()
}

public enum HostedAIClientError: LocalizedError, Sendable {
    case missingAPIKey(service: HostedAIService, baseURL: String)
    case modelUnavailable(service: HostedAIService, baseURL: String, modelName: String, availableModels: [String], serverMessage: String?)
    case requestFailed(service: HostedAIService, modelName: String?, statusCode: Int?, message: String)
    case invalidResponse(service: HostedAIService?, modelName: String?, message: String)

    var isTransient: Bool {
        switch self {
        case let .requestFailed(_, _, statusCode, message):
            if let statusCode, [408, 409, 429, 500, 502, 503, 504].contains(statusCode) {
                return true
            }
            let lowercased = message.lowercased()
            return lowercased.contains("timed out")
                || lowercased.contains("timeout")
                || lowercased.contains("gateway")
                || lowercased.contains("temporarily unavailable")
        case .missingAPIKey, .modelUnavailable, .invalidResponse:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(service, baseURL):
            return "\(service.displayName) at \(baseURL) needs an API key before it can run requests."
        case let .modelUnavailable(service, baseURL, modelName, availableModels, serverMessage):
            let available = availableModels.isEmpty ? "No models were reported." : "Available models: \(formatModelList(availableModels))."
            let suffix = serverMessage.map { " Server response: \($0)" } ?? ""
            return "\(service.displayName) at \(baseURL) does not list \"\(modelName)\". \(available)\(suffix)"
        case let .requestFailed(service, modelName, statusCode, message):
            let target = modelName ?? "request"
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            return "\(service.displayName) failed while running \(target)\(status). \(message)"
        case let .invalidResponse(service, modelName, message):
            let serviceName = service?.displayName ?? "Hosted AI"
            let target = modelName.map { " for \($0)" } ?? ""
            return "\(serviceName) returned an invalid response\(target). \(message)"
        }
    }
}

public struct HostedAIClient: Sendable {
    typealias RetryObserver = @Sendable (Int, Error, TimeInterval) -> Void

    public let service: HostedAIService
    public let modelName: String
    public let baseURL: URL

    private let healthStatusHandler: @Sendable () async -> HostedAIHealthStatus
    private let textHandler: @Sendable (String, String, HostedAIGenerationOptions, Bool, RetryObserver?) async throws -> String

    init(
        service: HostedAIService,
        modelName: String,
        baseURL: URL,
        healthStatusHandler: @escaping @Sendable () async -> HostedAIHealthStatus,
        textHandler: @escaping @Sendable (String, String, HostedAIGenerationOptions, Bool, RetryObserver?) async throws -> String
    ) {
        self.service = service
        self.modelName = modelName
        self.baseURL = baseURL
        self.healthStatusHandler = healthStatusHandler
        self.textHandler = textHandler
    }

    public func healthStatus() async -> HostedAIHealthStatus {
        await healthStatusHandler()
    }

    public func generateText(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions = .default
    ) async throws -> String {
        try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            options: options,
            retryObserver: nil
        )
    }

    public func generateJSON<T: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions = .default,
        as type: T.Type
    ) async throws -> T {
        let raw = try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            options: options,
            jsonMode: true,
            retryObserver: nil
        )
        return try HostedAIJSONParser.decodeCandidate(
            raw,
            as: T.self,
            service: service,
            modelName: modelName
        )
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions,
        jsonMode: Bool = false,
        retryObserver: RetryObserver?
    ) async throws -> String {
        try await textHandler(systemPrompt, userPrompt, options, jsonMode, retryObserver)
    }

    func generateJSON<T: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions,
        retryObserver: RetryObserver?,
        as type: T.Type
    ) async throws -> T {
        let raw = try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            options: options,
            jsonMode: true,
            retryObserver: retryObserver
        )
        return try HostedAIJSONParser.decodeCandidate(
            raw,
            as: T.self,
            service: service,
            modelName: modelName
        )
    }
}

public enum HostedAIClientFactory {
    public static func makeClient(
        configuration: HostedAIConfiguration,
        route: HostedAIRoute = .primary,
        session: URLSession? = nil,
        retryPolicy: HostedAIRetryPolicy = .default
    ) -> HostedAIClient {
        let session = session ?? HostedAIHTTP.session
        let modelName = configuration.resolvedModel(for: route)
        let baseURL = URL(string: configuration.baseURL) ?? URL(string: configuration.service.defaultBaseURL)!
        let apiKey = configuration.resolvedAPIKey()

        switch configuration.service {
        case .nvidia, .openAI, .zhipu, .mistral:
            let transport = OpenAICompatibleTransport(
                service: configuration.service,
                baseURL: baseURL,
                apiKey: apiKey,
                modelName: modelName,
                session: session,
                retryPolicy: retryPolicy
            )
            return HostedAIClient(
                service: configuration.service,
                modelName: modelName,
                baseURL: baseURL,
                healthStatusHandler: { await transport.healthStatus() },
                textHandler: { systemPrompt, userPrompt, options, jsonMode, retryObserver in
                    try await transport.generate(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        options: options,
                        jsonMode: jsonMode,
                        retryObserver: retryObserver
                    )
                }
            )
        case .anthropic:
            let transport = AnthropicTransport(
                baseURL: baseURL,
                apiKey: apiKey,
                modelName: modelName,
                session: session,
                retryPolicy: retryPolicy
            )
            return HostedAIClient(
                service: configuration.service,
                modelName: modelName,
                baseURL: baseURL,
                healthStatusHandler: { await transport.healthStatus() },
                textHandler: { systemPrompt, userPrompt, options, jsonMode, retryObserver in
                    try await transport.generate(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        options: options,
                        jsonMode: jsonMode,
                        retryObserver: retryObserver
                    )
                }
            )
        case .gemini:
            let transport = GeminiTransport(
                baseURL: baseURL,
                apiKey: apiKey,
                modelName: modelName,
                session: session,
                retryPolicy: retryPolicy
            )
            return HostedAIClient(
                service: configuration.service,
                modelName: modelName,
                baseURL: baseURL,
                healthStatusHandler: { await transport.healthStatus() },
                textHandler: { systemPrompt, userPrompt, options, jsonMode, retryObserver in
                    try await transport.generate(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        options: options,
                        jsonMode: jsonMode,
                        retryObserver: retryObserver
                    )
                }
            )
        }
    }

    public static func healthStatus(
        for configuration: HostedAIConfiguration,
        route: HostedAIRoute = .primary,
        session: URLSession? = nil,
        retryPolicy: HostedAIRetryPolicy = .default
    ) async -> HostedAIHealthStatus {
        await makeClient(
            configuration: configuration,
            route: route,
            session: session,
            retryPolicy: retryPolicy
        ).healthStatus()
    }
}

private struct OpenAICompatibleTransport: Sendable {
    let service: HostedAIService
    let baseURL: URL
    let apiKey: String
    let modelName: String
    let session: URLSession
    let retryPolicy: HostedAIRetryPolicy

    func healthStatus() async -> HostedAIHealthStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return HostedAIHealthStatus(
                isHealthy: false,
                summary: "API key required.",
                detail: "Enter an API key for \(service.displayName) before checking the model."
            )
        }

        do {
            let models = try await availableModels()
            guard models.contains(modelName) else {
                return HostedAIHealthStatus(
                    isHealthy: false,
                    summary: "Model unavailable.",
                    detail: "\(service.displayName) does not list \"\(modelName)\". Available models: \(formatModelList(models))."
                )
            }

            return HostedAIHealthStatus(
                isHealthy: true,
                summary: "\(service.displayName) ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return HostedAIHealthStatus(
                isHealthy: false,
                summary: "\(service.displayName) unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions,
        jsonMode: Bool,
        retryObserver: HostedAIClient.RetryObserver?
    ) async throws -> String {
        try await withTransientRetry(policy: retryPolicy, onRetry: retryObserver) {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw HostedAIClientError.missingAPIKey(service: service, baseURL: baseURL.absoluteString)
            }

            var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            request.httpBody = try JSONEncoder().encode(
                OpenAICompatibleRequest(
                    model: modelName,
                    messages: [
                        .init(role: "system", content: jsonMode ? "\(systemPrompt)\nReturn JSON only." : systemPrompt),
                        .init(role: "user", content: userPrompt),
                    ],
                    temperature: options.temperature,
                    responseFormat: jsonMode ? .init(type: "json_object") : nil
                )
            )

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw try await requestError(from: data, statusCode: httpResponse.statusCode)
            }

            let completion = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
            guard let content = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw HostedAIClientError.invalidResponse(
                    service: service,
                    modelName: modelName,
                    message: "The provider returned an empty text payload."
                )
            }
            return content
        }
    }

    private func availableModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HostedAIClientError.requestFailed(
                service: service,
                modelName: modelName,
                statusCode: nil,
                message: "No HTTP response was returned."
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw try await requestError(from: data, statusCode: httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data)
        return payload.data.map(\.id)
    }

    private func requestError(from data: Data, statusCode: Int?) async throws -> HostedAIClientError {
        let message = extractedMessage(from: data)
        if message.localizedCaseInsensitiveContains("model"),
           (message.localizedCaseInsensitiveContains("not found") || message.localizedCaseInsensitiveContains("does not exist")) {
            let models = (try? await availableModels()) ?? []
            return .modelUnavailable(
                service: service,
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                availableModels: models,
                serverMessage: message
            )
        }

        return .requestFailed(
            service: service,
            modelName: modelName,
            statusCode: statusCode,
            message: message
        )
    }
}

private struct AnthropicTransport: Sendable {
    let baseURL: URL
    let apiKey: String
    let modelName: String
    let session: URLSession
    let retryPolicy: HostedAIRetryPolicy

    func healthStatus() async -> HostedAIHealthStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return HostedAIHealthStatus(
                isHealthy: false,
                summary: "API key required.",
                detail: "Enter an API key for Anthropic before checking the model."
            )
        }

        do {
            let models = try await availableModels()
            guard models.contains(modelName) else {
                return HostedAIHealthStatus(
                    isHealthy: false,
                    summary: "Model unavailable.",
                    detail: "Anthropic does not list \"\(modelName)\". Available models: \(formatModelList(models))."
                )
            }

            return HostedAIHealthStatus(
                isHealthy: true,
                summary: "Anthropic ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return HostedAIHealthStatus(
                isHealthy: false,
                summary: "Anthropic unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions,
        jsonMode: Bool,
        retryObserver: HostedAIClient.RetryObserver?
    ) async throws -> String {
        try await withTransientRetry(policy: retryPolicy, onRetry: retryObserver) {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw HostedAIClientError.missingAPIKey(service: .anthropic, baseURL: baseURL.absoluteString)
            }

            var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
            request.httpMethod = "POST"
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            request.httpBody = try JSONEncoder().encode(
                AnthropicMessagesRequest(
                    model: modelName,
                    system: jsonMode ? "\(systemPrompt)\nReturn JSON only." : systemPrompt,
                    messages: [.init(role: "user", content: userPrompt)],
                    maxTokens: options.maxTokens ?? 8_192,
                    temperature: options.temperature
                )
            )

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw HostedAIClientError.requestFailed(
                    service: .anthropic,
                    modelName: modelName,
                    statusCode: httpResponse.statusCode,
                    message: extractedMessage(from: data)
                )
            }

            let completion = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
            let text = completion.content
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw HostedAIClientError.invalidResponse(
                    service: .anthropic,
                    modelName: modelName,
                    message: "Anthropic returned an empty text response."
                )
            }
            return text
        }
    }

    private func availableModels() async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw HostedAIClientError.missingAPIKey(service: .anthropic, baseURL: baseURL.absoluteString)
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HostedAIClientError.requestFailed(
                service: .anthropic,
                modelName: modelName,
                statusCode: nil,
                message: "No HTTP response was returned."
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HostedAIClientError.requestFailed(
                service: .anthropic,
                modelName: modelName,
                statusCode: httpResponse.statusCode,
                message: extractedMessage(from: data)
            )
        }

        let payload = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        return payload.data.map(\.id)
    }
}

private struct GeminiTransport: Sendable {
    let baseURL: URL
    let apiKey: String
    let modelName: String
    let session: URLSession
    let retryPolicy: HostedAIRetryPolicy

    func healthStatus() async -> HostedAIHealthStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return HostedAIHealthStatus(
                isHealthy: false,
                summary: "API key required.",
                detail: "Enter an API key for Google Gemini before checking the model."
            )
        }

        do {
            let models = try await availableModels()
            guard models.contains(modelName) else {
                return HostedAIHealthStatus(
                    isHealthy: false,
                    summary: "Model unavailable.",
                    detail: "Gemini does not list \"\(modelName)\". Available models: \(formatModelList(models))."
                )
            }

            return HostedAIHealthStatus(
                isHealthy: true,
                summary: "Gemini ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return HostedAIHealthStatus(
                isHealthy: false,
                summary: "Gemini unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions,
        jsonMode: Bool,
        retryObserver: HostedAIClient.RetryObserver?
    ) async throws -> String {
        try await withTransientRetry(policy: retryPolicy, onRetry: retryObserver) {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw HostedAIClientError.missingAPIKey(service: .gemini, baseURL: baseURL.absoluteString)
            }

            var request = URLRequest(url: baseURL.appending(path: "v1beta/models/\(modelName):generateContent"))
            request.httpMethod = "POST"
            request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            request.httpBody = try JSONEncoder().encode(
                GeminiGenerateContentRequest(
                    systemInstruction: .init(role: nil, parts: [.init(text: jsonMode ? "\(systemPrompt)\nReturn JSON only." : systemPrompt)]),
                    contents: [.init(role: "user", parts: [.init(text: userPrompt)])],
                    generationConfig: .init(
                        responseMimeType: jsonMode ? "application/json" : "text/plain",
                        temperature: options.temperature ?? 0.2
                    )
                )
            )

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw HostedAIClientError.requestFailed(
                    service: .gemini,
                    modelName: modelName,
                    statusCode: httpResponse.statusCode,
                    message: extractedMessage(from: data)
                )
            }

            let completion = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
            let text = completion.candidates
                .flatMap { $0.content.parts }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw HostedAIClientError.invalidResponse(
                    service: .gemini,
                    modelName: modelName,
                    message: "Gemini returned an empty text response."
                )
            }

            return text
        }
    }

    private func availableModels() async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw HostedAIClientError.missingAPIKey(service: .gemini, baseURL: baseURL.absoluteString)
        }

        var request = URLRequest(url: baseURL.appending(path: "v1beta/models"))
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HostedAIClientError.requestFailed(
                service: .gemini,
                modelName: modelName,
                statusCode: nil,
                message: "No HTTP response was returned."
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HostedAIClientError.requestFailed(
                service: .gemini,
                modelName: modelName,
                statusCode: httpResponse.statusCode,
                message: extractedMessage(from: data)
            )
        }

        let payload = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        return payload.models.map { model in
            let name = model.name
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
    }
}

private struct OpenAICompatibleRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double?
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }
}

private struct OpenAICompatibleResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let system: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct GeminiGenerateContentRequest: Encodable {
    struct Content: Encodable {
        let role: String?
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let responseMimeType: String
        let temperature: Double

        enum CodingKeys: String, CodingKey {
            case temperature
            case responseMimeType = "responseMimeType"
        }
    }

    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents, generationConfig
        case systemInstruction = "system_instruction"
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]
        }

        let content: Content
    }

    let candidates: [Candidate]
}

private struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct StandardAPIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}

private func extractedMessage(from data: Data) -> String {
    if let envelope = try? JSONDecoder().decode(StandardAPIErrorEnvelope.self, from: data) {
        return envelope.error.message
    }

    let fallback = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return fallback?.isEmpty == false ? fallback! : "The provider returned an empty error payload."
}

private func formatModelList(_ models: [String]) -> String {
    guard !models.isEmpty else { return "none reported" }
    let preview = Array(models.prefix(6))
    let suffix = models.count > preview.count ? ", ..." : ""
    return preview.joined(separator: ", ") + suffix
}
