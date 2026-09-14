import Foundation

enum OnboardingCleanupSetup {
    /// Only onboarding opts in. Existing profiles default to no pending change.
    static func choose(_ enabled: Bool, config: inout AppConfig, modelAvailable: Bool, supported: Bool) {
        config.pendingLocalCleanupSetup = enabled
        config.enablePostProcessor = false
        config.postProcessorBackend = TranscriptCleanupBackendOption.local.backend
        config.activePostProcessorId = PostProcessorOption.defaultQuilOption.id
        _ = activatePending(config: &config, modelAvailable: modelAvailable, supported: supported)
    }

    @discardableResult
    static func activatePending(config: inout AppConfig, modelAvailable: Bool, supported: Bool) -> Bool {
        guard config.pendingLocalCleanupSetup, modelAvailable, supported else { return false }
        config.pendingLocalCleanupSetup = false
        config.enablePostProcessor = true
        config.postProcessorBackend = TranscriptCleanupBackendOption.local.backend
        config.activePostProcessorId = PostProcessorOption.defaultQuilOption.id
        return true
    }
}
