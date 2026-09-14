import AppIntents
import MuesliNativeApp

@available(macOS 13.0, *)
struct UseOfflineModelsIntent: AppIntent {
    static var title: LocalizedStringResource = "Use Offline Models"
    static var description = IntentDescription("Uses downloaded speech, cleanup, Quill, and meeting-summary models. Requires local models and no active recording. Preview: computer-use planning is unavailable; this is not a system-wide network blocker.")
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let controller = try await MuesliShortcutsRuntime.waitForController()
        return .result(value: try controller.setOfflineInferenceForShortcuts(true))
    }
}

@available(macOS 13.0, *)
struct AllowOnlineModelsIntent: AppIntent {
    static var title: LocalizedStringResource = "Allow Online Models"
    static var description = IntentDescription("Restores your previous model selections and allows hosted or mixed local/online inference.")
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let controller = try await MuesliShortcutsRuntime.waitForController()
        return .result(value: try controller.setOfflineInferenceForShortcuts(false))
    }
}
