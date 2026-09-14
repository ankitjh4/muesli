import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Offline inference routing")
struct InferenceRoutingTests {
    @Test func offlinePausesBackgroundSyncWithoutErasingPreference() throws {
        var config = AppConfig()
        config.iCloudSyncEnabled = true
        #expect(BackgroundNetworkPolicy.allowsICloudSync(config))
        try InferenceRouting.transition(&config, offline: true, speechReady: true, languageReady: true)
        #expect(config.iCloudSyncEnabled)
        #expect(!BackgroundNetworkPolicy.allowsICloudSync(config))
        #expect(throws: (any Error).self) { try BackgroundNetworkPolicy.requireOnline(config) }
        try InferenceRouting.transition(&config, offline: false, speechReady: false, languageReady: false)
        #expect(BackgroundNetworkPolicy.allowsICloudSync(config))
        try BackgroundNetworkPolicy.requireOnline(config)
        config.iCloudSyncEnabled = false
        #expect(!BackgroundNetworkPolicy.allowsICloudSync(config))
    }

    @Test func missingDownloadsDoNotMutatePreferences() {
        var config = AppConfig()
        config.dictationProvider = DictationProvider.openRouter.rawValue
        #expect(throws: InferenceRouting.SwitchError.self) {
            try InferenceRouting.transition(&config, offline: true, speechReady: false, languageReady: true)
        }
        #expect(!config.offlineInference)
        #expect(config.savedOnlineInference == nil)
        #expect(config.resolvedDictationProvider == .openRouter)
        #expect(throws: InferenceRouting.SwitchError.self) {
            try InferenceRouting.transition(&config, offline: true, speechReady: true, languageReady: false)
        }
        #expect(!config.offlineInference)
    }

    @Test func repeatedOfflineSelectionDoesNotOverwriteOnlinePreferences() throws {
        var config = AppConfig()
        config.dictationProvider = DictationProvider.openRouter.rawValue
        config.quilBackend = "openrouter"
        config.quilModel = "example/model"
        try InferenceRouting.transition(&config, offline: true, speechReady: true, languageReady: true)
        let saved = config.savedOnlineInference
        try InferenceRouting.transition(&config, offline: true, speechReady: true, languageReady: true)
        #expect(config.savedOnlineInference == saved)
        try InferenceRouting.transition(&config, offline: false, speechReady: false, languageReady: false)
        #expect(config.quilBackend == "openrouter")
        #expect(config.quilModel == "example/model")
        #expect(config.resolvedDictationProvider == .openRouter)
    }

    @Test func normalizesCloudSelectionsAndRestoresOnlinePreferences() {
        var config = AppConfig()
        config.dictationProvider = DictationProvider.openRouter.rawValue
        config.postProcessorBackend = "openrouter"
        config.quilBackend = "openrouter"
        config.quilModel = "example/text-model"
        let saved = OnlineInferencePreferences(config: config)
        config.offlineInference = true
        InferenceRouting.enforceLocalModels(in: &config)
        #expect(config.resolvedDictationProvider == .local)
        #expect(config.postProcessorBackend == "local")
        #expect(config.quilBackend == "local")
        #expect(config.quilModel == PostProcessorOption.defaultQuilOption.id)
        config.offlineInference = false
        saved.restore(into: &config)
        #expect(config.resolvedDictationProvider == .openRouter)
        #expect(config.quilModel == "example/text-model")
    }

    @Test func persistedOfflineConfigCannotRestoreHostedRouting() throws {
        let data = Data(#"{"offline_inference":true,"dictation_provider":"openRouter","post_processor_backend":"openrouter","quil_backend":"openrouter"}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.resolvedDictationProvider == .local)
        #expect(config.postProcessorBackend == "local")
        #expect(config.quilBackend == "local")
    }

    @Test func hostedCleanupRejectsOfflineBeforeCredentialsOrTransport() async {
        var config = AppConfig()
        config.offlineInference = true
        do {
            _ = try await TranscriptCleanupClient.generate(
                systemPrompt: "Clean", userPrompt: "Example", backend: .hosted(.openRouter),
                model: "example/model", config: config
            )
            Issue.record("Hosted generation must not proceed offline")
        } catch {
            #expect(error.localizedDescription.contains("offline inference"))
        }
    }

    @Test func offlinePolicyRejectsHostedGeneration() {
        var config = AppConfig()
        config.offlineInference = true
        #expect(throws: TranscriptCleanupError.self) {
            try InferenceRouting.requireHostedInferenceAllowed(config: config)
        }
    }
}
