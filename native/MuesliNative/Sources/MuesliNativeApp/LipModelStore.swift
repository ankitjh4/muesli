import Foundation

/// Shared with the app's other downloaded models. No developer checkout or
/// Python environment is consulted. A future downloader can populate this path.
enum LipModelStore {
    enum Readiness: Equatable { case ready, needsVisualModel, needsLanguageModel, unsupportedSystem }

    static func readiness(visualInstalled: Bool, languageInstalled: Bool, supportsLocalLanguage: Bool) -> Readiness {
        guard supportsLocalLanguage else { return .unsupportedSystem }
        guard visualInstalled else { return .needsVisualModel }
        guard languageInstalled else { return .needsLanguageModel }
        return .ready
    }

    static var readiness: Readiness {
        let supportsLocalLanguage: Bool
        if #available(macOS 15.0, *) { supportsLocalLanguage = true }
        else { supportsLocalLanguage = false }
        return readiness(visualInstalled: isInstalled,
                         languageInstalled: PostProcessorOption.defaultQuilOption.isDownloaded,
                         supportsLocalLanguage: supportsLocalLanguage)
    }

    static var modelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/muesli/models/lip-vallr-coreml", isDirectory: true)
            .appendingPathComponent("model.mlmodelc", isDirectory: true)
    }

    static var isInstalled: Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &directory) && directory.boolValue
    }
}
