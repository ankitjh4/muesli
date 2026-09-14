import AVFoundation
import ApplicationServices
import SwiftUI
import MuesliCore

struct OnboardingView: View {
    let controller: MuesliController
    let appState: AppState

    @State private var currentStep: Int
    @State private var userName: String
    @State private var selectedUseCase: OnboardingUseCase
    @State private var selectedBackend: BackendOption
    @State private var selectedMeetingBackend: BackendOption
    @State private var selectedCohereLanguage: CohereTranscribeLanguage
    @State private var summaryBackend: MeetingSummaryBackendOption = .chatGPT
    @State private var apiKey = ""
    @State private var quillAPIKey = ""
    @State private var vocabularySuggestions: [String] = []
    @State private var selectedVocabulary = Set<String>()
    @State private var vocabularyTask: Task<Void, Never>?
    @State private var vocabularyGeneration = UUID()
    @State private var vocabularyMessage: String?
    @State private var vocabularyOnline = false
    @State private var vocabularyModel = ""
    @State private var vocabularyAPIKey = ""
    @State private var quillEnabled: Bool
    @State private var cleanupEnabled = true
    @State private var quillBackend: TranscriptCleanupBackendOption
    @State private var isSigningInChatGPT = false
    @State private var chatGPTSignInDone = false
    @State private var chatGPTSignInError: String?
    @State private var isSigningInOpenRouter = false
    @State private var openRouterSignInDone = false
    @State private var openRouterSignInError: String?
    @State private var isEnteringOpenRouterAPIKey = false

    // Permission states — polled from OS every second
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @State private var systemAudioGranted = false
    @State private var permissionPollTimer: Timer?
    @State private var grantingPermissionName: String?
    @State private var nativePermissionPromptName: String?
    @State private var recentlyGrantedPermissionName: String?
    @State private var permissionAdvanceTask: Task<Void, Never>?
    @State private var permissionAdvanceGeneration: UUID?
    @State private var hasCompletedPermissionsStep: Bool
    @State private var selectionBeforeEverything: OnboardingUseCase?

    // Hotkey recorder
    @State private var selectedHotkey: HotkeyConfig
    @State private var isRecordingHotkey = false
    @State private var hotkeyEventMonitor: Any?

    // Model selection
    @State private var showMoreModels = false
    @State private var customMenuBarEmoji: String

    // Dictation test
    @State private var isDictationTesting = false
    @State private var isDictationTestMonitorActive = false
    @State private var dictationTestResult: String?
    @State private var dictationTestError: String?
    @State private var isModelStillDownloading = false
    @State private var modelReadyBackend: BackendOption?
    @State private var modelDownloadBackend: BackendOption?
    @State private var modelDownloadTask: Task<Void, Never>?
    @State private var modelDownloadGeneration = UUID()
    @State private var modelDownloadProgress: Double?
    @State private var modelDownloadSnapshot: ModelDownloadProgress?
    @State private var isModelPreparingAfterDownload = false
    @State private var modelDownloadStatus: String?
    @State private var modelDownloadError: String?
    @State private var modelReadyIndicatorBackend: BackendOption?
    @State private var modelReadyIndicatorTask: Task<Void, Never>?

    // Meeting transcription setup uses its own model so users can optimize
    // long recordings independently from short dictation.
    @State private var meetingModelDownloadTask: Task<Void, Never>?
    @State private var meetingModelDownloadProgress: Double?
    @State private var meetingModelDownloadStatus: String?
    @State private var meetingModelDownloadError: String?
    @State private var meetingModelReadyBackend: BackendOption?

    // The first-run Quill setup supports the small private local model as well
    // as the two easiest hosted account options.
    @State private var isDownloadingQuillModel = false
    @State private var quillModelDownloadProgress: Double?
    @State private var quillModelDownloadStatus: String?
    @State private var quillModelDownloadError: String?
    @State private var quillModelDownloadTask: Task<Void, Never>?
    @State private var quillModelDownloadGeneration = UUID()

    @State private var hasFinishedOnboarding = false

    static let permissionsStep = OnboardingFlow.Step.permissions.rawValue
    static let dictationTestStep = OnboardingFlow.dictationTestStep
    private static let bundledMuesliLogo: NSImage = {
        if let url = Bundle.main.url(forResource: "muesli_app_icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }()

    private var orderedSteps: [Int] {
        OnboardingFlow.orderedSteps(for: selectedUseCase)
    }

    private var currentStepIndex: Int {
        OnboardingFlow.stepIndex(currentStep, for: selectedUseCase)
    }

    private var totalSteps: Int {
        orderedSteps.count
    }

    private var onboardingAlternativeModels: [BackendOption] {
        var options = BackendOption.onboarding.filter { $0 != BackendOption.onboardingDefault }
        if BackendOption.onboarding.contains(selectedBackend),
           selectedBackend != BackendOption.onboardingDefault,
           !options.contains(selectedBackend) {
            options.insert(selectedBackend, at: 0)
        }
        return options
    }

    private var onboardingMeetingModels: [BackendOption] {
        let candidates = [selectedMeetingBackend, selectedBackend] + BackendOption.onboarding
        return candidates.reduce(into: [BackendOption]()) { result, option in
            guard option.supportsMeetingTranscription, option.isCompatible(), !result.contains(option) else { return }
            result.append(option)
        }
    }

    init(
        controller: MuesliController,
        appState: AppState,
        initialStep: Int = 0,
        initialUserName: String = "",
        initialBackend: BackendOption = BackendOption.onboardingDefault,
        initialMeetingBackend: BackendOption = BackendOption.onboardingDefault,
        initialCohereLanguage: CohereTranscribeLanguage = CohereTranscribeLanguage.defaultLanguage,
        initialHotkey: HotkeyConfig = .default,
        initialSystemAudioRequested: Bool = false,
        initialUseCase: OnboardingUseCase = .dictation,
        initialSummaryBackend: MeetingSummaryBackendOption = .chatGPT,
        initialQuillEnabled: Bool = false,
        initialCleanupEnabled: Bool = true,
        initialQuillBackend: TranscriptCleanupBackendOption = .local,
        initialModelDownloadProgress: Double? = nil,
        initialModelDownloadStatus: String? = nil
    ) {
        self.controller = controller
        self.appState = appState
        // Pre-populate permission states so resumed onboarding reflects grants
        // that happened before the deliberate restart.
        let initialMicGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let initialAccessibilityGranted = AXIsProcessTrusted()
        let initialInputMonitoringGranted = CGPreflightListenEventAccess()
        let initialScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        let initialSystemAudioGranted = initialSystemAudioRequested
        let initialPermissions = OnboardingPermissionSnapshot(
            microphone: initialMicGranted,
            accessibility: initialAccessibilityGranted,
            inputMonitoring: initialInputMonitoringGranted,
            systemAudio: initialSystemAudioGranted,
            screenRecording: initialScreenRecordingGranted
        )
        let permissionGatedInitialStep = OnboardingPermissionGate.resumeStep(
            requestedStep: initialStep,
            permissions: initialPermissions,
            useCase: initialUseCase,
            permissionsStep: Self.permissionsStep,
            dictationTestStep: Self.dictationTestStep,
            useCoreAudioTap: appState.config.useCoreAudioTap
        )
        let sanitizedInitialBackend = BackendOption.resolvedOnboardingBackend(initialBackend)
        let sanitizedInitialMeetingBackend: BackendOption = {
            guard initialMeetingBackend.supportsMeetingTranscription,
                  initialMeetingBackend.isCompatible() else {
                return sanitizedInitialBackend.supportsMeetingTranscription
                    ? sanitizedInitialBackend : BackendOption.onboardingDefault
            }
            return initialMeetingBackend
        }()
        let supportedInitialQuillBackends: [TranscriptCleanupBackendOption] = [
            .local,
            .hosted(.chatGPT),
            .hosted(.openRouter),
        ]
        let sanitizedInitialQuillBackend = supportedInitialQuillBackends.contains(initialQuillBackend)
            ? initialQuillBackend : .local
        let modelGatedInitialStep = OnboardingFlow.modelGatedResumeStep(
            requestedStep: permissionGatedInitialStep,
            initialBackend: initialBackend,
            resolvedBackend: sanitizedInitialBackend
        )
        let meetingGatedInitialStep = initialUseCase.includesMeetings
            ? OnboardingFlow.setupGatedResumeStep(
                requestedStep: modelGatedInitialStep,
                setupStep: .meetingTranscription,
                isReady: OnlineDictationSetupPolicy.isMeetingReady(config: appState.config,
                    authenticated: appState.isOpenRouterAuthenticated,
                    localModelReady: sanitizedInitialMeetingBackend.isDownloaded)
            )
            : modelGatedInitialStep
        let initialQuillReady: Bool = {
            guard initialQuillEnabled else { return true }
            if sanitizedInitialQuillBackend.isOnDevice {
                return PostProcessorOption.defaultQuilOption.isDownloaded
            }
            if sanitizedInitialQuillBackend == .hosted(.chatGPT) {
                return ChatGPTAuthManager.shared.isAuthenticated
            }
            if sanitizedInitialQuillBackend == .hosted(.openRouter) {
                return OnlineDictationSetupPolicy.isReady(
                    authenticated: OpenRouterAuthManager.shared.isAuthenticated,
                    modelID: OnboardingQuillModelSelection.openRouterModel(in: appState.config)
                )
            }
            return false
        }()
        let quillGatedInitialStep = initialUseCase.includesDictation
            ? OnboardingFlow.setupGatedResumeStep(
                requestedStep: meetingGatedInitialStep,
                setupStep: .quill,
                isReady: initialQuillReady
            )
            : meetingGatedInitialStep
        let effectiveInitialStep = OnboardingFlow.normalizedStep(quillGatedInitialStep, for: initialUseCase)

        _currentStep = State(initialValue: effectiveInitialStep)
        _hasCompletedPermissionsStep = State(initialValue: OnboardingFlow.hasCompletedPermissionsStep(
            resumingAt: effectiveInitialStep
        ))
        _userName = State(initialValue: initialUserName)
        _selectedUseCase = State(initialValue: initialUseCase)
        _selectedBackend = State(initialValue: sanitizedInitialBackend)
        _selectedMeetingBackend = State(initialValue: sanitizedInitialMeetingBackend)
        _selectedCohereLanguage = State(initialValue: initialCohereLanguage)
        _selectedHotkey = State(initialValue: initialHotkey)
        _summaryBackend = State(initialValue: initialSummaryBackend)
        _quillEnabled = State(initialValue: initialQuillEnabled)
        _cleanupEnabled = State(initialValue: initialCleanupEnabled)
        _quillBackend = State(initialValue: sanitizedInitialQuillBackend)
        _customMenuBarEmoji = State(
            initialValue: MenuBarIconRenderer.emoji(from: appState.config.menuBarIcon) ?? ""
        )
        _modelDownloadProgress = State(initialValue: sanitizedInitialBackend == initialBackend ? initialModelDownloadProgress : nil)
        _modelDownloadStatus = State(initialValue: sanitizedInitialBackend == initialBackend ? initialModelDownloadStatus : nil)
        _micGranted = State(initialValue: initialMicGranted)
        _accessibilityGranted = State(initialValue: initialAccessibilityGranted)
        _inputMonitoringGranted = State(initialValue: initialInputMonitoringGranted)
        _screenRecordingGranted = State(initialValue: initialScreenRecordingGranted)
        _systemAudioGranted = State(initialValue: initialSystemAudioGranted)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: modelStep
                case 2: hotkeyStep
                case 3: permissionsStep
                case 4:
                    if usesOnlineDictationSetup {
                        onlineDictationTestStep
                    } else {
                        dictationTestStep
                    }
                case 5: meetingSummaryStep
                case 6: calendarAccessStep
                case 7: appearanceStep
                case 8: learnStep
                case 9: meetingTranscriptionStep
                case 10: quillStep
                case 11: reviewStep
                case 12: vocabularyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(MuesliTheme.surfaceBorder)

            // Bottom bar
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Step \(currentStepIndex + 1) of \(totalSteps)  ·  \(currentStepLabel)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MuesliTheme.textSecondary)
                    ProgressView(value: Double(currentStepIndex + 1), total: Double(totalSteps))
                        .tint(MuesliTheme.accent)
                        .frame(width: 220)
                }

                Spacer()

                HStack(spacing: MuesliTheme.spacing12) {
                    if canGoBack {
                        Button("Back") {
                            goToPreviousStep()
                        }
                        .buttonStyle(.plain)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .padding(.horizontal, MuesliTheme.spacing16)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    primaryButton
                }
            }
            .padding(.horizontal, MuesliTheme.spacing32)
            .padding(.vertical, MuesliTheme.spacing16)
        }
        .background(MuesliTheme.backgroundBase)
        .preferredColorScheme(.light)
        .onAppear {
            saveProgress(atStep: currentStep)
        }
        .onChange(of: currentStep) { _, step in
            saveProgress(atStep: step)
        }
        .onChange(of: userName) { _, _ in
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedUseCase) { previousUseCase, newUseCase in
            if previousUseCase != newUseCase {
                hasCompletedPermissionsStep = false
            }
            if !orderedSteps.contains(currentStep) {
                currentStep = OnboardingFlow.normalizedStep(currentStep, for: selectedUseCase)
            }
            resetModelDownloadForBackendChange()
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedBackend) { previousBackend, newBackend in
            if selectedMeetingBackend == previousBackend, newBackend.supportsMeetingTranscription {
                selectedMeetingBackend = newBackend
            }
            resetModelDownloadForBackendChange()
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedMeetingBackend) { _, _ in
            resetMeetingModelDownloadForBackendChange()
            saveProgress(atStep: currentStep)
        }
        .onChange(of: summaryBackend) { _, _ in
            saveProgress(atStep: currentStep)
        }
        .onChange(of: quillEnabled) { _, enabled in
            if !enabled && !cleanupEnabled { cancelQuillModelDownload() }
            saveProgress(atStep: currentStep)
        }
        .onChange(of: cleanupEnabled) { _, _ in saveProgress(atStep: currentStep) }
        .onChange(of: quillBackend) { _, backend in
            if !backend.isOnDevice && !cleanupEnabled { cancelQuillModelDownload() }
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedCohereLanguage) { _, _ in
            saveProgress(atStep: currentStep)
        }
        .onChange(of: modelReadyBackend) { _, _ in
            startDictationTestMonitorIfReady()
        }
        .onChange(of: isModelStillDownloading) { _, _ in
            startDictationTestMonitorIfReady()
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowModelDownloadIndicator {
                modelDownloadIndicator
                    .padding(.top, MuesliTheme.spacing16)
                    .padding(.trailing, MuesliTheme.spacing16)
            }
        }
    }

    // MARK: - Primary Button

    private var currentStepLabel: String {
        switch currentStep {
        case 0: return "Welcome"
        case 1: return "Dictation model"
        case 2: return "Shortcut"
        case 3: return "Permissions"
        case 4: return "Try it"
        case 5: return "Meeting summaries"
        case 6: return "Calendar"
        case 7: return "Appearance"
        case 8: return "How it works"
        case 9: return "Meeting model"
        case 10: return "Quill"
        case 11: return "Review"
        case 12: return "Your vocabulary"
        default: return "Setup"
        }
    }

    private var isQuillReady: Bool {
        guard quillEnabled else { return true }
        if quillBackend.isOnDevice {
            return PostProcessorOption.defaultQuilOption.isDownloaded
        }
        if quillBackend == .hosted(.chatGPT) {
            return appState.isChatGPTAuthenticated || chatGPTSignInDone
        }
        if quillBackend == .hosted(.openRouter) {
            return OnlineDictationSetupPolicy.isReady(
                authenticated: hasOpenRouterCredentialForSetup,
                modelID: OnboardingQuillModelSelection.openRouterModel(in: appState.config)
            )
        }
        return false
    }

    private var hasOpenRouterCredentialForSetup: Bool {
        appState.isOpenRouterAuthenticated
            || openRouterSignInDone
            || !quillAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (summaryBackend == .openRouter
                && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var usesOnlineMeetingSetup: Bool {
        appState.config.useOpenRouterForMeetings && !appState.config.offlineInference
    }

    private var isSelectedMeetingModelReady: Bool {
        OnlineDictationSetupPolicy.isMeetingReady(config: appState.config,
            authenticated: appState.isOpenRouterAuthenticated,
            localModelReady: meetingModelReadyBackend == selectedMeetingBackend
                || (selectedMeetingBackend == selectedBackend && modelReadyBackend == selectedBackend))
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch currentStep {
        case 0:
            onboardingButton("Continue", enabled: !userName.trimmingCharacters(in: .whitespaces).isEmpty) {
                goToNextStep()
            }
        case 1:
            if usesOnlineDictationSetup {
                onboardingButton("Continue", enabled: isOnlineDictationSetupReady) { goToNextStep() }
            } else if modelReadyBackend == selectedBackend && isRomanizationModelReady {
                onboardingButton("Continue", enabled: true) { goToNextStep() }
            } else if isModelStillDownloading {
                onboardingButton(isModelPreparingAfterDownload ? "Preparing model…" : "Downloading model…", enabled: false) {}
            } else {
                onboardingButton(selectedBackend.isDownloaded ? "Prepare model" : "Download model", enabled: selectedBackend.isCompatible()) {
                    ensureModelDownloadStarted()
                }
            }
        case 2:
            onboardingButton("Continue", enabled: true) {
                goToNextStep()
            }
        case 3:
            HStack(spacing: MuesliTheme.spacing12) {
                if !requiredPermissionsGranted {
                    skipButton("Explore without recording") { finishOnboarding(withKey: true) }
                }
                onboardingButton(currentStepIndex == orderedSteps.count - 1 ? "Finish" : "Continue", enabled: requiredPermissionsGranted) {
                    advancePastPermissions()
                }
            }
        case 4:
            if usesOnlineDictationSetup || dictationTestResult != nil {
                onboardingButton("Continue", enabled: true) { goToNextStep() }
            } else {
                HStack(spacing: MuesliTheme.spacing12) {
                    skipButton("Skip test") { goToNextStep() }
                    onboardingButton("Continue", enabled: false) {}
                }
            }
        case 5:
            HStack(spacing: MuesliTheme.spacing12) {
                skipButton { goToNextStep() }
                onboardingButton("Continue", enabled: true) { goToNextStep() }
            }
        case 6:
            HStack(spacing: MuesliTheme.spacing12) {
                skipButton("Not now") { goToNextStep() }
                onboardingButton("Continue", enabled: true) { goToNextStep() }
            }
        case 7:
            onboardingButton("Continue", enabled: true) {
                goToNextStep()
            }
        case 8:
            onboardingButton("Set up my choices", enabled: true) { goToNextStep() }
        case 9:
            if usesOnlineMeetingSetup {
                onboardingButton("Continue", enabled: isSelectedMeetingModelReady) { goToNextStep() }
            } else if isSelectedMeetingModelReady {
                onboardingButton("Continue", enabled: true) { goToNextStep() }
            } else if meetingModelDownloadTask != nil {
                onboardingButton("Preparing meeting model…", enabled: false) {}
            } else {
                onboardingButton(selectedMeetingBackend.isDownloaded ? "Prepare meeting model" : "Download meeting model", enabled: selectedMeetingBackend.isCompatible()) {
                    startMeetingModelDownload()
                }
            }
        case 10:
            if quillEnabled && quillBackend.isOnDevice && !PostProcessorOption.defaultQuilOption.isDownloaded {
                onboardingButton(isDownloadingQuillModel ? "Downloading Quill model…" : "Download Quill model", enabled: !isDownloadingQuillModel) {
                    startQuillModelDownload()
                }
            } else {
                onboardingButton("Continue", enabled: isQuillReady) { goToNextStep() }
            }
        case 11:
            onboardingButton("Finish setup", enabled: true) {
                finishOnboarding(withKey: true)
            }
        case 12:
            onboardingButton("Continue", enabled: vocabularyTask == nil) { goToNextStep() }
        default:
            EmptyView()
        }
    }

    private func goToNextStep() {
        guard currentStepIndex < orderedSteps.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = orderedSteps[currentStepIndex + 1]
        }
    }

    private func goToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = orderedSteps[currentStepIndex - 1]
        }
    }

    @ViewBuilder
    private func onboardingButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, MuesliTheme.spacing20)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(enabled ? MuesliTheme.accent : MuesliTheme.accent.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func skipButton(_ title: String = "Skip", action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(MuesliTheme.body())
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }

    private var shouldShowModelDownloadIndicator: Bool {
        isModelStillDownloading || modelDownloadError != nil || isShowingModelReadyIndicator
    }

    private var isShowingModelReadyIndicator: Bool {
        modelReadyIndicatorBackend == selectedBackend && !isModelStillDownloading && modelDownloadError == nil
    }

    private var isSelectedModelReadyForDictationTest: Bool {
        !usesOnlineDictationSetup && modelReadyBackend == selectedBackend && isRomanizationModelReady
            && !isModelStillDownloading && modelDownloadError == nil
    }

    private var canGoBack: Bool {
        OnboardingFlow.canGoBack(
            from: currentStep,
            useCase: selectedUseCase,
            dictationTestSucceeded: dictationTestResult != nil
        )
    }

    private var modelDownloadIndicator: some View {
        let progress = modelDownloadProgress.map { min(max($0, 0), 1) }
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MuesliTheme.surfaceBorder)
                    .frame(width: 24, height: 24)

                if isModelPreparingAfterDownload {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                } else if let progress {
                    ModelDownloadProgressShape(progress: progress)
                        .fill(MuesliTheme.accent)
                        .frame(width: 24, height: 24)

                    Circle()
                        .stroke(MuesliTheme.accent.opacity(0.7), lineWidth: 1)
                        .frame(width: 24, height: 24)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(modelDownloadIndicatorTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(modelDownloadError == nil ? MuesliTheme.textSecondary : MuesliTheme.recording)
                    .lineLimit(1)
                Text(modelDownloadIndicatorDetail(progress: progress))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MuesliTheme.backgroundRaised.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        .frame(width: 260, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.2), value: shouldShowModelDownloadIndicator)
    }

    private var modelDownloadIndicatorTitle: String {
        if let snapshot = modelDownloadSnapshot {
            switch snapshot.phase {
            case .downloading: return "Downloading \(selectedBackend.label)"
            case .preparing: return "Preparing \(selectedBackend.label)"
            case .ready: return "\(selectedBackend.label) ready"
            case .paused: return "Download paused"
            case .failed: return "Download failed"
            }
        }
        if modelDownloadError != nil {
            return "Download failed"
        }
        if isShowingModelReadyIndicator {
            return "\(selectedBackend.label) ready"
        }
        return "Preparing \(selectedBackend.label)"
    }

    private func modelDownloadIndicatorDetail(progress: Double?) -> String {
        if let modelDownloadError {
            return modelDownloadError
        }
        if isShowingModelReadyIndicator {
            return "Ready to test"
        }
        if let snapshot = modelDownloadSnapshot {
            return modelDownloadSnapshotDetail(snapshot)
        }
        if let modelDownloadStatus {
            return modelDownloadStatus
        }
        if let progress {
            return "\(Int((progress * 100).rounded()))% complete"
        }
        return "Downloading..."
    }

    private func modelDownloadSnapshotDetail(_ snapshot: ModelDownloadProgress) -> String {
        var details: [String] = []
        if let currentFile = snapshot.currentFile?.split(separator: "/").last.map(String.init), !currentFile.isEmpty {
            details.append(currentFile)
        }
        if snapshot.totalFileCount > 0 {
            let completed = min(max(snapshot.completedFileCount, 0), snapshot.totalFileCount)
            let remaining = snapshot.totalFileCount - completed
            details.append("\(completed) of \(snapshot.totalFileCount) files")
            if remaining > 0 {
                details.append("\(remaining) left")
            }
        }
        if let total = snapshot.totalBytes, total > 0 {
            details.append("\(ModelDownloadDisplayFormatting.bytes(snapshot.completedBytes)) / \(ModelDownloadDisplayFormatting.bytes(total))")
            if snapshot.completedBytes < total {
                details.append("\(ModelDownloadDisplayFormatting.bytes(total - snapshot.completedBytes)) left")
            }
        } else if let currentTotal = snapshot.currentFileTotalBytes, currentTotal > 0 {
            details.append("\(ModelDownloadDisplayFormatting.bytes(snapshot.currentFileCompletedBytes)) / \(ModelDownloadDisplayFormatting.bytes(currentTotal))")
            if snapshot.currentFileCompletedBytes < currentTotal {
                details.append("\(ModelDownloadDisplayFormatting.bytes(currentTotal - snapshot.currentFileCompletedBytes)) left")
            }
        }
        if snapshot.phase == .downloading {
            if snapshot.bytesPerSecond > 0 {
                details.append(ModelDownloadDisplayFormatting.rate(snapshot.bytesPerSecond))
            }
            if let eta = snapshot.estimatedSecondsRemaining,
               let formattedETA = ModelDownloadDisplayFormatting.eta(eta) {
                details.append("\(formattedETA) left")
            }
            if snapshot.retryCount > 0 {
                details.append("retry \(snapshot.retryCount)/3")
            }
        } else if let message = snapshot.message, !message.isEmpty {
            details.append(message)
        }
        return details.isEmpty ? (snapshot.message ?? "Downloading...") : details.joined(separator: " · ")
    }

    private var dictationTestSubtitle: AttributedString {
        let markdown: String
        if isSelectedModelReadyForDictationTest {
            markdown = selectedUseCase.includesVoiceNotes && !selectedUseCase.includesDictation
                ? "Hold **\(selectedHotkey.label)** to record a voice note, then release.\nYour words should appear below."
                : "Hold **\(selectedHotkey.label)** and say something, then release.\nYour words should appear below."
        } else {
            markdown = dictationTestPreparationSubtitleMarkdown
        }
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown.replacingOccurrences(of: "**", with: ""))
    }

    private var dictationTestPreparationSubtitleMarkdown: String {
        let unlockCopy = selectedUseCase.includesVoiceNotes && !selectedUseCase.includesDictation
            ? "Voice note test"
            : "Dictation"
        if isModelPreparingAfterDownload {
            return "Optimizing **\(selectedBackend.label)** for this Mac.\n\(unlockCopy) will unlock when it is ready."
        }
        return "Preparing **\(selectedBackend.label)** for your first test.\n\(unlockCopy) will unlock when the model is ready."
    }

    private var modelPreparationHints: [String] {
        if selectedBackend.backend == "whisper" {
            return [
                "Compiling CoreML files for the Neural Engine",
                "Preparing the first dictation test",
                "Future launches will skip most of this",
                "We'll bring Muesli+ forward when ready",
            ]
        }
        return [
            "Preparing the first dictation test",
            "Future launches will skip most of this",
            "We'll bring Muesli+ forward when ready",
        ]
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            Spacer()

            Image(nsImage: Self.bundledMuesliLogo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityLabel("Muesli+")

            VStack(spacing: MuesliTheme.spacing8) {
                Text("Welcome to Muesli+")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("Local-first dictation and meeting transcription for macOS.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text("Your name")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)

                OnboardingTextField(text: $userName, placeholder: "Enter your name", onSubmit: {
                    if !userName.trimmingCharacters(in: .whitespaces).isEmpty {
                        goToNextStep()
                    }
                })
                    .frame(width: 280, height: 32)
            }

            VStack(spacing: MuesliTheme.spacing8) {
                Text("What will you use Muesli+ for?")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)

                LazyVGrid(
                    columns: [
                        GridItem(.fixed(132), spacing: MuesliTheme.spacing8),
                        GridItem(.fixed(132), spacing: MuesliTheme.spacing8),
                    ],
                    spacing: MuesliTheme.spacing8
                ) {
                    useCaseCard(
                        icon: "waveform",
                        title: "Voice Notes",
                        subtitle: "Record in Muesli+",
                        selected: selectedUseCase.includesVoiceNotes
                    ) {
                        toggleCapability(.voiceNotes)
                    }

                    useCaseCard(
                        icon: "keyboard.fill",
                        title: "Dictation",
                        subtitle: "Paste into apps",
                        selected: selectedUseCase.includesDictation
                    ) {
                        toggleCapability(.dictation)
                    }

                    useCaseCard(
                        icon: "person.2.fill",
                        title: "Meetings",
                        subtitle: "Notes and summaries",
                        selected: selectedUseCase.includesMeetings
                    ) {
                        toggleCapability(.meetings)
                    }

                    useCaseCard(
                        icon: "rectangle.3.group.fill",
                        title: "Everything",
                        subtitle: "All workflows",
                        selected: selectedUseCase == .everything
                    ) {
                        toggleEverything()
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func useCaseCard(
        icon: String,
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? .white.opacity(0.72) : MuesliTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .white : MuesliTheme.textSecondary)
            .frame(width: 132, height: 74)
            .background(selected ? MuesliTheme.accent : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(selected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }

    // MARK: - Learn the building blocks

    private var learnStep: some View {
        ScrollView {
        VStack(spacing: 12) {
            ConceptsView()
            Toggle("Clean up spelling and spoken corrections automatically", isOn: $cleanupEnabled)
                .toggleStyle(.switch)
                .frame(maxWidth: 620)
            Text("Recommended. Uses the small local language model once downloaded; nothing is sent online. You can turn this off in Settings.")
                .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                .frame(maxWidth: 620, alignment: .leading)
            if cleanupEnabled {
                if #available(macOS 15.0, *) {
                    if PostProcessorOption.defaultQuilOption.isDownloaded {
                        Label("Local cleanup is ready", systemImage: "checkmark.circle.fill")
                            .font(MuesliTheme.caption())
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(isDownloadingQuillModel ? "Downloading local cleanup…" : "Download local cleanup (about 510 MB)") {
                                startQuillModelDownload()
                            }
                            .disabled(isDownloadingQuillModel || appState.config.offlineInference)
                            if let progress = quillModelDownloadProgress, isDownloadingQuillModel {
                                ProgressView(value: progress)
                            }
                            if let message = quillModelDownloadError ?? quillModelDownloadStatus {
                                Text(message).font(MuesliTheme.caption())
                            }
                            Text(appState.config.offlineInference
                                 ? "Switch to online mode to download. Cleanup itself runs offline."
                                 : "This download also powers Roman-letter Hindi, vocabulary suggestions, and local Quill. You can continue setup while it downloads.")
                                .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                        }.frame(maxWidth: 620, alignment: .leading)
                    }
                } else {
                    Text("Local cleanup requires macOS 15 or later. Your original transcript remains available.")
                        .font(MuesliTheme.caption())
                }
            }
        }
        .padding(.bottom, 16)
        }
    }

    /// Pure education surface: can be reviewed without saving onboarding progress
    /// or requesting permissions from a preview/test process.
    struct ConceptsView: View {
    var body: some View {
        VStack(spacing: MuesliTheme.spacing20) {
            VStack(spacing: MuesliTheme.spacing8) {
                Text("Four simple building blocks")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("Choose each part once now. Muesli+ will use those choices automatically, and you can change them later.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 590)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: MuesliTheme.spacing12, alignment: .top), GridItem(.flexible(), alignment: .top)],
                spacing: MuesliTheme.spacing12
            ) {
                setupConceptCard(
                    number: "1",
                    icon: "waveform",
                    title: "Dictation",
                    explanation: "Listens to your microphone and writes the words you say.",
                    privacy: "Local or OpenRouter · your choice"
                )
                setupConceptCard(
                    number: "2",
                    icon: "text.badge.checkmark",
                    title: "Cleanup",
                    explanation: "Optionally fixes spelling, grammar, and spoken corrections before your words are pasted. It should not rewrite your meaning.",
                    privacy: "Separate language model · local or hosted"
                )
                setupConceptCard(
                    number: "3",
                    icon: "list.bullet.clipboard",
                    title: "Meeting notes",
                    explanation: "A speech model writes the transcript, on this Mac or online through OpenRouter. A separate optional language model turns that text into notes and action items.",
                    privacy: "Local audio by default · online transcription shares audio"
                )
                setupConceptCard(
                    number: "4",
                    icon: "pencil.and.scribble",
                    title: "Quill",
                    explanation: "Highlight text, hold a shortcut, and say how you want it rewritten.",
                    privacy: "Optional · local or hosted"
                )
            }
            .frame(maxWidth: 620)

            Label(
                "Cleanup keeps your message: ‘Friday, sorry, Monday’ becomes ‘Monday’. Quill changes it only when you ask, for example ‘make this friendlier’. Review model output before sending.",
                systemImage: "lightbulb.fill"
            )
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

            Label("Want to try speaking silently? After setup, open Lip dictation · Lab. It reads lip movements from a camera clip or video, then uses a small local language model to suggest English text. Both models must be installed; no microphone is used. This optional experiment can make mistakes—always review its suggestions.", systemImage: "video")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(maxWidth: 620, alignment: .leading)
        }
        .padding(.horizontal, MuesliTheme.spacing32)
        .padding(.top, MuesliTheme.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func setupConceptCard(
        number: String,
        icon: String,
        title: String,
        explanation: String,
        privacy: String
    ) -> some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
            ZStack {
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(MuesliTheme.accent.opacity(0.1))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MuesliTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(number).  \(title)")
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(explanation)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(privacy)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuesliTheme.success)
            }

            Spacer(minLength: 0)
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    }

    // MARK: - Step 2: Model Selection

    private var usesOnlineDictationSetup: Bool {
        appState.config.resolvedDictationProvider == .openRouter
    }

    private var isOnlineDictationSetupReady: Bool {
        OnlineDictationSetupPolicy.isReady(
            authenticated: appState.isOpenRouterAuthenticated,
            modelID: appState.config.openRouterDictationModel
        )
    }

    private var onlineDictationTestStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            Image(systemName: "network").font(.system(size: 32))
            Text("Ready to try online dictation").font(MuesliTheme.title1())
            Text("After finishing setup, hold \(selectedHotkey.label) and say a short sentence. Your audio will be sent to your selected OpenRouter provider; internet access and provider credits are required. No local speech-model download is needed.")
                .font(MuesliTheme.body())
                .multilineTextAlignment(.center)
            Text("This setup screen has not tested the provider connection or transcription quality.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .padding(MuesliTheme.spacing32)
    }

    private var modelStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            VStack(spacing: MuesliTheme.spacing8) {
                Text("Choose how Muesli+ hears you")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("Choose where dictation runs. Speech recognition turns your audio into text; a separate language model can clean up that text.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, MuesliTheme.spacing24)

            ScrollView {
                VStack(spacing: MuesliTheme.spacing8) {
                    Picker("Dictation runs", selection: Binding(
                        get: { usesOnlineDictationSetup },
                        set: { online in
                            resetModelDownloadForBackendChange()
                            controller.updateConfig {
                                $0.dictationProvider = online ? DictationProvider.openRouter.rawValue : DictationProvider.local.rawValue
                            }
                        }
                    )) {
                        Text("On this Mac").tag(false)
                        Text("Online · OpenRouter").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(appState.config.offlineInference)

                    if usesOnlineDictationSetup {
                        OnlineDictationSetupView(controller: controller, appState: appState)
                    } else {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                        Text("What do you usually speak?")
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        HStack(spacing: MuesliTheme.spacing8) {
                            languageChoiceButton("English", icon: "textformat.abc", backend: .parakeetUnified)
                            languageChoiceButton("Many languages", icon: "globe", backend: .parakeetMultilingual)
                            languageChoiceButton("Hinglish", icon: "character.bubble", backend: .bodhanFlexInt8)
                        }
                    }
                    .padding(MuesliTheme.spacing12)
                    .background(MuesliTheme.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                            .strokeBorder(MuesliTheme.accent.opacity(0.15), lineWidth: 1)
                    )

                    modelCard(option: selectedBackend)

                    if selectedBackend.backend == "bodhan" {
                        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                            Toggle("Write Hindi in English letters", isOn: Binding(
                                get: { controller.config.romanizeHindi },
                                set: { enabled in
                                    controller.updateConfig { $0.romanizeHindi = enabled }
                                    resetModelDownloadForBackendChange()
                                }
                            ))
                            .font(MuesliTheme.headline())
                            Text("First, Bodhan Flex recognizes your Hindi and English speech. Then a small local language model writes the Hindi words in Roman letters—for example, नमस्ते becomes namaste. This is romanization, not translation.")
                                .font(MuesliTheme.body())
                            Text("Two downloads: the speech model shown above and Qwen3.5 0.8B (about 510 MB). Both stages run on this Mac after setup. English and numbers pass through unchanged. If romanization fails, your original transcript is kept.")
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textSecondary)
                            Text("Experimental: Roman spellings may be inaccurate. Review the result before sending it.")
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.transcribing)
                        }
                        .padding(MuesliTheme.spacing16)
                        .background(MuesliTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMoreModels.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Other models")
                                .font(MuesliTheme.caption())
                            Image(systemName: showMoreModels ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, MuesliTheme.spacing4)

                    if showMoreModels {
                        ForEach(onboardingAlternativeModels.filter { $0 != selectedBackend }, id: \.model) { option in
                            modelCard(option: option)
                        }

                        Text("More models are available after onboarding.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, MuesliTheme.spacing4)
                    }

                    if selectedBackend.backend == BackendOption.cohereTranscribe.backend {
                        cohereLanguageCard
                    }
                    }
                }
                .padding(.horizontal, MuesliTheme.spacing32)
            }

        }
        .frame(maxWidth: .infinity)
    }

    private func languageChoiceButton(_ title: String, icon: String, backend: BackendOption) -> some View {
        let isSelected = selectedBackend == backend
        return Button {
            controller.updateConfig { $0.romanizeHindi = backend == .bodhanFlexInt8 }
            selectedBackend = backend
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : MuesliTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSelected ? MuesliTheme.accent : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cohereLanguageCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text("Cohere language")
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textPrimary)

            Text("Cohere does not auto-detect language, so pick the language you want it to transcribe.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)

            FixedWidthPopUp(
                selection: selectedCohereLanguage.label,
                options: CohereTranscribeLanguage.allCases.map(\.label)
            ) { label in
                guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
                selectedCohereLanguage = language
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.top, MuesliTheme.spacing8)
    }

    private func modelCard(option: BackendOption) -> some View {
        let isSelected = selectedBackend == option
        let incompatibilityReason = option.incompatibilityReason()
        return Button {
            guard option.isCompatible() else { return }
            selectedBackend = option
        } label: {
            HStack(spacing: MuesliTheme.spacing12) {
                Circle()
                    .fill(isSelected ? MuesliTheme.accent : Color.clear)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.textTertiary, lineWidth: 1.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(incompatibilityReason == nil ? MuesliTheme.textPrimary : MuesliTheme.textTertiary)
                        if option == BackendOption.onboardingDefault {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(MuesliTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    Text(onboardingDescription(for: option))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(incompatibilityReason == nil ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                    if let incompatibilityReason {
                        Label(incompatibilityReason, systemImage: "exclamationmark.triangle")
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(MuesliTheme.spacing12)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(incompatibilityReason != nil)
        .help(incompatibilityReason ?? option.label)
    }

    private func onboardingDescription(for option: BackendOption) -> String {
        if option == .parakeetUnified {
            return "Best first choice for clear English dictation. Fast and accurate on Apple silicon."
        } else if option == .parakeetMultilingual {
            return "Choose this when you regularly speak languages other than English."
        } else if option == .whisperHinglishRomanized {
            return "For Hindi-English code-switching. Hindi is written in Roman letters while English stays English."
        } else if option == .whisperTiny {
            return "Smallest multilingual download. Quick to try, but less accurate with noise and accents."
        } else if option == .whisperSmall {
            return "A balanced multilingual model for accents, mixed audio, and everyday notes."
        } else if option == .cohereTranscribe {
            return "A very large model for difficult accents and audio. Slower, with no live words while speaking."
        } else if option == .nemotron35Multilingual {
            return "Shows live multilingual text as you speak. Best for users who value immediate feedback."
        }
        return option.description
    }

    // MARK: - Step 3: Appearance

    private var appearanceStep: some View {
        ScrollView {
            VStack(spacing: MuesliTheme.spacing16) {
                VStack(spacing: MuesliTheme.spacing4) {
                    Text("Make Muesli+ yours")
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    Text("Choose a light color theme and the menu bar icon you will recognize at a glance.")
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Color theme")
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text("All six start in light mode. Dark mode is an optional switch below.")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: MuesliTheme.spacing8), count: 6),
                    spacing: MuesliTheme.spacing8
                ) {
                    ForEach(MuesliColorTheme.allCases) { theme in
                        colorThemeButton(theme)
                    }
                }

                Divider().background(MuesliTheme.surfaceBorder)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu bar icon")
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text("All 34 built-in choices are shown below. Recording and transcribing keep their clear animated status icons.")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 58), spacing: MuesliTheme.spacing8),
                        count: 7
                    ),
                    spacing: MuesliTheme.spacing8
                ) {
                    ForEach(MenuBarIconRenderer.options, id: \.id) { option in
                        statusIconButton(option)
                    }
                }

                HStack(spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use any emoji")
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        Text("Click the field to open the macOS emoji picker.")
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }

                    Spacer(minLength: MuesliTheme.spacing8)

                    OnboardingEmojiField(text: $customMenuBarEmoji) { choice in
                        selectStatusIcon(choice)
                    }
                    .frame(width: 150, height: 32)
                }
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(MuesliTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )

                Toggle("Use dark mode after setup", isOn: Binding(
                    get: { appState.config.darkMode },
                    set: { value in controller.updateConfig { $0.darkMode = value } }
                ))
                .toggleStyle(.switch)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, MuesliTheme.spacing32)
            .padding(.top, MuesliTheme.spacing20)
            .padding(.bottom, MuesliTheme.spacing16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func colorThemeButton(_ theme: MuesliColorTheme) -> some View {
        let isSelected = MuesliColorTheme.resolved(for: appState.config.recordingColorHex) == theme
        return Button {
            controller.updateConfig { $0.recordingColorHex = theme.hex }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: theme.hex))
                    .frame(width: 24, height: 24)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(theme.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isSelected ? Color(hex: theme.hex).opacity(0.10) : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isSelected ? Color(hex: theme.hex) : MuesliTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.label) color theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func statusIconButton(_ option: MenuBarIconRenderer.Option) -> some View {
        let isSelected = appState.config.menuBarIcon == option.id
        return Button {
            selectStatusIcon(option.id)
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let image = MenuBarIconRenderer.make(choice: option.id) {
                        Image(nsImage: image)
                            .renderingMode(
                                MenuBarIconRenderer.isEmojiChoice(option.id) ? .original : .template
                            )
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                .foregroundStyle(isSelected ? Color.white : MuesliTheme.textPrimary)
                .frame(width: 20, height: 20)

                Text(option.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : MuesliTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 3)
            .background(isSelected ? MuesliTheme.accent : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(option.label)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectStatusIcon(_ choice: String) {
        customMenuBarEmoji = MenuBarIconRenderer.emoji(from: choice) ?? ""
        controller.updateConfig { $0.menuBarIcon = choice }
    }

    // MARK: - Permissions (sequential, one at a time)

    /// The ordered list of permissions to grant during onboarding.
    /// Request the permission union for the capabilities selected during setup.
    /// Screen Recording remains optional because it enriches meeting context but
    /// is not required to capture the meeting's audio.
    private var permissionSteps: [(icon: String, name: String, description: String, granted: Bool, action: () -> Void)] {
        var steps: [(String, String, String, Bool, () -> Void)] = [
            ("mic.fill", "Microphone", "Record audio for voice notes, dictation, and meetings", micGranted, {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            })
        ]
        if selectedUseCase.includesPushToTalk {
            if selectedUseCase.includesDictation {
                steps += [
                    ("hand.raised.fill", "Accessibility", "Paste transcribed text into other apps", accessibilityGranted, requestAccessibilityPermission),
                ]
            }
            steps += [
            ("keyboard.fill", "Input Monitoring", "Detect hotkey for push-to-talk recording", inputMonitoringGranted, {
                self.controller.beginSystemPermissionGuide(for: .inputMonitoring)
                if !CGRequestListenEventAccess() {
                    self.openSystemSettings(
                        "Privacy_ListenEvent",
                        yieldBehavior: OnboardingSystemSettingsYieldPolicy.behavior(for: .inputMonitoring)
                    )
                }
            }),
            ]
        }
        if selectedUseCase.includesMeetings {
            if appState.config.useCoreAudioTap {
                steps.append((
                    "speaker.wave.2.fill",
                    "System Audio",
                    "Capture meeting audio from other participants",
                    systemAudioGranted,
                    {
                        Task {
                            let granted = await CoreAudioSystemRecorder.requestSystemAudioAccess()
                            await MainActor.run {
                                self.systemAudioGranted = granted
                                if granted {
                                    self.notePermissionGranted("System Audio")
                                } else {
                                    self.saveProgress(atStep: self.currentStep)
                                }
                            }
                        }
                    }
                ))
            } else {
                steps.append((
                    "rectangle.dashed.badge.record",
                    "Screen & System Audio",
                    "Capture meeting audio from other participants",
                    screenRecordingGranted,
                    { CGRequestScreenCaptureAccess() }
                ))
            }
        }
        return steps
    }

    /// Index of the current permission being requested.
    private var currentPermissionIndex: Int {
        for (i, step) in permissionSteps.enumerated() {
            if !step.granted { return i }
        }
        return permissionSteps.count
    }

    private var permissionsStep: some View {
        let steps = permissionSteps
        let idx = currentPermissionIndex
        let total = steps.count
        let confirmationIndex = recentlyGrantedPermissionName.flatMap { grantedName in
            steps.firstIndex { $0.name == grantedName }
        }
        let displayIndex = confirmationIndex ?? idx

        return VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            if displayIndex < total {
                let step = steps[displayIndex]
                let isConfirmingGrant = recentlyGrantedPermissionName == step.name

                VStack(spacing: MuesliTheme.spacing8) {
                    Text("Permission \(displayIndex + 1) of \(total)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .textCase(.uppercase)

                    Text(step.name)
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    Text(step.description)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Image(systemName: step.icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(isConfirmingGrant ? MuesliTheme.success : MuesliTheme.accent)
                    .frame(height: 64)

                Button {
                    if grantingPermissionName == step.name && !isConfirmingGrant {
                        guard !isWaitingForNativePermissionPrompt(step.name) else { return }
                        openSystemSettingsForPermission(at: displayIndex)
                    } else {
                        grantingPermissionName = step.name
                        recentlyGrantedPermissionName = nil
                        saveProgress(atStep: currentStep)
                        step.action()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isConfirmingGrant {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(permissionButtonTitle(for: step.name, isConfirmingGrant: isConfirmingGrant))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.vertical, MuesliTheme.spacing12)
                    .background(isConfirmingGrant ? MuesliTheme.success : MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
                .disabled(isConfirmingGrant || isWaitingForNativePermissionPrompt(step.name))
                .animation(.easeInOut(duration: 0.2), value: isConfirmingGrant)

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(progressDotColor(
                                index: i,
                                currentIndex: displayIndex,
                                isConfirmingGrant: isConfirmingGrant
                            ))
                            .frame(width: 8, height: 8)
                    }
                }

                if isWaitingForNativePermissionPrompt(step.name) {
                    Text("Respond to the macOS permission prompt")
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                } else {
                    Button {
                        openSystemSettingsForPermission(at: displayIndex)
                    } label: {
                        Text("Not seeing a prompt? Open System Settings")
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if step.name == "Input Monitoring", grantingPermissionName == step.name {
                    Button {
                        openApplicationsFolder()
                    } label: {
                        Text("Need to add Muesli+ manually? Open Applications")
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if selectedUseCase.canSwitchToVoiceNotesOnly && step.name == "Accessibility" {
                    Button {
                        switchToVoiceNotesOnly()
                    } label: {
                        VStack(spacing: 2) {
                            Text("Use Voice Notes instead")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Keeps the hotkey, skips paste permission")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        .foregroundStyle(MuesliTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            } else {
                // All granted
                VStack(spacing: MuesliTheme.spacing8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(MuesliTheme.success)

                    Text("All permissions granted")
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            startPermissionPolling()
            schedulePermissionAdvanceIfReady()
        }
        .onChange(of: requiredPermissionsGranted) { _, granted in
            if granted {
                schedulePermissionAdvanceIfReady()
            } else {
                cancelScheduledPermissionAdvance()
            }
        }
        .onDisappear {
            cancelScheduledPermissionAdvance()
            stopPermissionPolling()
            controller.dismissSystemPermissionGuide()
        }
    }

    private func permissionButtonTitle(for permissionName: String, isConfirmingGrant: Bool) -> String {
        if isConfirmingGrant { return "Granted" }
        if isWaitingForNativePermissionPrompt(permissionName) { return "Waiting for macOS..." }
        if grantingPermissionName == permissionName { return "Open Settings" }
        return "Grant Permission"
    }

    private func isWaitingForNativePermissionPrompt(_ permissionName: String) -> Bool {
        nativePermissionPromptName == permissionName
    }

    private func requestAccessibilityPermission() {
        nativePermissionPromptName = "Accessibility"
        controller.beginSystemPermissionGuide(for: .accessibility)
        controller.prepareOnboardingForNativePermissionPrompt()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if nativePermissionPromptName == "Accessibility", !accessibilityGranted {
                nativePermissionPromptName = nil
            }
        }
    }

    private func switchToVoiceNotesOnly() {
        grantingPermissionName = nil
        nativePermissionPromptName = nil
        recentlyGrantedPermissionName = nil
        controller.dismissSystemPermissionGuide()
        selectedUseCase = selectedUseCase.replacingDictationWithVoiceNotes
        currentStep = OnboardingFlow.normalizedStep(currentStep, for: selectedUseCase)
        saveProgress(atStep: currentStep)
    }

    private func systemSettingsPane(for permissionIndex: Int) -> String {
        let steps = permissionSteps
        guard permissionIndex < steps.count else { return "Privacy_Microphone" }
        switch steps[permissionIndex].name {
        case "Microphone": return "Privacy_Microphone"
        case "Accessibility": return "Privacy_Accessibility"
        case "Input Monitoring": return "Privacy_ListenEvent"
        case "System Audio", "Screen & System Audio": return "Privacy_ScreenCapture"
        default: return "Privacy_Microphone"
        }
    }

    private func progressDotColor(index: Int, currentIndex: Int, isConfirmingGrant: Bool) -> Color {
        if index < currentIndex || (isConfirmingGrant && index == currentIndex) {
            return MuesliTheme.success
        }
        if index == currentIndex {
            return MuesliTheme.accent
        }
        return MuesliTheme.surfaceBorder
    }

    private func permissionRow(icon: String, name: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: MuesliTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(description)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MuesliTheme.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(MuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing12)
        .animation(.easeInOut(duration: 0.25), value: granted)
    }

    private var requiredPermissionsGranted: Bool {
        OnboardingPermissionGate.hasRequiredPermissions(
            OnboardingPermissionSnapshot(
                microphone: micGranted,
                accessibility: accessibilityGranted,
                inputMonitoring: inputMonitoringGranted,
                systemAudio: systemAudioGranted,
                screenRecording: screenRecordingGranted
            ),
            for: selectedUseCase,
            useCoreAudioTap: appState.config.useCoreAudioTap
        )
    }

    private func startPermissionPolling() {
        refreshPermissions()
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            withAnimation { refreshPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func schedulePermissionAdvanceIfReady() {
        guard OnboardingFlow.shouldSchedulePermissionAdvance(
            currentStep: currentStep,
            requiredPermissionsGranted: requiredPermissionsGranted,
            hasCompletedPermissionsStep: hasCompletedPermissionsStep,
            hasScheduledTask: permissionAdvanceTask != nil
        ) else { return }

        let generation = UUID()
        permissionAdvanceGeneration = generation
        permissionAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard permissionAdvanceGeneration == generation, !Task.isCancelled else { return }
            guard currentStep == Self.permissionsStep, requiredPermissionsGranted else {
                permissionAdvanceGeneration = nil
                permissionAdvanceTask = nil
                return
            }

            permissionAdvanceGeneration = nil
            permissionAdvanceTask = nil
            advancePastPermissions()
        }
    }

    private func cancelScheduledPermissionAdvance() {
        permissionAdvanceGeneration = nil
        permissionAdvanceTask?.cancel()
        permissionAdvanceTask = nil
    }

    private func advancePastPermissions() {
        cancelScheduledPermissionAdvance()
        controller.dismissSystemPermissionGuide()
        let action = OnboardingFlow.permissionAdvanceAction(
            for: selectedUseCase,
            currentStepIndex: currentStepIndex,
            orderedStepCount: orderedSteps.count,
            hasCompletedPermissionsStep: hasCompletedPermissionsStep
        )
        hasCompletedPermissionsStep = true
        switch action {
        case .restartForDictationTest:
            saveProgressAndRestart()
        case .finish:
            finishOnboarding(withKey: false)
        case .next:
            goToNextStep()
        }
    }

    private func toggleCapability(_ capability: OnboardingCapability) {
        applyUseCaseSelection(OnboardingFlow.toggling(
            capability,
            in: OnboardingFlow.UseCaseSelectionState(
                selectedUseCase: selectedUseCase,
                selectionBeforeEverything: selectionBeforeEverything
            )
        ))
    }

    private func toggleEverything() {
        applyUseCaseSelection(OnboardingFlow.togglingEverything(
            in: OnboardingFlow.UseCaseSelectionState(
                selectedUseCase: selectedUseCase,
                selectionBeforeEverything: selectionBeforeEverything
            )
        ))
    }

    private func applyUseCaseSelection(_ state: OnboardingFlow.UseCaseSelectionState) {
        selectedUseCase = state.selectedUseCase
        selectionBeforeEverything = state.selectionBeforeEverything
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()

        if let grantingPermissionName, isPermissionGranted(named: grantingPermissionName) {
            notePermissionGranted(grantingPermissionName)
        }
    }

    private func isPermissionGranted(named permissionName: String) -> Bool {
        switch permissionName {
        case "Microphone":
            return micGranted
        case "Accessibility":
            return accessibilityGranted
        case "Input Monitoring":
            return inputMonitoringGranted
        case "System Audio":
            return systemAudioGranted
        case "Screen & System Audio":
            return screenRecordingGranted
        default:
            return false
        }
    }

    @MainActor
    private func notePermissionGranted(_ permissionName: String) {
        guard recentlyGrantedPermissionName != permissionName else { return }
        if PermissionDragGuidePermission(permissionName: permissionName) != nil {
            controller.dismissSystemPermissionGuide()
        }
        grantingPermissionName = nil
        nativePermissionPromptName = nil
        recentlyGrantedPermissionName = permissionName
        saveProgress(atStep: currentStep)
        controller.bringOnboardingToFront()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            if recentlyGrantedPermissionName == permissionName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    recentlyGrantedPermissionName = nil
                }
            }
        }
    }

    private func saveProgress(atStep step: Int? = nil) {
        guard !hasFinishedOnboarding else { return }
        let progress = OnboardingProgress(
            currentStep: step ?? currentStep,
            userName: userName,
            selectedBackendKey: selectedBackend.backend,
            selectedModelKey: selectedBackend.model,
            selectedMeetingBackendKey: selectedMeetingBackend.backend,
            selectedMeetingModelKey: selectedMeetingBackend.model,
            selectedCohereLanguageCode: selectedCohereLanguage.rawValue,
            hotkeyKeyCode: selectedHotkey.keyCode,
            hotkeyLabel: selectedHotkey.label,
            systemAudioRequested: systemAudioGranted,
            onboardingUseCaseRawValue: selectedUseCase.rawValue,
            summaryBackendKey: summaryBackend.backend,
            quillEnabled: quillEnabled,
            cleanupEnabled: cleanupEnabled,
            quillBackendKey: quillBackend.backend,
            modelDownloadProgress: modelDownloadProgress,
            modelDownloadStatus: modelDownloadStatus
        )
        OnboardingProgress.save(progress)
    }

    private func saveProgressAndRestart() {
        saveProgress(atStep: Self.dictationTestStep)
        controller.relaunchApp()
    }

    private func openSystemSettingsForPermission(at permissionIndex: Int) {
        let steps = permissionSteps
        var guidePermission: PermissionDragGuidePermission?
        if permissionIndex < steps.count {
            let permissionName = steps[permissionIndex].name
            grantingPermissionName = permissionName
            nativePermissionPromptName = nil
            recentlyGrantedPermissionName = nil
            saveProgress(atStep: currentStep)
            guidePermission = PermissionDragGuidePermission(permissionName: permissionName)
            if let guidePermission {
                controller.beginSystemPermissionGuide(for: guidePermission)
            }
        }
        openSystemSettings(
            systemSettingsPane(for: permissionIndex),
            yieldBehavior: OnboardingSystemSettingsYieldPolicy.behavior(for: guidePermission)
        )
    }

    private func openSystemSettings(
        _ pane: String,
        yieldBehavior: OnboardingSystemSettingsYieldBehavior
    ) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            if NSWorkspace.shared.open(url) {
                controller.yieldOnboardingFocusToSystemSettings(using: yieldBehavior)
            }
        }
    }

    private func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    // MARK: - Hotkey Configuration

    private var hotkeyStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text("Dictation Shortcut")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("Choose the key you'll hold to dictate. Press and hold the key to record, release to transcribe.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: MuesliTheme.spacing16) {
                // Current hotkey display
                Text(selectedHotkey.label)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .padding(.horizontal, MuesliTheme.spacing32)
                    .padding(.vertical, MuesliTheme.spacing16)
                    .background(MuesliTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )

                // Change button
                Button {
                    if isRecordingHotkey {
                        stopRecordingHotkey()
                    } else {
                        startRecordingHotkey()
                    }
                } label: {
                    Text(isRecordingHotkey ? "Press a modifier key..." : "Change Shortcut")
                        .font(MuesliTheme.body())
                        .foregroundStyle(isRecordingHotkey ? MuesliTheme.accent : MuesliTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(isRecordingHotkey ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(isRecordingHotkey ? MuesliTheme.accent.opacity(0.3) : MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }

            Text("Supported: Left Cmd, Right Cmd, Fn, Ctrl, Option, Shift")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onDisappear { stopRecordingHotkey() }
    }

    private func startRecordingHotkey() {
        isRecordingHotkey = true
        hotkeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let keyCode = event.keyCode
            if let label = HotkeyConfig.label(for: keyCode) {
                selectedHotkey = HotkeyConfig(keyCode: keyCode, label: label)
                stopRecordingHotkey()
            }
            return event
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        if let monitor = hotkeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyEventMonitor = nil
        }
    }

    // MARK: - Dictation Test

    private var dictationTestStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text(selectedUseCase.includesVoiceNotes && !selectedUseCase.includesDictation ? "Test Voice Note" : "Test Dictation")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(dictationTestSubtitle)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)

                if isSelectedModelReadyForDictationTest {
                    Text("Try saying: \"testing this one out\"")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.top, 2)
                }
            }

            if !isSelectedModelReadyForDictationTest {
                VStack(spacing: MuesliTheme.spacing8) {
                    if isModelPreparingAfterDownload {
                        IndeterminatePreparationBar()
                            .frame(width: 260, height: 7)
                        Text(modelDownloadStatus ?? "Preparing \(selectedBackend.label)...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                        Text("This usually takes 20-60 seconds the first time.")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                        RotatingPreparationHint(messages: modelPreparationHints)
                            .padding(.top, 2)
                    } else if let modelDownloadProgress {
                        ProgressView(value: modelDownloadProgress, total: 1.0)
                            .frame(width: 260)
                        Text(modelDownloadStatus ?? "\(Int((modelDownloadProgress * 100).rounded()))% complete")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    } else {
                        ProgressView()
                            .controlSize(.regular)
                        Text(modelDownloadStatus ?? "Preparing \(selectedBackend.label)...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    Text("The dictation test is disabled until download and warmup complete.")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .multilineTextAlignment(.center)

                    if let modelDownloadError {
                        Text(modelDownloadError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)

                        Button("Retry Download") {
                            self.modelDownloadError = nil
                            self.modelDownloadSnapshot = nil
                            ensureModelDownloadStarted()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                    }
                }
            } else {
                VStack(spacing: MuesliTheme.spacing16) {
                    Text(dictationTestResult ?? "Your transcription will appear here...")
                        .font(dictationTestResult != nil ? .system(size: 14, design: .monospaced) : .system(size: 13, design: .rounded))
                        .foregroundStyle(dictationTestResult != nil ? MuesliTheme.textPrimary : MuesliTheme.textTertiary)
                        .italic(dictationTestResult == nil)
                        .frame(maxWidth: 400, minHeight: 60, alignment: .topLeading)
                        .padding(MuesliTheme.spacing16)
                        .background(MuesliTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                                .strokeBorder(dictationTestResult != nil ? MuesliTheme.success.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: 1)
                        )

                    if isDictationTesting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Listening... release \(selectedHotkey.label) when done")
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textSecondary)
                        }
                    } else if dictationTestResult == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14))
                            Text("Hold \(selectedHotkey.label) to start")
                                .font(MuesliTheme.body())
                        }
                        .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    if let dictationTestError {
                        Text(dictationTestError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }

                    if dictationTestResult != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MuesliTheme.success)
                            Text("Dictation is working!")
                                .font(MuesliTheme.body())
                                .foregroundStyle(MuesliTheme.success)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            ensureModelDownloadStarted()
            controller.dictationTestBackend = selectedBackend
            controller.dictationTestCohereLanguage = selectedCohereLanguage
            controller.dictationTestRecordingStarted = {
                withAnimation { isDictationTesting = true }
                dictationTestError = nil
            }
            controller.dictationTestRecordingStopped = {
                withAnimation { isDictationTesting = false }
            }
            controller.dictationTestCallback = { text in
                if text.isEmpty {
                    dictationTestError = "No speech detected. Try again."
                } else {
                    withAnimation { dictationTestResult = text }
                    advanceAfterSuccessfulDictationTest(text: text)
                }
                isDictationTesting = false
            }
            controller.dictationTestFailureCallback = { message in
                dictationTestError = message
                isDictationTesting = false
            }
            startDictationTestMonitorIfReady()
        }
        .onDisappear {
            // Cancel any in-flight recording before clearing callbacks to prevent
            // the transcription Task from falling through to the production paste path
            controller.cancelTestDictation()
            controller.clearDictationTestLifecycle()
            // Stop the test monitor while moving through onboarding, but leave the
            // production monitor running when finishing from the dictation test.
            if !hasFinishedOnboarding {
                controller.stopHotkeyMonitor()
            }
            isDictationTestMonitorActive = false
        }
    }

    // MARK: - Meeting Transcription

    private var meetingTranscriptionStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            VStack(spacing: MuesliTheme.spacing8) {
                Text("Choose your meeting model")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("Choose where meeting audio becomes text. On the next screen, separately choose how that transcript becomes notes and action items.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 590)
            }
            .padding(.top, MuesliTheme.spacing24)

            Picker("Meeting transcription runs", selection: Binding(
                get: { usesOnlineMeetingSetup },
                set: { online in
                    resetMeetingModelDownloadForBackendChange()
                    controller.updateConfig { $0.useOpenRouterForMeetings = online }
                }
            )) {
                Text("On this Mac").tag(false)
                Text("Online · OpenRouter").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(appState.config.offlineInference)
            .padding(.horizontal, MuesliTheme.spacing32)

            Label(usesOnlineMeetingSetup ? "No speech-model download needed. Internet access and provider credits are required."
                  : "Using the same model for dictation and meetings saves disk space.", systemImage: usesOnlineMeetingSetup ? "network" : "internaldrive")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 7)
                .background(MuesliTheme.accent.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

            ScrollView {
                VStack(spacing: MuesliTheme.spacing8) {
                    if usesOnlineMeetingSetup {
                        OnlineDictationSetupView(controller: controller, appState: appState, forMeetings: true)
                    } else {
                    ForEach(onboardingMeetingModels, id: \.model) { option in
                        meetingModelCard(option)
                    }

                    if let status = meetingModelDownloadStatus {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(status)
                                    .font(MuesliTheme.caption())
                                    .foregroundStyle(meetingModelDownloadError == nil ? MuesliTheme.textSecondary : MuesliTheme.recording)
                                Spacer()
                                if let progress = meetingModelDownloadProgress {
                                    Text("\(Int(progress * 100))%")
                                        .font(MuesliTheme.caption())
                                        .foregroundStyle(MuesliTheme.textTertiary)
                                }
                            }
                            if let progress = meetingModelDownloadProgress {
                                ProgressView(value: min(max(progress, 0), 1))
                                    .tint(MuesliTheme.accent)
                            }
                        }
                        .padding(MuesliTheme.spacing12)
                        .background(MuesliTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    }
                }
                .padding(.horizontal, MuesliTheme.spacing32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func meetingModelCard(_ option: BackendOption) -> some View {
        let isSelected = selectedMeetingBackend == option
        let sharedWithDictation = selectedUseCase.includesPushToTalk && option == selectedBackend
        return Button {
            selectedMeetingBackend = option
        } label: {
            HStack(spacing: MuesliTheme.spacing12) {
                Circle()
                    .fill(isSelected ? MuesliTheme.accent : Color.clear)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.textTertiary, lineWidth: 1.5)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                        if sharedWithDictation {
                            Text("Same as dictation")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MuesliTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MuesliTheme.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(onboardingDescription(for: option))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if option.isDownloaded {
                    Label("On Mac", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                }
            }
            .padding(MuesliTheme.spacing12)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label), \(option.sizeLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Meeting Summaries

    private var meetingSummaryStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text("Choose how meeting notes are made")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("First, your meeting model creates a transcript. Then this optional service reads that text and turns it into a summary and action items.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                providerTab("ChatGPT", selected: summaryBackend == .chatGPT) {
                    summaryBackend = .chatGPT
                    apiKey = ""
                }
                providerTab("OpenAI", selected: summaryBackend == .openAI) {
                    summaryBackend = .openAI
                    apiKey = ""
                }
                providerTab("OpenRouter", selected: summaryBackend == .openRouter) {
                    summaryBackend = .openRouter
                    apiKey = ""
                }
                providerTab("Ollama", selected: summaryBackend == .ollama) {
                    summaryBackend = .ollama
                    apiKey = ""
                }
            }
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(width: 320)

            if summaryBackend == .chatGPT {
                Text("Uses your ChatGPT Plus or Pro subscription. The transcript text—not the meeting audio—is sent to ChatGPT.")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)

                if appState.isChatGPTAuthenticated || chatGPTSignInDone {
                    HStack(spacing: 6) {
                        OpenAILogoShape()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                        Text("Signed in with ChatGPT")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(MuesliTheme.success)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                } else if isSigningInChatGPT {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Signing in...")
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                } else {
                    Button {
                        isSigningInChatGPT = true
                        chatGPTSignInError = nil
                        Task {
                            let error = await controller.signInWithChatGPT()
                            isSigningInChatGPT = false
                            chatGPTSignInDone = ChatGPTAuthManager.shared.isAuthenticated
                            chatGPTSignInError = error
                        }
                    } label: {
                        HStack(spacing: 6) {
                            OpenAILogoShape()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                            Text("Sign in with ChatGPT")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)

                    if let chatGPTSignInError {
                        Text(chatGPTSignInError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            } else if summaryBackend == .ollama {
                Text("Keep summary generation on your device with Ollama. Install Ollama separately and pull a text model before creating a summary.")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Text("Ollama is served by default at http://localhost:11434")
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(MuesliTheme.success)
                            .frame(width: 6, height: 6)
                        Text("No authentication required")
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.success)
                    }
                }
            } else if summaryBackend == .openRouter {
                Text("The transcript text—not the meeting audio—is sent through OpenRouter to the model you choose.")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)

                if appState.isOpenRouterAuthenticated || openRouterSignInDone {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .font(.system(size: 13, weight: .semibold))
                        Text("OpenRouter connected")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(MuesliTheme.success)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                } else if isSigningInOpenRouter {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                } else {
                    Button {
                        isSigningInOpenRouter = true
                        openRouterSignInError = nil
                        apiKey = ""
                        isEnteringOpenRouterAPIKey = false
                        Task {
                            let error = await controller.signInWithOpenRouter()
                            isSigningInOpenRouter = false
                            openRouterSignInDone = OpenRouterAuthManager.shared.isAuthenticated
                            openRouterSignInError = error
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "network")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Connect OpenRouter")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)

                    Button(isEnteringOpenRouterAPIKey ? "Cancel manual key" : "Enter API key manually") {
                        isEnteringOpenRouterAPIKey.toggle()
                        apiKey = ""
                        openRouterSignInError = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))

                    if isEnteringOpenRouterAPIKey {
                        PastableSecureField(
                            text: apiKey,
                            placeholder: "sk-or-...",
                            onChange: { apiKey = $0 }
                        )
                        .frame(width: 320, height: 28)
                    }

                    if let openRouterSignInError {
                        Text(openRouterSignInError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Text("API Key")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)

                    PastableSecureField(
                        text: apiKey,
                        placeholder: "sk-...",
                        onChange: { apiKey = $0 }
                    )
                    .frame(width: 320, height: 28)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(apiKey.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                            .frame(width: 6, height: 6)
                        Text(apiKey.isEmpty ? "No API key" : "Key entered")
                            .font(.system(size: 11))
                            .foregroundStyle(apiKey.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func providerTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .frame(width: 80)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(selected ? MuesliTheme.surfacePrimary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quill

    private var quillStep: some View {
        ScrollView {
        VStack(spacing: MuesliTheme.spacing16) {
            VStack(spacing: MuesliTheme.spacing8) {
                Text("Would you like voice-powered editing?")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text("Quill is optional. Highlight text, hold \(appState.config.quilHotkey.label), and say something like “make this friendlier.”")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
            .padding(.top, MuesliTheme.spacing24)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: MuesliTheme.spacing8), GridItem(.flexible(), spacing: MuesliTheme.spacing8)],
                spacing: MuesliTheme.spacing8
            ) {
                quillChoiceCard(
                    icon: "pause.circle",
                    title: "Not now",
                    subtitle: "Keep Quill off. You can enable it later.",
                    selected: !quillEnabled
                ) {
                    quillEnabled = false
                }
                quillChoiceCard(
                    icon: "laptopcomputer",
                    title: "Private on-device",
                    subtitle: "Download Qwen 3.5 0.8B · about 533 MB",
                    selected: quillEnabled && quillBackend.isOnDevice
                ) {
                    quillEnabled = true
                    quillBackend = .local
                }
                quillChoiceCard(
                    icon: "person.crop.circle",
                    title: "Use ChatGPT",
                    subtitle: "Uses your signed-in ChatGPT account.",
                    selected: quillEnabled && quillBackend == .hosted(.chatGPT)
                ) {
                    quillEnabled = true
                    quillBackend = .hosted(.chatGPT)
                }
                quillChoiceCard(
                    icon: "network",
                    title: "Use OpenRouter",
                    subtitle: "Connect an account or enter an API key.",
                    selected: quillEnabled && quillBackend == .hosted(.openRouter)
                ) {
                    quillEnabled = true
                    quillBackend = .hosted(.openRouter)
                }
            }
            .frame(maxWidth: 620)

            quillSetupStatus
                .frame(maxWidth: 620)

            if quillEnabled && quillBackend == .hosted(.openRouter) && hasOpenRouterCredentialForSetup {
                OpenRouterTextModelSetupView(controller: controller, appState: appState, modelID: Binding(
                    get: { OnboardingQuillModelSelection.openRouterModel(in: appState.config) },
                    set: { model in
                        controller.updateConfig {
                            $0.quilBackend = TranscriptCleanupBackendOption.hosted(.openRouter).backend
                            $0.quilModel = model
                        }
                    }
                ))
                .frame(maxWidth: 620)
            }

            Label(
                "Quill changes selected text. With no selection, it generates new text at the cursor.",
                systemImage: "info.circle"
            )
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textSecondary)
        }
        .padding(.horizontal, MuesliTheme.spacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func quillChoiceCard(
        icon: String,
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? .white : MuesliTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MuesliTheme.headline())
                    Text(subtitle)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(selected ? Color.white.opacity(0.78) : MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(selected ? .white : MuesliTheme.textPrimary)
            .padding(MuesliTheme.spacing12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(selected ? MuesliTheme.accent : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(selected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var quillSetupStatus: some View {
        if !quillEnabled {
            onboardingStatusBox(
                icon: "checkmark.circle.fill",
                title: "Quill will stay off",
                detail: "Nothing else to set up.",
                color: MuesliTheme.success
            )
        } else if quillBackend.isOnDevice {
            if PostProcessorOption.defaultQuilOption.isDownloaded {
                onboardingStatusBox(
                    icon: "checkmark.circle.fill",
                    title: "Local Quill model is ready",
                    detail: "Selected text and instructions stay on this Mac.",
                    color: MuesliTheme.success
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        quillModelDownloadStatus ?? "The local Quill model needs to be downloaded.",
                        systemImage: isDownloadingQuillModel ? "arrow.down.circle" : "internaldrive"
                    )
                    .font(MuesliTheme.caption())
                    .foregroundStyle(quillModelDownloadError == nil ? MuesliTheme.textSecondary : MuesliTheme.recording)
                    if let progress = quillModelDownloadProgress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(MuesliTheme.accent)
                    }
                }
                .padding(MuesliTheme.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MuesliTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
        } else if quillBackend == .hosted(.chatGPT) {
            if appState.isChatGPTAuthenticated || chatGPTSignInDone {
                onboardingStatusBox(
                    icon: "checkmark.circle.fill",
                    title: "ChatGPT is connected",
                    detail: "Quill instructions and selected text are sent to ChatGPT.",
                    color: MuesliTheme.success
                )
            } else if isSigningInChatGPT {
                onboardingStatusBox(
                    icon: "hourglass",
                    title: "Waiting for ChatGPT sign-in",
                    detail: "Finish signing in in your browser.",
                    color: MuesliTheme.accent
                )
            } else {
                VStack(spacing: 6) {
                    onboardingActionButton("Sign in with ChatGPT", systemImage: "person.crop.circle") {
                        isSigningInChatGPT = true
                        chatGPTSignInError = nil
                        Task {
                            let error = await controller.signInWithChatGPT(selectMeetingSummaryBackend: false)
                            isSigningInChatGPT = false
                            chatGPTSignInDone = ChatGPTAuthManager.shared.isAuthenticated
                            chatGPTSignInError = error
                        }
                    }
                    if let chatGPTSignInError {
                        Text(chatGPTSignInError)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.recording)
                    }
                }
            }
        } else if quillBackend == .hosted(.openRouter) {
            if hasOpenRouterCredentialForSetup {
                onboardingStatusBox(
                    icon: "checkmark.circle.fill",
                    title: "OpenRouter is connected",
                    detail: "Quill instructions and selected text are sent to your chosen OpenRouter model.",
                    color: MuesliTheme.success
                )
            } else if isSigningInOpenRouter {
                onboardingStatusBox(
                    icon: "hourglass",
                    title: "Waiting for OpenRouter",
                    detail: "Approve access in your browser.",
                    color: MuesliTheme.accent
                )
            } else {
                VStack(spacing: MuesliTheme.spacing8) {
                    onboardingActionButton("Connect OpenRouter", systemImage: "network") {
                        isSigningInOpenRouter = true
                        openRouterSignInError = nil
                        quillAPIKey = ""
                        Task {
                            let error = await controller.signInWithOpenRouter(selectMeetingSummaryBackend: false)
                            isSigningInOpenRouter = false
                            openRouterSignInDone = OpenRouterAuthManager.shared.isAuthenticated
                            openRouterSignInError = error
                        }
                    }
                    Text("or enter an API key")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                    PastableSecureField(
                        text: quillAPIKey,
                        placeholder: "sk-or-...",
                        onChange: { quillAPIKey = $0 }
                    )
                    .frame(width: 320, height: 28)
                    if let openRouterSignInError {
                        Text(openRouterSignInError)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.recording)
                    }
                }
            }
        }
    }

    private func onboardingStatusBox(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(detail)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            Spacer()
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func onboardingActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(MuesliTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startMeetingModelDownload() {
        guard selectedMeetingBackend.isCompatible(), meetingModelDownloadTask == nil else { return }
        if selectedMeetingBackend == selectedBackend, modelReadyBackend == selectedBackend {
            meetingModelReadyBackend = selectedMeetingBackend
            goToNextStep()
            return
        }

        let backend = selectedMeetingBackend
        meetingModelDownloadProgress = backend.isDownloaded ? nil : 0.02
        meetingModelDownloadStatus = backend.isDownloaded
            ? "Preparing \(backend.label) for meetings…"
            : "Downloading \(backend.label)…"
        meetingModelDownloadError = nil

        meetingModelDownloadTask = Task {
            do {
                try await controller.downloadModelForOnboarding(
                    backend,
                    onboardingUseCase: .meetings
                ) { progress, status in
                    Task { @MainActor in
                        guard selectedMeetingBackend == backend else { return }
                        meetingModelDownloadProgress = min(max(progress, 0), 1)
                        meetingModelDownloadStatus = status ?? "Preparing \(backend.label)…"
                        meetingModelDownloadError = nil
                    }
                } progressSnapshot: { snapshot in
                    Task { @MainActor in
                        guard selectedMeetingBackend == backend else { return }
                        meetingModelDownloadProgress = snapshot.fractionCompleted
                        meetingModelDownloadStatus = snapshot.message
                            ?? (snapshot.phase == .preparing ? "Preparing meeting model…" : "Downloading meeting model…")
                    }
                }
                await MainActor.run {
                    guard selectedMeetingBackend == backend else { return }
                    meetingModelReadyBackend = backend
                    meetingModelDownloadProgress = 1
                    meetingModelDownloadStatus = "\(backend.label) is ready for meetings"
                    meetingModelDownloadError = nil
                    meetingModelDownloadTask = nil
                    saveProgress(atStep: currentStep)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard selectedMeetingBackend == backend else { return }
                    meetingModelDownloadTask = nil
                    meetingModelDownloadStatus = "Download paused"
                }
            } catch {
                await MainActor.run {
                    guard selectedMeetingBackend == backend else { return }
                    meetingModelDownloadTask = nil
                    meetingModelDownloadProgress = nil
                    meetingModelDownloadError = error.localizedDescription
                    meetingModelDownloadStatus = "Meeting model setup failed. Check your connection and try again."
                }
            }
        }
    }

    private func resetMeetingModelDownloadForBackendChange() {
        meetingModelDownloadTask?.cancel()
        meetingModelDownloadTask = nil
        if let meetingModelReadyBackend, meetingModelReadyBackend != selectedMeetingBackend {
            self.meetingModelReadyBackend = nil
        }
        meetingModelDownloadProgress = nil
        meetingModelDownloadStatus = nil
        meetingModelDownloadError = nil
    }

    private func startQuillModelDownload() {
        let option = PostProcessorOption.defaultQuilOption
        guard !option.isDownloaded, quillModelDownloadTask == nil, !appState.config.offlineInference else { return }
        let generation = UUID()
        quillModelDownloadGeneration = generation

        isDownloadingQuillModel = true
        quillModelDownloadProgress = 0.02
        quillModelDownloadStatus = "Downloading the local language model…"
        quillModelDownloadError = nil

        quillModelDownloadTask = Task {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: option.cacheDirectory, withIntermediateDirectories: true)
                let manifest = ModelDownloadManifest(
                    id: option.id,
                    version: "main",
                    files: [ModelDownloadFile(relativePath: option.filename, remoteURL: option.downloadURL)],
                    maximumConcurrency: 1
                )
                try await ModelDownloadCoordinator.shared.download(manifest, to: option.cacheDirectory) { snapshot in
                    Task { @MainActor in
                        guard quillModelDownloadGeneration == generation else { return }
                        quillModelDownloadProgress = snapshot.fractionCompleted
                        quillModelDownloadStatus = snapshot.message ?? "Downloading the local language model…"
                    }
                }
                try Task.checkCancellation()

                let header = try Data(contentsOf: option.modelURL, options: [.mappedIfSafe]).prefix(4)
                guard header.elementsEqual(Data("GGUF".utf8)) else {
                    try? fileManager.removeItem(at: option.modelURL)
                    throw NSError(
                        domain: "MuesliOnboardingQuillDownload",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The downloaded language model was incomplete. Please try again."]
                    )
                }

                await MainActor.run {
                    guard quillModelDownloadGeneration == generation else { return }
                    quillModelDownloadGeneration = UUID()
                    isDownloadingQuillModel = false
                    quillModelDownloadTask = nil
                    quillModelDownloadProgress = 1
                    quillModelDownloadStatus = "Local language model is ready"
                    quillModelDownloadError = nil
                    saveProgress(atStep: currentStep)
                    if hasFinishedOnboarding && appState.config.pendingLocalCleanupSetup {
                        controller.preloadExperimentalTranscriptionFeatures()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard quillModelDownloadGeneration == generation else { return }
                    quillModelDownloadGeneration = UUID()
                    isDownloadingQuillModel = false
                    quillModelDownloadTask = nil
                    quillModelDownloadStatus = "Download paused. Select Download to resume."
                }
            } catch {
                await MainActor.run {
                    guard quillModelDownloadGeneration == generation else { return }
                    quillModelDownloadGeneration = UUID()
                    isDownloadingQuillModel = false
                    quillModelDownloadTask = nil
                    quillModelDownloadProgress = nil
                    quillModelDownloadStatus = "Language model download failed. Check your connection and try again."
                    quillModelDownloadError = error.localizedDescription
                }
            }
        }
    }

    private func cancelQuillModelDownload() {
        guard quillModelDownloadTask != nil else { return }
        quillModelDownloadGeneration = UUID()
        quillModelDownloadTask?.cancel()
        quillModelDownloadTask = nil
        isDownloadingQuillModel = false
        quillModelDownloadProgress = nil
        quillModelDownloadStatus = nil
        quillModelDownloadError = nil
        Task {
            await ModelDownloadCoordinator.shared.cancel(modelID: PostProcessorOption.defaultQuilOption.id)
        }
    }

    private func startDictationTestMonitorIfReady() {
        let action = OnboardingFlow.dictationTestMonitorAction(
            currentStep: currentStep,
            dictationTestStep: Self.dictationTestStep,
            modelReady: isSelectedModelReadyForDictationTest,
            monitorActive: isDictationTestMonitorActive,
            dictationTesting: isDictationTesting
        )

        switch action {
        case .none:
            return
        case .stop(let cancelTestDictation):
            if cancelTestDictation {
                controller.cancelTestDictation()
                isDictationTesting = false
            }
            controller.stopHotkeyMonitor()
            isDictationTestMonitorActive = false
            return
        case .start:
            dictationTestError = nil
            controller.dictationTestBackend = selectedBackend
            controller.dictationTestCohereLanguage = selectedCohereLanguage
            controller.startHotkeyMonitor(keyCode: selectedHotkey.keyCode)
            isDictationTestMonitorActive = true
        }
    }

    private func advanceAfterSuccessfulDictationTest(text: String) {
        guard selectedUseCase.includesMeetings else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard currentStep == Self.dictationTestStep, dictationTestResult == text else { return }
            goToNextStep()
        }
    }

    private var needsRomanizationModel: Bool {
        selectedBackend.backend == "bodhan" && controller.config.romanizeHindi
    }

    private var isRomanizationModelReady: Bool {
        !needsRomanizationModel || PostProcessorOption.qwen35_0_8b.isDownloaded
    }

    private func ensureModelDownloadStarted() {
        if let reason = selectedBackend.incompatibilityReason() {
            modelDownloadError = reason
            return
        }
        if modelReadyBackend == selectedBackend && isRomanizationModelReady {
            isModelStillDownloading = false
            modelDownloadProgress = 1.0
            isModelPreparingAfterDownload = false
            modelDownloadStatus = "\(selectedBackend.label) ready"
            modelDownloadError = nil
            publishModelPreparationStatus(
                title: "\(selectedBackend.label) ready",
                detail: "Ready for transcription",
                progress: 1.0,
                isPreparing: false,
                isComplete: true
            )
            return
        }

        if modelDownloadTask != nil {
            guard modelDownloadBackend != selectedBackend else {
                isModelStillDownloading = true
                return
            }
            cancelModelDownload(for: modelDownloadBackend)
            modelDownloadGeneration = UUID()
            modelDownloadTask?.cancel()
            modelDownloadTask = nil
            modelDownloadBackend = nil
        }

        let backend = selectedBackend
        let downloadRomanizationModel = needsRomanizationModel
        let useCase = selectedUseCase
        let generation = UUID()
        let alreadyDownloaded = backend.isDownloaded
        modelDownloadGeneration = generation
        modelDownloadBackend = backend
        isModelStillDownloading = true
        modelDownloadProgress = alreadyDownloaded ? nil : (modelDownloadProgress ?? 0.02)
        isModelPreparingAfterDownload = alreadyDownloaded
        modelDownloadStatus = alreadyDownloaded
            ? "Warming up \(backend.label)..."
            : (modelDownloadStatus ?? initialDownloadStatus(for: backend))
        modelDownloadError = nil
        modelDownloadSnapshot = nil
        publishModelPreparationStatus(
            title: "Preparing \(backend.label)",
            detail: modelDownloadStatus,
            progress: modelDownloadProgress,
            isPreparing: isModelPreparingAfterDownload,
            isComplete: false
        )

        modelDownloadTask = Task {
            defer {
                Task { @MainActor in
                    if modelDownloadGeneration == generation, modelDownloadBackend == backend {
                        modelDownloadTask = nil
                        modelDownloadBackend = nil
                    }
                }
            }
            do {
                if downloadRomanizationModel {
                    let option = PostProcessorOption.qwen35_0_8b
                    if !option.isDownloaded {
                        modelDownloadStatus = "Downloading the local Hindi romanization model (about 510 MB)…"
                        try FileManager.default.createDirectory(at: option.cacheDirectory, withIntermediateDirectories: true)
                        let manifest = ModelDownloadManifest(
                            id: option.id,
                            version: "main",
                            files: [ModelDownloadFile(relativePath: option.filename, remoteURL: option.downloadURL)],
                            maximumConcurrency: 1
                        )
                        try await ModelDownloadCoordinator.shared.download(manifest, to: option.cacheDirectory) { snapshot in
                            Task { @MainActor in
                                guard modelDownloadGeneration == generation, selectedBackend == backend else { return }
                                modelDownloadProgress = snapshot.fractionCompleted
                                modelDownloadStatus = "Downloading local romanization model…"
                            }
                        }
                    }
                    try Task.checkCancellation()
                    let header = try Data(contentsOf: option.modelURL, options: [.mappedIfSafe]).prefix(4)
                    guard header.elementsEqual(Data("GGUF".utf8)) else {
                        throw NSError(domain: "MuesliRomanizationSetup", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "The romanization model is incomplete. Download it again in Models."])
                    }
                }
                try await controller.downloadModelForOnboarding(backend, onboardingUseCase: useCase) { progress, status in
                    Task { @MainActor in
                        guard modelDownloadGeneration == generation,
                              modelDownloadBackend == backend,
                              selectedBackend == backend else { return }
                        applyModelPreparationProgress(progress, status: status, backend: backend, generation: generation)
                    }
                } progressSnapshot: { snapshot in
                    Task { @MainActor in
                        guard modelDownloadGeneration == generation,
                              modelDownloadBackend == backend,
                              selectedBackend == backend else { return }
                        applyModelDownloadSnapshot(snapshot, backend: backend, generation: generation)
                    }
                }
                await MainActor.run {
                    guard modelDownloadGeneration == generation,
                          modelDownloadBackend == backend,
                          selectedBackend == backend else { return }
                    modelReadyBackend = backend
                    modelDownloadProgress = 1.0
                    modelDownloadSnapshot = nil
                    isModelPreparingAfterDownload = false
                    modelDownloadStatus = "\(backend.label) ready"
                    modelDownloadError = nil
                    withAnimation { isModelStillDownloading = false }
                    publishModelPreparationStatus(
                        title: "\(backend.label) ready",
                        detail: "Ready for transcription",
                        progress: 1.0,
                        isPreparing: false,
                        isComplete: true
                    )
                    showModelReadyIndicator(for: backend)
                    controller.notifyOnboardingModelReady()
                    saveProgress(atStep: currentStep)
                }
            } catch is CancellationError {
                // Backend changes cancel the old task; the new selection owns the download UI.
            } catch {
                await MainActor.run {
                    guard modelDownloadGeneration == generation,
                          modelDownloadBackend == backend,
                          selectedBackend == backend else { return }
                    modelDownloadError = modelPreparationFailureMessage(for: backend)
                    modelDownloadStatus = backend.isDownloaded ? "Model setup paused" : "Download paused"
                    modelDownloadProgress = nil
                    if let snapshot = modelDownloadSnapshot {
                        modelDownloadSnapshot = snapshot.replacing(
                            phase: .failed,
                            message: modelDownloadError
                        )
                    }
                    isModelPreparingAfterDownload = false
                    isModelStillDownloading = false
                    publishModelPreparationStatus(
                        title: backend.isDownloaded ? "Model setup paused" : "Download paused",
                        detail: modelDownloadError,
                        progress: nil,
                        isPreparing: false,
                        isComplete: false
                    )
                }
                fputs("[muesli-native] onboarding model download failed: \(error)\n", stderr)
            }
        }
    }

    private func applyModelDownloadSnapshot(
        _ snapshot: ModelDownloadProgress,
        backend: BackendOption,
        generation: UUID
    ) {
        guard modelDownloadGeneration == generation,
              modelDownloadBackend == backend,
              selectedBackend == backend else { return }
        modelDownloadSnapshot = snapshot
        modelDownloadError = nil

        switch snapshot.phase {
        case .downloading:
            isModelStillDownloading = true
            isModelPreparingAfterDownload = false
            if let fraction = snapshot.fractionCompleted {
                modelDownloadProgress = max(modelDownloadProgress ?? 0.02, fraction)
            }
            modelDownloadStatus = modelDownloadSnapshotDetail(snapshot)
        case .preparing:
            isModelStillDownloading = true
            isModelPreparingAfterDownload = true
            modelDownloadProgress = nil
            modelDownloadStatus = snapshot.message ?? "Preparing \(backend.label)..."
        case .ready:
            modelDownloadStatus = snapshot.message ?? "\(backend.label) ready"
        case .paused:
            isModelStillDownloading = false
            isModelPreparingAfterDownload = false
            modelDownloadStatus = snapshot.message ?? "Download paused"
        case .failed:
            isModelStillDownloading = false
            isModelPreparingAfterDownload = false
            modelDownloadError = snapshot.message
            modelDownloadStatus = snapshot.message ?? "Download failed"
        }

        publishModelPreparationStatus(
            title: modelDownloadIndicatorTitle,
            detail: modelDownloadStatus,
            progress: modelDownloadProgress,
            isPreparing: isModelPreparingAfterDownload,
            isComplete: snapshot.phase == .ready
        )
    }

    private func applyModelPreparationProgress(
        _ progress: Double,
        status: String?,
        backend: BackendOption,
        generation: UUID
    ) {
        guard modelDownloadGeneration == generation,
              modelDownloadBackend == backend,
              selectedBackend == backend else { return }
        let detail = status ?? "Preparing \(backend.label)..."
        let lowercasedDetail = detail.lowercased()
        let isPreparing = lowercasedDetail.contains("compiling")
            || lowercasedDetail.contains("warming")
            || lowercasedDetail.contains("readying")

        modelDownloadError = nil
        isModelStillDownloading = true

        if isPreparing {
            isModelPreparingAfterDownload = true
            modelDownloadStatus = "Optimizing \(backend.label) for this Mac..."
            publishModelPreparationStatus(
                title: "Preparing \(backend.label)",
                detail: modelDownloadStatus,
                progress: nil,
                isPreparing: true,
                isComplete: false
            )
            saveProgress(atStep: currentStep)
            return
        }

        isModelPreparingAfterDownload = false
        let clampedProgress = min(max(progress, 0), 1)
        let currentProgress = modelDownloadProgress ?? 0
        let isZeroReset = clampedProgress <= 0.001 && currentProgress > 0.03

        guard !isZeroReset else { return }
        modelDownloadProgress = max(currentProgress, max(clampedProgress, 0.02))
        modelDownloadStatus = detail
        publishModelPreparationStatus(
            title: "Preparing \(backend.label)",
            detail: detail,
            progress: modelDownloadProgress,
            isPreparing: false,
            isComplete: false
        )
        saveProgress(atStep: currentStep)
    }

    private func resetModelDownloadForBackendChange() {
        cancelModelDownload(for: modelDownloadBackend)
        modelDownloadGeneration = UUID()
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        modelReadyIndicatorTask?.cancel()
        modelReadyIndicatorTask = nil
        modelReadyBackend = nil
        modelReadyIndicatorBackend = nil
        modelDownloadBackend = nil
        modelDownloadProgress = nil
        modelDownloadSnapshot = nil
        isModelPreparingAfterDownload = false
        modelDownloadStatus = nil
        modelDownloadError = nil
        isModelStillDownloading = false
    }

    private func cancelModelDownload(for backend: BackendOption?) {
        guard let backend else { return }
        Task {
            await ManagedASRModelDownloader.cancel(modelID: backend.model)
        }
    }

    private func initialDownloadStatus(for backend: BackendOption) -> String {
        let size = backend.sizeLabel
            .replacingOccurrences(of: "~", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !size.isEmpty {
            return "0 MB of \(size)"
        }
        return "Starting \(backend.label) download..."
    }

    private func modelPreparationFailureMessage(for backend: BackendOption) -> String {
        backend.isDownloaded
            ? "Model setup failed. Restart Muesli+ or retry from Models."
            : "Download failed. Check your connection and retry."
    }

    private func publishModelPreparationStatus(
        title: String,
        detail: String?,
        progress: Double?,
        isPreparing: Bool,
        isComplete: Bool
    ) {
        appState.modelPreparationTitle = title
        appState.modelPreparationDetail = detail
        appState.modelPreparationProgress = progress.map { min(max($0, 0), 1) }
        appState.isModelPreparingAfterDownload = isPreparing
        appState.modelPreparationIsComplete = isComplete
        if isComplete {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard appState.modelPreparationTitle == title,
                      appState.modelPreparationIsComplete else { return }
                appState.modelPreparationTitle = nil
                appState.modelPreparationDetail = nil
                appState.modelPreparationProgress = nil
                appState.isModelPreparingAfterDownload = false
                appState.modelPreparationIsComplete = false
            }
        } else if !isPreparing && progress == nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                guard appState.modelPreparationTitle == title,
                      appState.modelPreparationProgress == nil,
                      !appState.isModelPreparingAfterDownload,
                      !appState.modelPreparationIsComplete else { return }
                appState.modelPreparationTitle = nil
                appState.modelPreparationDetail = nil
            }
        }
    }

    private func showModelReadyIndicator(for backend: BackendOption) {
        modelReadyIndicatorTask?.cancel()
        modelReadyIndicatorBackend = backend
        modelReadyIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard modelReadyIndicatorBackend == backend else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                modelReadyIndicatorBackend = nil
            }
            modelReadyIndicatorTask = nil
        }
    }

    private var calendarAccessStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()
            Image(nsImage: CalendarIntegration.calendarIcon)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("Bring your meetings into Muesli+")
                .font(MuesliTheme.title1())
                .foregroundStyle(MuesliTheme.textPrimary)
            Text("Allow access to macOS Calendar to see upcoming meetings and get reminders.")
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
            CalendarAccessControl {
                await controller.calendarAccessDidChange()
            }
            Button("Set up calendar accounts…", action: CalendarIntegration.openAccounts)
                .buttonStyle(.link)
            Divider().background(MuesliTheme.surfaceBorder)
            Text("Already use Google or Exchange? Add the account in macOS Internet Accounts and turn on Calendars.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, MuesliTheme.spacing32)
    }

    // MARK: - Review

    private var vocabularyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                Text("Teach Muesli+ your vocabulary").font(MuesliTheme.title1())
                Text("What do you work on? Tell us about your role, tools, and topics. We’ll suggest specialist words for you to review. This step is optional.")
                    .font(MuesliTheme.body()).foregroundStyle(MuesliTheme.textSecondary)
                TextField("For example: I’m a developer working with Swift, Kubernetes, and PostgreSQL.", text: Binding(
                    get: { appState.config.professionDescription },
                    set: { value in
                        vocabularyGeneration = UUID()
                        vocabularyTask?.cancel()
                        vocabularyTask = nil
                        vocabularySuggestions = []
                        selectedVocabulary = []
                        vocabularyMessage = nil
                        controller.updateConfig { $0.professionDescription = String(value.prefix(2_000)) }
                    }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)
                .accessibilityLabel("Describe your work and vocabulary")
                if !appState.config.offlineInference {
                    Toggle("Use OpenRouter for vocabulary suggestions", isOn: $vocabularyOnline)
                        .disabled(vocabularyTask != nil)
                }
                Text("Nothing is added to the dictionary until you select Save.")
                    .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                if vocabularyOnline && !appState.config.offlineInference {
                    Text("Your work description will be sent to OpenRouter and the selected provider when you choose Suggest words. Do not include confidential details. Provider charges may apply.")
                        .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                    if !appState.isOpenRouterAuthenticated {
                        SecureField("OpenRouter API key", text: $vocabularyAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save API key") {
                            vocabularyMessage = controller.storeManualOpenRouterAPIKey(vocabularyAPIKey, selectMeetingSummaryBackend: false)
                            if vocabularyMessage == nil { vocabularyAPIKey = "" }
                        }
                    }
                    OpenRouterTextModelSetupView(controller: controller, appState: appState, modelID: $vocabularyModel)
                        .disabled(vocabularyTask != nil)
                } else {
                    Text("Suggestions run on this Mac using the downloaded language model. Your description is not sent to a hosted AI provider.")
                        .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                }
                if !(vocabularyOnline && !appState.config.offlineInference) && !PostProcessorOption.defaultQuilOption.isDownloaded {
                    Button(isDownloadingQuillModel ? "Downloading local language model…" : "Download local language model (about 510 MB)") {
                        startQuillModelDownload()
                    }
                    .disabled(isDownloadingQuillModel || appState.config.offlineInference)
                    if let quillModelDownloadError {
                        Text(quillModelDownloadError).foregroundStyle(MuesliTheme.transcribing)
                    }
                } else {
                    Button(vocabularyTask == nil ? "Suggest words" : "Finding useful words…") {
                        generateVocabularySuggestions()
                    }
                    .disabled(vocabularyTask != nil || appState.config.professionDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (vocabularyOnline && !appState.config.offlineInference && (!appState.isOpenRouterAuthenticated || vocabularyModel.isEmpty)))
                }
                if !vocabularySuggestions.isEmpty {
                    Text("Review the spellings and uncheck anything you don’t use.").font(MuesliTheme.headline())
                    ForEach(vocabularySuggestions, id: \.self) { word in
                        Toggle(word, isOn: Binding(
                            get: { selectedVocabulary.contains(word) },
                            set: { enabled in
                                if enabled { selectedVocabulary.insert(word) }
                                else { selectedVocabulary.remove(word) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    Button("Save \(selectedVocabulary.count) words to my dictionary") {
                        let selected = vocabularySuggestions.filter { selectedVocabulary.contains($0) }
                        var added = 0
                        controller.updateConfig { config in
                            for word in selected where !config.customWords.contains(where: { $0.targetWord.lowercased() == word.lowercased() }) {
                                config.customWords.append(CustomWord(word: word, replacement: word))
                                added += 1
                            }
                        }
                        vocabularySuggestions = []
                        selectedVocabulary = []
                        vocabularyMessage = "Saved \(added) words. You can review, edit, or remove them in Dictionary after setup."
                    }
                    .disabled(selectedVocabulary.isEmpty)
                }
                if let vocabularyMessage {
                    Text(vocabularyMessage).font(MuesliTheme.body())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("You can also add names or terms manually in Dictionary at any time.")
                    .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
            }
            .padding(MuesliTheme.spacing32)
        }
        .onDisappear {
            vocabularyGeneration = UUID()
            vocabularyTask?.cancel()
            vocabularyTask = nil
        }
    }

    private func generateVocabularySuggestions() {
        let generation = UUID()
        vocabularyGeneration = generation
        vocabularyMessage = nil
        let description = controller.config.professionDescription
        let existing = controller.config.customWords.flatMap { [$0.word, $0.targetWord] }
        let config = controller.config
        let useOnline = vocabularyOnline && !config.offlineInference
        let model = vocabularyModel
        vocabularyTask = Task { @MainActor in
            defer { if vocabularyGeneration == generation { vocabularyTask = nil } }
            do {
                let words: [String]
                if useOnline {
                    words = try await HostedProfessionVocabulary.suggest(description, excluding: existing, model: model, config: config)
                } else {
                    words = try await controller.transcriptionCoordinator.suggestProfessionVocabulary(description, excluding: existing)
                }
                guard !Task.isCancelled, vocabularyGeneration == generation else { return }
                vocabularySuggestions = words
                selectedVocabulary = Set(words)
                if words.isEmpty { vocabularyMessage = "No new terms found. Try naming a few tools or topics you work with, or continue and add words manually later." }
            } catch is CancellationError {
            } catch {
                guard vocabularyGeneration == generation else { return }
                vocabularyMessage = "Couldn’t generate a usable word list. Try a shorter description, or continue and add words manually in Dictionary."
            }
        }
    }

    private var reviewStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            VStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(MuesliTheme.success)
                Text("You're ready to use Muesli+")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text("Here is what Muesli+ will use. Choose Change if anything does not look right.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, MuesliTheme.spacing20)

            ScrollView {
                VStack(spacing: MuesliTheme.spacing8) {
                    if selectedUseCase.includesPushToTalk {
                        reviewRow(
                            icon: "waveform",
                            title: "Dictation",
                            value: selectedBackend.label,
                            detail: "Hold \(selectedHotkey.label), speak, then release",
                            editStep: OnboardingFlow.Step.model.rawValue
                        )
                    }
                    if selectedUseCase.includesMeetings {
                        reviewRow(
                            icon: "person.2.fill",
                            title: "Meeting transcript",
                            value: usesOnlineMeetingSetup ? appState.config.openRouterMeetingModel : selectedMeetingBackend.label,
                            detail: usesOnlineMeetingSetup ? "Audio is sent through OpenRouter; provider charges may apply" : "Audio is transcribed locally on this Mac",
                            editStep: OnboardingFlow.Step.meetingTranscription.rawValue
                        )
                        reviewRow(
                            icon: "list.bullet.clipboard",
                            title: "Meeting summary",
                            value: summaryBackend.label,
                            detail: meetingSummaryReviewDetail,
                            editStep: OnboardingFlow.Step.meetingSummary.rawValue
                        )
                    }
                    if selectedUseCase.includesDictation {
                        reviewRow(
                            icon: "pencil.and.scribble",
                            title: "Quill",
                            value: quillEnabled ? quillBackend.label : "Off",
                            detail: quillEnabled
                                ? "Hold \(appState.config.quilHotkey.label) to rewrite selected text"
                                : "You can enable voice editing later in Settings",
                            editStep: OnboardingFlow.Step.quill.rawValue
                        )
                    }
                    reviewRow(
                        icon: "paintpalette.fill",
                        title: "Appearance",
                        value: MuesliColorTheme.resolved(for: appState.config.recordingColorHex).label,
                        detail: appState.config.darkMode ? "Dark mode after setup" : "Light mode after setup",
                        editStep: OnboardingFlow.Step.appearance.rawValue
                    )
                    reviewRow(
                        icon: "hand.raised.fill",
                        title: "Privacy permissions",
                        value: requiredPermissionsGranted ? "Ready" : "Needs attention",
                        detail: "Only the permissions required for your selected features",
                        editStep: OnboardingFlow.Step.permissions.rawValue
                    )
                }
                .padding(.horizontal, MuesliTheme.spacing32)
            }

            Text("Nothing here is permanent. Every choice can be changed later in Settings or Models.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .padding(.bottom, MuesliTheme.spacing4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var meetingSummaryReviewDetail: String {
        if summaryBackend == .chatGPT {
            return (appState.isChatGPTAuthenticated || chatGPTSignInDone)
                ? "ChatGPT account connected" : "Not connected yet; summaries can be set up later"
        } else if summaryBackend == .openRouter {
            return (appState.isOpenRouterAuthenticated || openRouterSignInDone || !apiKey.isEmpty)
                ? "OpenRouter connected" : "Not connected yet; summaries can be set up later"
        } else if summaryBackend == .openAI {
            return apiKey.isEmpty ? "No API key entered yet" : "API key entered"
        } else if summaryBackend == .ollama {
            return "Uses Ollama running on this Mac"
        }
        return "Provider selected"
    }

    private func reviewRow(
        icon: String,
        title: String,
        value: String,
        detail: String,
        editStep: Int
    ) -> some View {
        HStack(spacing: MuesliTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                Text(value)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(detail)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            Spacer()
            Button("Change") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentStep = editStep
                }
            }
            .buttonStyle(.link)
            .font(MuesliTheme.caption())
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func finishOnboarding(withKey: Bool) {
        hasFinishedOnboarding = true
        OnboardingProgress.clear()
        let shouldContinueModelPreparation = modelDownloadTask != nil && modelReadyBackend != selectedBackend
        if shouldContinueModelPreparation {
            modelDownloadGeneration = UUID()
            modelDownloadTask?.cancel()
            modelDownloadTask = nil
            modelDownloadBackend = nil
            controller.continueModelPreparationAfterOnboarding(
                selectedBackend,
                onboardingUseCase: selectedUseCase,
                initialProgress: modelDownloadProgress,
                initialStatus: modelDownloadStatus,
                isPreparing: isModelPreparingAfterDownload
            )
        } else if isModelStillDownloading || modelReadyBackend == selectedBackend {
            publishModelPreparationStatus(
                title: modelReadyBackend == selectedBackend ? "\(selectedBackend.label) ready" : "Preparing \(selectedBackend.label)",
                detail: modelReadyBackend == selectedBackend ? "Ready for transcription" : modelDownloadStatus,
                progress: modelReadyBackend == selectedBackend ? 1.0 : modelDownloadProgress,
                isPreparing: isModelPreparingAfterDownload,
                isComplete: modelReadyBackend == selectedBackend
            )
        }
        let dictationBackend = selectedUseCase.includesPushToTalk
            ? selectedBackend : selectedMeetingBackend
        controller.completeOnboarding(
            userName: userName.trimmingCharacters(in: .whitespaces),
            backend: dictationBackend,
            meetingBackend: selectedMeetingBackend,
            cohereLanguage: selectedCohereLanguage,
            hotkey: selectedHotkey,
            onboardingUseCase: selectedUseCase,
            summaryBackend: summaryBackend,
            apiKey: withKey ? apiKey : nil,
            quillEnabled: quillEnabled,
            quillBackend: quillBackend,
            quillAPIKey: withKey ? quillAPIKey : nil,
            cleanupEnabled: cleanupEnabled
        )
    }
}

private struct ModelDownloadProgressShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        guard clampedProgress > 0 else { return path }
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + (360 * clampedProgress)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct IndeterminatePreparationBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let segmentWidth = max(trackWidth * 0.32, 64)
            let travel = max(trackWidth - segmentWidth, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MuesliTheme.surfaceBorder)

                Capsule()
                    .fill(MuesliTheme.textSecondary.opacity(0.9))
                    .frame(width: segmentWidth)
                    .offset(x: isAnimating ? travel : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct RotatingPreparationHint: View {
    let messages: [String]
    @State private var index = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(messages.isEmpty ? "" : messages[index % messages.count])
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(MuesliTheme.textTertiary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .id(index)
            .transition(.opacity)
            .onReceive(timer) { _ in
                guard messages.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    index = (index + 1) % messages.count
                }
            }
            .onChange(of: messages) { _, _ in
                index = 0
            }
    }
}

// MARK: - Text Field

/// NSTextField subclass that handles Cmd+V/C/X/A without needing a standard Edit menu.
class EditableNSTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A focused emoji field that opens the macOS character palette when clicked.
/// Selecting all existing text first makes the next emoji replace the prior choice.
final class EmojiPickerNSTextField: EditableNSTextField {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        currentEditor()?.selectAll(nil)
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

struct OnboardingEmojiField: NSViewRepresentable {
    @Binding var text: String
    let onValidEmoji: (String) -> Void

    func makeNSView(context: Context) -> EmojiPickerNSTextField {
        let field = EmojiPickerNSTextField()
        field.placeholderString = "Choose emoji"
        field.font = .systemFont(ofSize: 18)
        field.alignment = .center
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        field.toolTip = "Click to open the macOS emoji picker"
        return field
    }

    func updateNSView(_ nsView: EmojiPickerNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onValidEmoji: onValidEmoji)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onValidEmoji: (String) -> Void

        init(text: Binding<String>, onValidEmoji: @escaping (String) -> Void) {
            _text = text
            self.onValidEmoji = onValidEmoji
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
            guard let choice = MenuBarIconRenderer.choice(forEmoji: field.stringValue) else { return }
            onValidEmoji(choice)
        }
    }
}

struct OnboardingTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> EditableNSTextField {
        let field = EditableNSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 14)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

// MARK: - OpenAI Logo

struct OpenAILogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        var p = Path()
        p.move(to: CGPoint(x: 22.2819 * sx, y: 9.8211 * sy))
        p.addCurve(to: CGPoint(x: 21.7662 * sx, y: 4.9103 * sy), control1: CGPoint(x: 22.8248 * sx, y: 8.1862 * sy), control2: CGPoint(x: 22.6369 * sx, y: 6.3967 * sy))
        p.addCurve(to: CGPoint(x: 15.2564 * sx, y: 2.0103 * sy), control1: CGPoint(x: 20.4571 * sx, y: 2.6316 * sy), control2: CGPoint(x: 17.8260 * sx, y: 1.4595 * sy))
        p.addCurve(to: CGPoint(x: 4.9807 * sx, y: 4.1818 * sy), control1: CGPoint(x: 12.1364 * sx, y: -1.4602 * sy), control2: CGPoint(x: 6.4298 * sx, y: -0.2543 * sy))
        p.addCurve(to: CGPoint(x: 0.9830 * sx, y: 7.0818 * sy), control1: CGPoint(x: 3.2928 * sx, y: 4.5279 * sy), control2: CGPoint(x: 1.8360 * sx, y: 5.5847 * sy))
        p.addCurve(to: CGPoint(x: 1.7257 * sx, y: 14.1784 * sy), control1: CGPoint(x: -0.3404 * sx, y: 9.3568 * sy), control2: CGPoint(x: -0.0401 * sx, y: 12.2267 * sy))
        p.addCurve(to: CGPoint(x: 2.2367 * sx, y: 19.0891 * sy), control1: CGPoint(x: 1.1808 * sx, y: 15.8125 * sy), control2: CGPoint(x: 1.3670 * sx, y: 17.6022 * sy))
        p.addCurve(to: CGPoint(x: 8.7513 * sx, y: 21.9892 * sy), control1: CGPoint(x: 3.5475 * sx, y: 21.3686 * sy), control2: CGPoint(x: 6.1803 * sx, y: 22.5406 * sy))
        p.addCurve(to: CGPoint(x: 13.2599 * sx, y: 24.0000 * sy), control1: CGPoint(x: 9.8948 * sx, y: 23.2770 * sy), control2: CGPoint(x: 11.5377 * sx, y: 24.0097 * sy))
        p.addCurve(to: CGPoint(x: 19.0317 * sx, y: 19.7942 * sy), control1: CGPoint(x: 15.8937 * sx, y: 24.0024 * sy), control2: CGPoint(x: 18.2271 * sx, y: 22.3021 * sy))
        p.addCurve(to: CGPoint(x: 23.0294 * sx, y: 16.8941 * sy), control1: CGPoint(x: 20.7194 * sx, y: 19.4475 * sy), control2: CGPoint(x: 22.1760 * sx, y: 18.3908 * sy))
        p.addCurve(to: CGPoint(x: 22.2819 * sx, y: 9.8212 * sy), control1: CGPoint(x: 24.3368 * sx, y: 14.6231 * sy), control2: CGPoint(x: 24.0351 * sx, y: 11.7688 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 13.2599 * sx, y: 22.4292 * sy))
        p.addCurve(to: CGPoint(x: 10.3835 * sx, y: 21.3884 * sy), control1: CGPoint(x: 12.2086 * sx, y: 22.4309 * sy), control2: CGPoint(x: 11.1903 * sx, y: 22.0624 * sy))
        p.addLine(to: CGPoint(x: 10.5254 * sx, y: 21.3080 * sy))
        p.addLine(to: CGPoint(x: 15.3037 * sx, y: 18.5498 * sy))
        p.addCurve(to: CGPoint(x: 15.6964 * sx, y: 17.8685 * sy), control1: CGPoint(x: 15.5456 * sx, y: 18.4079 * sy), control2: CGPoint(x: 15.6949 * sx, y: 18.1490 * sy))
        p.addLine(to: CGPoint(x: 15.6964 * sx, y: 11.1316 * sy))
        p.addLine(to: CGPoint(x: 17.7164 * sx, y: 12.3002 * sy))
        p.addCurve(to: CGPoint(x: 17.7544 * sx, y: 12.3522 * sy), control1: CGPoint(x: 17.7367 * sx, y: 12.3105 * sy), control2: CGPoint(x: 17.7508 * sx, y: 12.3298 * sy))
        p.addLine(to: CGPoint(x: 17.7544 * sx, y: 17.9348 * sy))
        p.addCurve(to: CGPoint(x: 13.2599 * sx, y: 22.4292 * sy), control1: CGPoint(x: 17.7491 * sx, y: 20.4148 * sy), control2: CGPoint(x: 15.7399 * sx, y: 22.4240 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 3.5992 * sx, y: 18.3038 * sy))
        p.addCurve(to: CGPoint(x: 3.0646 * sx, y: 15.2901 * sy), control1: CGPoint(x: 3.0720 * sx, y: 17.3934 * sy), control2: CGPoint(x: 2.8827 * sx, y: 16.3263 * sy))
        p.addLine(to: CGPoint(x: 3.2066 * sx, y: 15.3753 * sy))
        p.addLine(to: CGPoint(x: 7.9896 * sx, y: 18.1335 * sy))
        p.addCurve(to: CGPoint(x: 8.7702 * sx, y: 18.1335 * sy), control1: CGPoint(x: 8.2306 * sx, y: 18.2749 * sy), control2: CGPoint(x: 8.5292 * sx, y: 18.2749 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 14.7650 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 17.0974 * sy))
        p.addCurve(to: CGPoint(x: 14.5798 * sx, y: 17.1589 * sy), control1: CGPoint(x: 14.6119 * sx, y: 17.1219 * sy), control2: CGPoint(x: 14.5997 * sx, y: 17.1445 * sy))
        p.addLine(to: CGPoint(x: 9.7400 * sx, y: 19.9502 * sy))
        p.addCurve(to: CGPoint(x: 3.5992 * sx, y: 18.3038 * sy), control1: CGPoint(x: 7.5893 * sx, y: 21.1891 * sy), control2: CGPoint(x: 4.8416 * sx, y: 20.4525 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 2.3408 * sx, y: 7.8956 * sy))
        p.addCurve(to: CGPoint(x: 4.7063 * sx, y: 5.9228 * sy), control1: CGPoint(x: 2.8717 * sx, y: 6.9794 * sy), control2: CGPoint(x: 3.7096 * sx, y: 6.2805 * sy))
        p.addLine(to: CGPoint(x: 4.7063 * sx, y: 11.6000 * sy))
        p.addCurve(to: CGPoint(x: 5.0942 * sx, y: 12.2765 * sy), control1: CGPoint(x: 4.7026 * sx, y: 11.8793 * sy), control2: CGPoint(x: 4.8513 * sx, y: 12.1386 * sy))
        p.addLine(to: CGPoint(x: 10.9086 * sx, y: 15.6308 * sy))
        p.addLine(to: CGPoint(x: 8.8885 * sx, y: 16.7993 * sy))
        p.addCurve(to: CGPoint(x: 8.8175 * sx, y: 16.7993 * sy), control1: CGPoint(x: 8.8663 * sx, y: 16.8111 * sy), control2: CGPoint(x: 8.8397 * sx, y: 16.8111 * sy))
        p.addLine(to: CGPoint(x: 3.9872 * sx, y: 14.0128 * sy))
        p.addCurve(to: CGPoint(x: 2.3408 * sx, y: 7.8720 * sy), control1: CGPoint(x: 1.8408 * sx, y: 12.7686 * sy), control2: CGPoint(x: 1.1047 * sx, y: 10.0230 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 18.9371 * sx, y: 11.7514 * sy))
        p.addLine(to: CGPoint(x: 13.1038 * sx, y: 8.3640 * sy))
        p.addLine(to: CGPoint(x: 15.1192 * sx, y: 7.2000 * sy))
        p.addCurve(to: CGPoint(x: 15.1902 * sx, y: 7.2000 * sy), control1: CGPoint(x: 15.1414 * sx, y: 7.1882 * sy), control2: CGPoint(x: 15.1680 * sx, y: 7.1882 * sy))
        p.addLine(to: CGPoint(x: 20.0205 * sx, y: 9.9913 * sy))
        p.addCurve(to: CGPoint(x: 19.3440 * sx, y: 18.0955 * sy), control1: CGPoint(x: 23.3136 * sx, y: 11.8915 * sy), control2: CGPoint(x: 22.9065 * sx, y: 16.7676 * sy))
        p.addLine(to: CGPoint(x: 19.3440 * sx, y: 12.4183 * sy))
        p.addCurve(to: CGPoint(x: 18.9370 * sx, y: 11.7513 * sy), control1: CGPoint(x: 19.3355 * sx, y: 12.1397 * sy), control2: CGPoint(x: 19.1808 * sx, y: 11.8863 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 20.9478 * sx, y: 8.7283 * sy))
        p.addLine(to: CGPoint(x: 20.8058 * sx, y: 8.6431 * sy))
        p.addLine(to: CGPoint(x: 16.0323 * sx, y: 5.8613 * sy))
        p.addCurve(to: CGPoint(x: 15.2469 * sx, y: 5.8613 * sy), control1: CGPoint(x: 15.7898 * sx, y: 5.7190 * sy), control2: CGPoint(x: 15.4894 * sx, y: 5.7190 * sy))
        p.addLine(to: CGPoint(x: 9.4090 * sx, y: 9.2297 * sy))
        p.addLine(to: CGPoint(x: 9.4090 * sx, y: 6.8974 * sy))
        p.addCurve(to: CGPoint(x: 9.4374 * sx, y: 6.8359 * sy), control1: CGPoint(x: 9.4065 * sx, y: 6.8732 * sy), control2: CGPoint(x: 9.4174 * sx, y: 6.8496 * sy))
        p.addLine(to: CGPoint(x: 14.2677 * sx, y: 4.0493 * sy))
        p.addCurve(to: CGPoint(x: 20.9479 * sx, y: 8.7093 * sy), control1: CGPoint(x: 17.5693 * sx, y: 2.1473 * sy), control2: CGPoint(x: 21.5928 * sx, y: 4.9539 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.3065 * sx, y: 12.8630 * sy))
        p.addLine(to: CGPoint(x: 6.2865 * sx, y: 11.6992 * sy))
        p.addCurve(to: CGPoint(x: 6.2485 * sx, y: 11.6425 * sy), control1: CGPoint(x: 6.2660 * sx, y: 11.6869 * sy), control2: CGPoint(x: 6.2521 * sx, y: 11.6661 * sy))
        p.addLine(to: CGPoint(x: 6.2485 * sx, y: 6.0742 * sy))
        p.addCurve(to: CGPoint(x: 13.6242 * sx, y: 2.6205 * sy), control1: CGPoint(x: 6.2535 * sx, y: 2.2647 * sy), control2: CGPoint(x: 10.6950 * sx, y: 0.1849 * sy))
        p.addLine(to: CGPoint(x: 13.4822 * sx, y: 2.7010 * sy))
        p.addLine(to: CGPoint(x: 8.7040 * sx, y: 5.4590 * sy))
        p.addCurve(to: CGPoint(x: 8.3113 * sx, y: 6.1403 * sy), control1: CGPoint(x: 8.4621 * sx, y: 5.6009 * sy), control2: CGPoint(x: 8.3128 * sx, y: 5.8598 * sy))
        p.closeSubpath()
        // Inner hexagon
        p.move(to: CGPoint(x: 9.4041 * sx, y: 10.4976 * sy))
        p.addLine(to: CGPoint(x: 12.0061 * sx, y: 8.9978 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 10.4976 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 13.4970 * sy))
        p.addLine(to: CGPoint(x: 12.0156 * sx, y: 14.9967 * sy))
        p.addLine(to: CGPoint(x: 9.4089 * sx, y: 13.4970 * sy))
        p.closeSubpath()
        return p
    }
}
