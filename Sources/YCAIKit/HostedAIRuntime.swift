import Foundation

final class HostedAIRetryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

public struct HostedAIRequestTarget: Equatable, Sendable {
    public var configuration: HostedAIConfiguration
    public var route: HostedAIRoute

    public init(configuration: HostedAIConfiguration, route: HostedAIRoute = .primary) {
        self.configuration = configuration
        self.route = route
    }

    public var service: HostedAIService {
        configuration.service
    }

    public var modelName: String {
        configuration.resolvedModel(for: route)
    }
}

public enum HostedAIFallbackCondition: String, Codable, CaseIterable, Hashable, Sendable {
    case transientFailure
    case modelUnavailable
    case invalidResponse
    case requestFailure
}

public struct HostedAIFallbackPolicy: Equatable, Sendable {
    public var conditions: Set<HostedAIFallbackCondition>

    public init(conditions: Set<HostedAIFallbackCondition>) {
        self.conditions = conditions
    }

    public static let conservative = HostedAIFallbackPolicy(
        conditions: [.transientFailure, .modelUnavailable]
    )

    public static let aggressive = HostedAIFallbackPolicy(
        conditions: Set(HostedAIFallbackCondition.allCases)
    )

    fileprivate func shouldFallback(after error: Error) -> Bool {
        conditions.contains { $0.matches(error) }
    }
}

public struct HostedAIRequestTrace: Equatable, Sendable {
    public enum Outcome: String, Codable, Equatable, Sendable {
        case success
        case failure
    }

    public enum ErrorCategory: String, Codable, Equatable, Sendable {
        case missingAPIKey
        case modelUnavailable
        case invalidResponse
        case requestFailed
        case transientNetwork
        case unknown
    }

    public var service: HostedAIService
    public var modelName: String
    public var route: HostedAIRoute
    public var baseURL: String
    public var fallbackIndex: Int
    public var retryCount: Int
    public var duration: TimeInterval
    public var outcome: Outcome
    public var errorCategory: ErrorCategory?
    public var errorDescription: String?

    public init(
        service: HostedAIService,
        modelName: String,
        route: HostedAIRoute,
        baseURL: String,
        fallbackIndex: Int,
        retryCount: Int,
        duration: TimeInterval,
        outcome: Outcome,
        errorCategory: ErrorCategory? = nil,
        errorDescription: String? = nil
    ) {
        self.service = service
        self.modelName = modelName
        self.route = route
        self.baseURL = baseURL
        self.fallbackIndex = fallbackIndex
        self.retryCount = retryCount
        self.duration = duration
        self.outcome = outcome
        self.errorCategory = errorCategory
        self.errorDescription = errorDescription
    }
}

public struct HostedAIRuntime: Sendable {
    public typealias TraceHandler = @Sendable (HostedAIRequestTrace) -> Void

    private let targets: [HostedAIRequestTarget]
    private let fallbackPolicy: HostedAIFallbackPolicy
    private let retryPolicy: HostedAIRetryPolicy
    private let session: URLSession
    private let traceHandler: TraceHandler?

    public init(
        primary: HostedAIRequestTarget,
        fallbackTargets: [HostedAIRequestTarget] = [],
        fallbackPolicy: HostedAIFallbackPolicy = .conservative,
        retryPolicy: HostedAIRetryPolicy = .default,
        session: URLSession? = nil,
        traceHandler: TraceHandler? = nil
    ) {
        self.targets = [primary] + fallbackTargets
        self.fallbackPolicy = fallbackPolicy
        self.retryPolicy = retryPolicy
        self.session = session ?? HostedAIHTTP.session
        self.traceHandler = traceHandler
    }

    public init(
        configuration: HostedAIConfiguration,
        route: HostedAIRoute = .primary,
        fallbackTargets: [HostedAIRequestTarget] = [],
        fallbackPolicy: HostedAIFallbackPolicy = .conservative,
        retryPolicy: HostedAIRetryPolicy = .default,
        session: URLSession? = nil,
        traceHandler: TraceHandler? = nil
    ) {
        self.init(
            primary: HostedAIRequestTarget(configuration: configuration, route: route),
            fallbackTargets: fallbackTargets,
            fallbackPolicy: fallbackPolicy,
            retryPolicy: retryPolicy,
            session: session,
            traceHandler: traceHandler
        )
    }

    public func generateText(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions = .default
    ) async throws -> String {
        try await execute { client, retryObserver in
            try await client.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                options: options,
                retryObserver: retryObserver
            )
        }
    }

    public func generateJSON<T: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        options: HostedAIGenerationOptions = .default,
        as type: T.Type
    ) async throws -> T {
        try await execute { client, retryObserver in
            try await client.generateJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                options: options,
                retryObserver: retryObserver,
                as: type
            )
        }
    }

    private func execute<T>(
        operation: (HostedAIClient, HostedAIClient.RetryObserver?) async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for (fallbackIndex, target) in targets.enumerated() {
            let client = HostedAIClientFactory.makeClient(
                configuration: target.configuration,
                route: target.route,
                session: session,
                retryPolicy: retryPolicy
            )
            let startedAt = Date()
            let retryCounter = HostedAIRetryCounter()
            let retryObserver: HostedAIClient.RetryObserver = { _, _, _ in
                retryCounter.increment()
            }

            do {
                let result = try await operation(client, retryObserver)
                traceHandler?(
                    HostedAIRequestTrace(
                        service: client.service,
                        modelName: client.modelName,
                        route: target.route,
                        baseURL: client.baseURL.absoluteString,
                        fallbackIndex: fallbackIndex,
                        retryCount: retryCounter.snapshot(),
                        duration: Date().timeIntervalSince(startedAt),
                        outcome: .success
                    )
                )
                return result
            } catch {
                lastError = error
                traceHandler?(
                    HostedAIRequestTrace(
                        service: client.service,
                        modelName: client.modelName,
                        route: target.route,
                        baseURL: client.baseURL.absoluteString,
                        fallbackIndex: fallbackIndex,
                        retryCount: retryCounter.snapshot(),
                        duration: Date().timeIntervalSince(startedAt),
                        outcome: .failure,
                        errorCategory: .from(error),
                        errorDescription: error.localizedDescription
                    )
                )

                let hasMoreTargets = fallbackIndex < targets.count - 1
                guard hasMoreTargets, fallbackPolicy.shouldFallback(after: error) else {
                    throw error
                }
            }
        }

        throw lastError ?? HostedAIClientError.invalidResponse(
            service: nil,
            modelName: nil,
            message: "HostedAIRuntime exhausted every target without producing a result."
        )
    }
}

private extension HostedAIRequestTrace.ErrorCategory {
    static func from(_ error: Error) -> Self {
        if let clientError = error as? HostedAIClientError {
            switch clientError {
            case .missingAPIKey:
                return .missingAPIKey
            case .modelUnavailable:
                return .modelUnavailable
            case .invalidResponse:
                return .invalidResponse
            case .requestFailed:
                return .requestFailed
            }
        }

        if error.isTransientHostedAIFailure {
            return .transientNetwork
        }

        return .unknown
    }
}

private extension HostedAIFallbackCondition {
    func matches(_ error: Error) -> Bool {
        switch self {
        case .transientFailure:
            return error.isTransientHostedAIFailure
        case .modelUnavailable:
            guard case .modelUnavailable = error as? HostedAIClientError else { return false }
            return true
        case .invalidResponse:
            guard case .invalidResponse = error as? HostedAIClientError else { return false }
            return true
        case .requestFailure:
            guard case .requestFailed = error as? HostedAIClientError else { return false }
            return true
        }
    }
}
