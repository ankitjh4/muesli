import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Quill app-specific writing styles")
struct QuilAppStyleTests {
    let styles = [QuilAppStyle(bundleID: "com.apple.mail", appName: "Mail", prompt: "Be professional.")]

    @Test func exactAppMatching() {
        #expect(QuilAppStyle.prompt(for: "com.apple.mail", in: styles) == "Be professional.")
        #expect(QuilAppStyle.prompt(for: "com.apple.mail.other", in: styles) == nil)
        #expect(QuilAppStyle.prompt(for: nil, in: styles) == nil)
    }

    @Test func settingsRoundTrip() throws {
        var config = AppConfig()
        config.quilAppStyles = styles
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(restored.quilAppStyles == styles)
        let oldConfig = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(oldConfig.quilAppStyles.isEmpty)
    }

    @Test func separatesSavedPreferencesFromUntrustedContext() {
        let prompt = QuilTransformationPrompt.userPrompt(
            selectedText: "Hello", instruction: "Make this informal",
            appContext: "An email document", appStyle: "Be professional."
        )
        #expect(prompt.contains("\"user_saved_app_style\":\"Be professional.\""))
        #expect(prompt.contains("\"spoken_instruction\":\"Make this informal\""))
        #expect(QuilTransformationPrompt.system.contains("only where the spoken instruction does not specify otherwise"))
        let withoutStyle = QuilTransformationPrompt.userPrompt(selectedText: "Hello", instruction: "Shorten")
        #expect(!withoutStyle.contains("user_saved_app_style"))
    }

    @Test func boundsStoredPromptAtRuntime() {
        let long = QuilAppStyle(bundleID: "test", appName: "Test", prompt: String(repeating: "x", count: 3_000))
        #expect(QuilAppStyle.prompt(for: "test", in: [long])?.count == 2_000)
    }
}
