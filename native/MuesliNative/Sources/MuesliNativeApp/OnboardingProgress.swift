import Foundation

struct OnboardingPermissionSnapshot: Equatable, Sendable {
    var microphone: Bool
    var accessibility: Bool
    var inputMonitoring: Bool
    var systemAudio: Bool
    var screenRecording: Bool
}

enum OnboardingPermissionGate {
    static func hasRequiredDictationPermissions(_ permissions: OnboardingPermissionSnapshot) -> Bool {
        permissions.microphone && permissions.accessibility && permissions.inputMonitoring
    }

    static func hasRequiredVoiceNotesPermissions(_ permissions: OnboardingPermissionSnapshot) -> Bool {
        permissions.microphone && permissions.inputMonitoring
    }

    static func hasRequiredMeetingPermissions(
        _ permissions: OnboardingPermissionSnapshot,
        useCoreAudioTap: Bool = true
    ) -> Bool {
        permissions.microphone
            && (useCoreAudioTap ? permissions.systemAudio : permissions.screenRecording)
    }

    /// Runtime startup remains gated only by permissions needed for the app's
    /// always-on interaction surfaces. Meeting system audio is requested during
    /// onboarding, but a later revocation is repaired when meeting capture starts
    /// instead of trapping an existing user back in onboarding.
    static func hasRequiredStartupPermissions(
        _ permissions: OnboardingPermissionSnapshot,
        for useCase: OnboardingUseCase
    ) -> Bool {
        if useCase.includesDictation {
            return hasRequiredDictationPermissions(permissions)
        }
        if useCase.includesVoiceNotes {
            return hasRequiredVoiceNotesPermissions(permissions)
        }
        return permissions.microphone
    }

    static func hasRequiredPermissions(
        _ permissions: OnboardingPermissionSnapshot,
        for useCase: OnboardingUseCase,
        useCoreAudioTap: Bool = true
    ) -> Bool {
        guard permissions.microphone else { return false }
        if useCase.includesDictation,
           (!permissions.accessibility || !permissions.inputMonitoring) {
            return false
        }
        if useCase.includesVoiceNotes, !permissions.inputMonitoring {
            return false
        }
        if useCase.includesMeetings,
           !hasRequiredMeetingPermissions(permissions, useCoreAudioTap: useCoreAudioTap) {
            return false
        }
        return true
    }

    static func resumeStep(
        requestedStep: Int,
        permissions: OnboardingPermissionSnapshot,
        useCase: OnboardingUseCase,
        permissionsStep: Int,
        dictationTestStep: Int,
        useCoreAudioTap: Bool = true
    ) -> Int {
        let gatedStep = useCase.includesPushToTalk ? dictationTestStep : permissionsStep + 1
        if OnboardingFlow.isStep(requestedStep, atOrAfter: gatedStep)
            && !hasRequiredPermissions(permissions, for: useCase, useCoreAudioTap: useCoreAudioTap) {
            return permissionsStep
        }
        return requestedStep
    }
}

struct OnboardingProgress: Codable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int = currentSchemaVersion
    var currentStep: Int
    var userName: String
    var selectedBackendKey: String
    var selectedModelKey: String
    var selectedMeetingBackendKey: String
    var selectedMeetingModelKey: String
    var selectedCohereLanguageCode: String
    var hotkeyKeyCode: UInt16
    var hotkeyLabel: String
    var systemAudioRequested: Bool = false
    var onboardingUseCaseRawValue: String = OnboardingUseCase.dictation.rawValue
    var summaryBackendKey: String = MeetingSummaryBackendOption.chatGPT.backend
    var quillEnabled: Bool = false
    var cleanupEnabled: Bool = true
    var quillBackendKey: String = TranscriptCleanupBackendOption.local.backend
    var modelDownloadProgress: Double?
    var modelDownloadStatus: String?

    init(
        schemaVersion: Int = currentSchemaVersion,
        currentStep: Int,
        userName: String,
        selectedBackendKey: String,
        selectedModelKey: String,
        selectedMeetingBackendKey: String? = nil,
        selectedMeetingModelKey: String? = nil,
        selectedCohereLanguageCode: String = CohereTranscribeLanguage.defaultLanguage.rawValue,
        hotkeyKeyCode: UInt16,
        hotkeyLabel: String,
        systemAudioRequested: Bool = false,
        onboardingUseCaseRawValue: String = OnboardingUseCase.dictation.rawValue,
        summaryBackendKey: String = MeetingSummaryBackendOption.chatGPT.backend,
        quillEnabled: Bool = false,
        cleanupEnabled: Bool = true,
        quillBackendKey: String = TranscriptCleanupBackendOption.local.backend,
        modelDownloadProgress: Double? = nil,
        modelDownloadStatus: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.currentStep = currentStep
        self.userName = userName
        self.selectedBackendKey = selectedBackendKey
        self.selectedModelKey = selectedModelKey
        self.selectedMeetingBackendKey = selectedMeetingBackendKey ?? selectedBackendKey
        self.selectedMeetingModelKey = selectedMeetingModelKey ?? selectedModelKey
        self.selectedCohereLanguageCode = CohereTranscribeLanguage.resolvedCode(selectedCohereLanguageCode)
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyLabel = hotkeyLabel
        self.systemAudioRequested = systemAudioRequested
        self.onboardingUseCaseRawValue = OnboardingUseCase.resolved(onboardingUseCaseRawValue).rawValue
        self.summaryBackendKey = MeetingSummaryBackendOption.resolved(summaryBackendKey).backend
        self.quillEnabled = quillEnabled
        self.cleanupEnabled = cleanupEnabled
        self.quillBackendKey = TranscriptCleanupBackendOption.resolved(quillBackendKey).backend
        self.modelDownloadProgress = modelDownloadProgress
        self.modelDownloadStatus = modelDownloadStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        currentStep = try c.decode(Int.self, forKey: .currentStep)
        userName = try c.decode(String.self, forKey: .userName)
        selectedBackendKey = try c.decode(String.self, forKey: .selectedBackendKey)
        selectedModelKey = try c.decode(String.self, forKey: .selectedModelKey)
        selectedMeetingBackendKey = try c.decodeIfPresent(String.self, forKey: .selectedMeetingBackendKey)
            ?? selectedBackendKey
        selectedMeetingModelKey = try c.decodeIfPresent(String.self, forKey: .selectedMeetingModelKey)
            ?? selectedModelKey
        selectedCohereLanguageCode = CohereTranscribeLanguage.resolvedCode(
            try c.decodeIfPresent(String.self, forKey: .selectedCohereLanguageCode)
        )
        hotkeyKeyCode = try c.decode(UInt16.self, forKey: .hotkeyKeyCode)
        hotkeyLabel = try c.decode(String.self, forKey: .hotkeyLabel)
        systemAudioRequested = try c.decodeIfPresent(Bool.self, forKey: .systemAudioRequested) ?? false
        onboardingUseCaseRawValue = OnboardingUseCase.resolved(
            try c.decodeIfPresent(String.self, forKey: .onboardingUseCaseRawValue)
        ).rawValue
        summaryBackendKey = MeetingSummaryBackendOption.resolved(
            try c.decodeIfPresent(String.self, forKey: .summaryBackendKey)
        ).backend
        quillEnabled = try c.decodeIfPresent(Bool.self, forKey: .quillEnabled) ?? false
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? true
        quillBackendKey = TranscriptCleanupBackendOption.resolved(
            try c.decodeIfPresent(String.self, forKey: .quillBackendKey)
        ).backend
        modelDownloadProgress = try c.decodeIfPresent(Double.self, forKey: .modelDownloadProgress)
        modelDownloadStatus = try c.decodeIfPresent(String.self, forKey: .modelDownloadStatus)
    }

    private static var fileURL: URL {
        AppIdentity.supportDirectoryURL.appendingPathComponent("onboarding-progress.json")
    }

    static func save(_ progress: OnboardingProgress) {
        do {
            let dir = AppIdentity.supportDirectoryURL
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(progress)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            fputs("[muesli-native] failed to save onboarding progress: \(error)\n", stderr)
        }
    }

    static func load() -> OnboardingProgress? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard var progress = try? JSONDecoder().decode(OnboardingProgress.self, from: data) else {
            // Stale or incompatible schema — discard and start fresh
            clear()
            return nil
        }
        guard progress.schemaVersion <= currentSchemaVersion else {
            clear()
            return nil
        }
        if progress.schemaVersion < currentSchemaVersion {
            progress.schemaVersion = currentSchemaVersion
            save(progress)
        }
        return progress
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
