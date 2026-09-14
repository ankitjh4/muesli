import Foundation

enum BackgroundNetworkPolicy {
    static func allowsICloudSync(_ config: AppConfig) -> Bool {
        config.iCloudSyncEnabled && !config.offlineInference
    }

    static func requireOnline(_ config: AppConfig) throws {
        guard !config.offlineInference else {
            throw NSError(domain: "MuesliOfflineMode", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "This network service is paused in offline mode. Switch to online / mixed mode to use it."
            ])
        }
    }
}

struct OnlineInferencePreferences: Codable, Equatable {
    var dictationProvider: String
    var cleanupBackend: String
    var cleanupModel: String
    var quilBackend: String
    var quilModel: String

    init(config: AppConfig) {
        dictationProvider = config.dictationProvider
        cleanupBackend = config.postProcessorBackend
        cleanupModel = config.activePostProcessorId
        quilBackend = config.quilBackend
        quilModel = config.quilModel
    }

    func restore(into config: inout AppConfig) {
        config.dictationProvider = dictationProvider
        config.postProcessorBackend = cleanupBackend
        config.activePostProcessorId = cleanupModel
        config.quilBackend = quilBackend
        config.quilModel = quilModel
    }
}

enum InferenceRouting {
    enum SwitchError: LocalizedError {
        case busy, backgroundWork, missingSpeechModel, missingLanguageModel, missingSpeechSupportFiles
        var errorDescription: String? {
            switch self {
            case .busy: return "Finish the current recording or transformation before switching inference modes."
            case .backgroundWork: return "Wait for meeting processing, imports, and the current app update to finish before switching inference modes."
            case .missingSpeechModel: return "Select and download a local speech model in Models before switching offline."
            case .missingSpeechSupportFiles: return "Whisper needs its small text-decoding files before it can work offline. Open Shortcuts and choose Prepare Whisper for offline use while online."
            case .missingLanguageModel: return "Download Qwen Basic Cleanup in Models before switching offline. It supplies the local correction and Quill language model."
            }
        }
    }

    static func transition(_ config: inout AppConfig, offline: Bool, speechReady: Bool, languageReady: Bool) throws {
        guard config.offlineInference != offline else { return }
        if offline {
            guard speechReady else { throw SwitchError.missingSpeechModel }
            guard languageReady else { throw SwitchError.missingLanguageModel }
            config.savedOnlineInference = OnlineInferencePreferences(config: config)
            config.offlineInference = true
            config.postProcessorBackend = TranscriptCleanupBackendOption.local.backend
            config.activePostProcessorId = PostProcessorOption.qwen35_0_8b.id
            config.quilBackend = TranscriptCleanupBackendOption.local.backend
            config.quilModel = PostProcessorOption.defaultQuilOption.id
            enforceLocalModels(in: &config)
        } else {
            config.offlineInference = false
            let saved = config.savedOnlineInference
            saved?.restore(into: &config)
            config.savedOnlineInference = nil
        }
    }

    static func enforceLocalModels(in config: inout AppConfig) {
        guard config.offlineInference else { return }
        config.dictationProvider = DictationProvider.local.rawValue
        if !TranscriptCleanupBackendOption.resolved(config.postProcessorBackend).isOnDevice {
            config.postProcessorBackend = TranscriptCleanupBackendOption.local.backend
            config.activePostProcessorId = PostProcessorOption.qwen35_0_8b.id
        }
        if !TranscriptCleanupBackendOption.resolved(config.quilBackend).isOnDevice {
            config.quilBackend = TranscriptCleanupBackendOption.local.backend
            config.quilModel = PostProcessorOption.defaultQuilOption.id
        }
    }

    static func requireHostedInferenceAllowed(config: AppConfig) throws {
        guard !config.offlineInference else {
            throw TranscriptCleanupError.missingConfiguration("This feature requires a hosted model and is unavailable in offline inference mode. No request was sent.")
        }
    }
}
