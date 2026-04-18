import Foundation

enum HostedAIHTTP {
    static let requestTimeout: TimeInterval = 600
    static let resourceTimeout: TimeInterval = 1_800

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }()
}

public struct HostedAIRetryPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var initialBackoff: TimeInterval
    public var backoffMultiplier: Double
    public var maxBackoff: TimeInterval

    public init(
        maxAttempts: Int = 2,
        initialBackoff: TimeInterval = 0.75,
        backoffMultiplier: Double = 1,
        maxBackoff: TimeInterval = 0.75
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialBackoff = max(0, initialBackoff)
        self.backoffMultiplier = max(1, backoffMultiplier)
        self.maxBackoff = max(0, maxBackoff)
    }

    public static let `default` = HostedAIRetryPolicy()

    public static let recommended = HostedAIRetryPolicy(
        maxAttempts: 3,
        initialBackoff: 0.5,
        backoffMultiplier: 2,
        maxBackoff: 2
    )

    fileprivate func delayBeforeAttempt(_ nextAttempt: Int) -> TimeInterval {
        guard nextAttempt > 1, initialBackoff > 0 else { return 0 }

        let exponent = max(0, nextAttempt - 2)
        let proposedDelay = initialBackoff * pow(backoffMultiplier, Double(exponent))
        if maxBackoff > 0 {
            return min(proposedDelay, maxBackoff)
        }
        return proposedDelay
    }
}

enum HostedAIJSONParser {
    static func decodeCandidate<T: Decodable>(
        _ raw: String,
        as type: T.Type,
        service: HostedAIService? = nil,
        modelName: String? = nil
    ) throws -> T {
        let candidates = candidateJSONStrings(from: raw)

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(T.self, from: data) {
                return decoded
            }
        }

        throw HostedAIClientError.invalidResponse(
            service: service,
            modelName: modelName,
            message: "The model returned text, but none of the extracted JSON candidates matched the requested schema."
        )
    }

    static func candidateJSONStrings(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fenceStripped = stripCodeFences(from: trimmed)

        var candidates = [fenceStripped, trimmed]
        if let extracted = extractFirstJSONObject(from: fenceStripped) {
            candidates.append(extracted)
        }
        if let extracted = extractFirstJSONObject(from: trimmed) {
            candidates.append(extracted)
        }

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func stripCodeFences(from raw: String) -> String {
        guard raw.hasPrefix("```") else { return raw }

        var lines = raw.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFirstJSONObject(from text: String) -> String? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }

        for start in characters.indices where characters[start] == "{" {
            var depth = 0
            var insideString = false
            var escaped = false

            for end in start..<characters.count {
                let character = characters[end]

                if escaped {
                    escaped = false
                    continue
                }

                if character == "\\" && insideString {
                    escaped = true
                    continue
                }

                if character == "\"" {
                    insideString.toggle()
                    continue
                }

                if insideString {
                    continue
                }

                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1

                    guard depth >= 0 else { break }
                    guard depth == 0 else { continue }

                    let candidate = String(characters[start...end])
                    guard let data = candidate.data(using: .utf8) else { continue }
                    if (try? JSONSerialization.jsonObject(with: data)) != nil {
                        return candidate
                    }
                }
            }
        }

        return nil
    }
}

extension Error {
    var isTransientHostedAIFailure: Bool {
        if let clientError = self as? HostedAIClientError {
            return clientError.isTransient
        }

        if let urlError = self as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        let lowercased = localizedDescription.lowercased()
        return lowercased.contains("timed out")
            || lowercased.contains("gateway timeout")
            || lowercased.contains("temporarily unavailable")
    }
}

func withTransientRetry<T>(
    policy: HostedAIRetryPolicy = .default,
    onRetry: (@Sendable (Int, Error, TimeInterval) -> Void)? = nil,
    operation: () async throws -> T
) async throws -> T {
    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch {
            guard attempt < policy.maxAttempts, error.isTransientHostedAIFailure else {
                throw error
            }
            try Task.checkCancellation()

            let delay = policy.delayBeforeAttempt(attempt + 1)
            onRetry?(attempt + 1, error, delay)
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
}
