import Foundation
import MuesliCore

enum HostedProfessionVocabulary {
    typealias Generate = (String, String, String, AppConfig) async throws -> String

    static func suggest(
        _ description: String,
        excluding existing: [String],
        model: String,
        config: AppConfig,
        generate: Generate = { system, input, model, config in
            try await ModelNetworkPolicy.shared.withNetworkAccess {
                try await TranscriptCleanupClient.generate(
                systemPrompt: system, userPrompt: input,
                backend: .hosted(.openRouter), model: model, config: config,
                maxOutputTokens: 512, logCategory: "profession-vocabulary"
                )
            }
        }
    ) async throws -> [String] {
        try InferenceRouting.requireHostedInferenceAllowed(config: config)
        let input = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= 2_000, !model.isEmpty else {
            throw TranscriptCleanupError.missingConfiguration("Describe your work and select an OpenRouter text model first.")
        }
        try Task.checkCancellation()
        let output = try await generate(ProfessionVocabulary.systemPrompt, input, model, config)
        try Task.checkCancellation()
        return try ProfessionVocabulary.parse(output, excluding: existing)
    }
}
