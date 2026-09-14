import Foundation
import MuesliCore
import Security

public enum AppIdentity {
    private static let defaultName = "Muesli+"

    /// macOS linkd rejects App Intent connections from ad-hoc builds without a
    /// Team ID. Metadata discovery alone does not establish runtime support.
    static let hasSigningTeam: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String else { return false }
        return !team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }()

    static var bundleName: String {
        stringValue(for: "CFBundleName") ?? defaultName
    }

    static var displayName: String {
        stringValue(for: "CFBundleDisplayName") ?? bundleName
    }

    static var marketingVersion: String {
        stringValue(for: "CFBundleShortVersionString") ?? "0.0.0"
    }

    static var supportDirectoryName: String {
        stringValue(for: "MuesliSupportDirectoryName") ?? displayName
    }

    /// Public so App Intents (a separate module from the rest of the app)
    /// can resolve the *running* app identity's data directory — e.g.
    /// MuesliDev vs Muesli+ — instead of hardcoding the production default.
    public static var supportDirectoryURL: URL {
        MuesliPaths.defaultSupportDirectoryURL(appName: supportDirectoryName)
    }

    private static func stringValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
