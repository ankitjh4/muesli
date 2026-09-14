import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Onboarding local cleanup")
struct OnboardingCleanupSetupTests {
    @Test func onboardingOptOutSurvivesRestart() throws {
        let progress = OnboardingProgress(currentStep: 8, userName: "", selectedBackendKey: "bodhan",
            selectedModelKey: "test", hotkeyKeyCode: 61, hotkeyLabel: "Right Option", cleanupEnabled: false)
        let restored = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(progress))
        #expect(!restored.cleanupEnabled)
    }

    @Test func enablesAvailableLocalModelWithoutCloud() {
        var config = AppConfig()
        OnboardingCleanupSetup.choose(true, config: &config, modelAvailable: true, supported: true)
        #expect(config.enablePostProcessor)
        #expect(!config.pendingLocalCleanupSetup)
        #expect(config.postProcessorBackend == TranscriptCleanupBackendOption.local.backend)
        #expect(config.activePostProcessorId == PostProcessorOption.defaultQuilOption.id)
    }

    @Test func waitsForDownloadAndThenActivatesOnce() throws {
        var config = AppConfig()
        OnboardingCleanupSetup.choose(true, config: &config, modelAvailable: false, supported: true)
        #expect(!config.enablePostProcessor)
        #expect(config.pendingLocalCleanupSetup)
        config = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(OnboardingCleanupSetup.activatePending(config: &config, modelAvailable: true, supported: true))
        #expect(config.enablePostProcessor)
        #expect(!OnboardingCleanupSetup.activatePending(config: &config, modelAvailable: true, supported: true))
    }

    @Test func optOutAndOldProfilesStayOff() throws {
        var old = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(!OnboardingCleanupSetup.activatePending(config: &old, modelAvailable: true, supported: true))
        #expect(!old.enablePostProcessor)
        OnboardingCleanupSetup.choose(false, config: &old, modelAvailable: true, supported: true)
        #expect(!old.enablePostProcessor)
        #expect(!old.pendingLocalCleanupSetup)
    }

    @Test func unsupportedSystemDoesNotActivate() {
        var config = AppConfig()
        OnboardingCleanupSetup.choose(true, config: &config, modelAvailable: true, supported: false)
        #expect(!config.enablePostProcessor)
        #expect(config.pendingLocalCleanupSetup)
    }
}
