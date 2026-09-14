import Foundation
import MuesliCore

struct OpenRouterDictationConfiguration: Sendable {
    let apiKey: String
    let model: String
}

struct OpenRouterTranscriptionResult: Equatable, Sendable {
    let text: String
    let generationID: String?
}

enum OpenRouterTranscriptionError: LocalizedError, @unchecked Sendable {
    case offlineMode
    case missingAPIKey
    case missingModel
    case emptyTranscript
    case server(statusCode: Int, message: String?)
    case network(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .offlineMode:
            return "OpenRouter transcription is unavailable in offline mode. Switch to online / mixed models to send audio to your selected provider."
        case .missingAPIKey:
            return "OpenRouter is not connected. Connect it in Settings → Dictation."
        case .missingModel:
            return "Choose an OpenRouter transcription model in Settings → Dictation."
        case .emptyTranscript:
            return "OpenRouter returned an empty transcript."
        case .server(let statusCode, let message):
            if let message, !message.isEmpty {
                return "OpenRouter transcription failed (HTTP \(statusCode)): \(message)"
            }
            return "OpenRouter transcription failed (HTTP \(statusCode))."
        case .network(let underlying):
            return "Could not reach OpenRouter: \(underlying.localizedDescription)"
        }
    }
}

struct OpenRouterTranscriptionClient: Sendable {
    typealias LoadData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let endpoint = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!
    static let requestTimeout: TimeInterval = 65

    private let loadData: LoadData
    private let networkPolicy: ModelNetworkPolicy

    init(networkPolicy: ModelNetworkPolicy = .shared, loadData: @escaping LoadData = { try await URLSession.shared.data(for: $0) }) {
        self.networkPolicy = networkPolicy
        self.loadData = loadData
    }

    func transcribe(
        wavURL: URL,
        configuration: OpenRouterDictationConfiguration
    ) async throws -> OpenRouterTranscriptionResult {
        try Task.checkCancellation()
        guard networkPolicy.isAllowed else { throw OpenRouterTranscriptionError.offlineMode }
        let audioData: Data
        do {
            audioData = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: wavURL)
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OpenRouterTranscriptionError.network(underlying: error)
        }

        try Task.checkCancellation()
        let request = try Self.request(audioData: audioData, configuration: configuration)
        do {
            let (data, response) = try await networkPolicy.withNetworkAccess { try await loadData(request) }
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterTranscriptionError.network(
                    underlying: URLError(.badServerResponse)
                )
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw OpenRouterTranscriptionError.server(
                    statusCode: httpResponse.statusCode,
                    message: Self.serverMessage(from: data)
                )
            }

            let payload = try JSONDecoder().decode(ResponsePayload.self, from: data)
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw OpenRouterTranscriptionError.emptyTranscript }
            return OpenRouterTranscriptionResult(
                text: text,
                generationID: httpResponse.value(forHTTPHeaderField: "X-Generation-Id")
            )
        } catch is ModelNetworkPolicy.OfflineError {
            throw OpenRouterTranscriptionError.offlineMode
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenRouterTranscriptionError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw OpenRouterTranscriptionError.network(underlying: error)
        }
    }

    func validateAccess(configuration: OpenRouterDictationConfiguration) throws {
        try Task.checkCancellation()
        guard networkPolicy.isAllowed else { throw OpenRouterTranscriptionError.offlineMode }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterTranscriptionError.missingAPIKey
        }
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterTranscriptionError.missingModel
        }
    }

    static func request(
        audioData: Data,
        configuration: OpenRouterDictationConfiguration
    ) throws -> URLRequest {
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw OpenRouterTranscriptionError.missingAPIKey }
        let model = normalizedModel(configuration.model)
        guard !model.isEmpty else { throw OpenRouterTranscriptionError.missingModel }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppIdentity.displayName, forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONEncoder().encode(RequestPayload(
            model: model,
            inputAudio: InputAudio(data: audioData.base64EncodedString(), format: "wav")
        ))
        return request
    }

    static func normalizedModel(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }
        let raw = payload.error?.message ?? payload.message
        guard let raw else { return nil }
        let collapsed = raw
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(240))
    }

    private struct RequestPayload: Encodable {
        let model: String
        let inputAudio: InputAudio

        enum CodingKeys: String, CodingKey {
            case model
            case inputAudio = "input_audio"
        }
    }

    private struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    private struct ResponsePayload: Decodable {
        let text: String
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorPayload?
        let message: String?
    }

    private struct ErrorPayload: Decodable {
        let message: String?
    }
}

enum OpenRouterModelCatalogScope: String, Sendable {
    case text
    case transcription
}

enum OpenRouterModelCatalogError: LocalizedError {
    case invalidResponse, offlineMode

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Could not load OpenRouter models."
        case .offlineMode: return "You’re offline. Switch to online mode to refresh OpenRouter models."
        }
    }
}

struct OpenRouterModelCatalogClient: Sendable {
    typealias LoadData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let loadData: LoadData
    private let networkPolicy: ModelNetworkPolicy

    init(networkPolicy: ModelNetworkPolicy = .shared,
         loadData: @escaping LoadData = { try await URLSession.shared.data(for: $0) }) {
        self.networkPolicy = networkPolicy
        self.loadData = loadData
    }

    func load(_ scope: OpenRouterModelCatalogScope) async throws -> [SummaryModelPreset] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkPolicy.withNetworkAccess { try await loadData(Self.request(scope)) }
            try Task.checkCancellation()
            try networkPolicy.requireAllowed()
        } catch is ModelNetworkPolicy.OfflineError {
            throw OpenRouterModelCatalogError.offlineMode
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OpenRouterModelCatalogError.invalidResponse
        }
        let catalog = try JSONDecoder().decode(OpenRouterModelCatalog.self, from: data)
        switch scope {
        case .text:
            return OpenRouterModelCatalogFilter.textGenerationPresets(from: catalog.data)
        case .transcription:
            return OpenRouterModelCatalogFilter.transcriptionPresets(from: catalog.data)
        }
    }

    static func request(_ scope: OpenRouterModelCatalogScope) -> URLRequest {
        var components = URLComponents(string: "https://openrouter.ai/api/v1/models")!
        components.queryItems = [URLQueryItem(name: "output_modalities", value: scope.rawValue)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue(AppIdentity.displayName, forHTTPHeaderField: "X-OpenRouter-Title")
        return request
    }
}
