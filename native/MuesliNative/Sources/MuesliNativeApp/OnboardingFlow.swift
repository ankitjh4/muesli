import Foundation

enum OnboardingFlow {
    enum LaunchDestination: Equatable { case setup, dashboard, background }

    static func launchDestination(completedSetup: Bool, recordingPermissionsReady: Bool, openDashboard: Bool) -> LaunchDestination {
        guard completedSetup else { return .setup }
        return openDashboard || !recordingPermissionsReady ? .dashboard : .background
    }

    struct UseCaseSelectionState: Equatable {
        let selectedUseCase: OnboardingUseCase
        let selectionBeforeEverything: OnboardingUseCase?
    }

    enum PermissionAdvanceAction: Equatable {
        case restartForDictationTest
        case finish
        case next
    }

    enum DictationTestMonitorAction: Equatable {
        case start
        case stop(cancelTestDictation: Bool)
        case none
    }

    enum Step: Int {
        case welcome = 0
        case model = 1
        case hotkey = 2
        case permissions = 3
        case dictationTest = 4
        case meetingSummary = 5
        case calendarAccess = 6
        // Keep the original raw values stable because onboarding progress is persisted.
        case appearance = 7
        case learn = 8
        case meetingTranscription = 9
        case quill = 10
        case review = 11
        case vocabulary = 12
    }

    static let dictationTestStep = Step.dictationTest.rawValue

    private static let canonicalStepOrder: [Step] = [
        .welcome,
        .learn,
        .model,
        .meetingTranscription,
        .meetingSummary,
        .quill,
        .vocabulary,
        .appearance,
        .hotkey,
        .permissions,
        .dictationTest,
        .calendarAccess,
        .review,
    ]

    private static func position(of rawStep: Int) -> Int? {
        canonicalStepOrder.firstIndex { $0.rawValue == rawStep }
    }

    private static func isStep(_ rawStep: Int, after otherRawStep: Int) -> Bool {
        guard let position = position(of: rawStep),
              let otherPosition = Self.position(of: otherRawStep) else {
            return rawStep > otherRawStep
        }
        return position > otherPosition
    }

    static func isStep(_ rawStep: Int, atOrAfter otherRawStep: Int) -> Bool {
        guard let position = position(of: rawStep),
              let otherPosition = Self.position(of: otherRawStep) else {
            return rawStep >= otherRawStep
        }
        return position >= otherPosition
    }

    /// Reconfirm a restored model whenever sanitization replaces it, without skipping
    /// earlier setup steps or discarding the permission gate for unchanged selections.
    static func modelGatedResumeStep(
        requestedStep: Int,
        initialBackend: BackendOption,
        resolvedBackend: BackendOption,
        currentOSVersion: OperatingSystemVersion = BackendOption.currentOSVersion
    ) -> Int {
        let mustChooseModel = resolvedBackend != initialBackend
            || !initialBackend.isCompatible(currentOSVersion: currentOSVersion)
        return mustChooseModel && isStep(requestedStep, after: Step.model.rawValue)
            ? Step.model.rawValue : requestedStep
    }

    /// A resumed setup must not jump past an unfinished model or account choice.
    /// This is shared by meeting transcription and optional Quill setup.
    static func setupGatedResumeStep(
        requestedStep: Int,
        setupStep: Step,
        isReady: Bool
    ) -> Int {
        !isReady && isStep(requestedStep, after: setupStep.rawValue)
            ? setupStep.rawValue : requestedStep
    }

    static func hasCompletedPermissionsStep(resumingAt step: Int) -> Bool {
        isStep(step, after: Step.permissions.rawValue)
    }

    static func shouldSchedulePermissionAdvance(
        currentStep: Int,
        requiredPermissionsGranted: Bool,
        hasCompletedPermissionsStep: Bool,
        hasScheduledTask: Bool
    ) -> Bool {
        currentStep == Step.permissions.rawValue
            && requiredPermissionsGranted
            && !hasCompletedPermissionsStep
            && !hasScheduledTask
    }

    static func toggling(
        _ capability: OnboardingCapability,
        in state: UseCaseSelectionState
    ) -> UseCaseSelectionState {
        UseCaseSelectionState(
            selectedUseCase: state.selectedUseCase.toggling(capability),
            selectionBeforeEverything: nil
        )
    }

    static func togglingEverything(in state: UseCaseSelectionState) -> UseCaseSelectionState {
        if state.selectedUseCase == .everything {
            guard let previousSelection = state.selectionBeforeEverything else { return state }
            return UseCaseSelectionState(
                selectedUseCase: previousSelection,
                selectionBeforeEverything: nil
            )
        }
        return UseCaseSelectionState(
            selectedUseCase: .everything,
            selectionBeforeEverything: state.selectedUseCase
        )
    }

    static func permissionAdvanceAction(
        for useCase: OnboardingUseCase,
        currentStepIndex: Int,
        orderedStepCount: Int,
        hasCompletedPermissionsStep: Bool = false
    ) -> PermissionAdvanceAction {
        if hasCompletedPermissionsStep {
            return currentStepIndex == orderedStepCount - 1 ? .finish : .next
        }
        if useCase.includesPushToTalk { return .restartForDictationTest }
        if currentStepIndex == orderedStepCount - 1 { return .finish }
        return .next
    }

    static func shouldReclassifyVoiceNotesAsDictation(
        previousUseCase: OnboardingUseCase,
        permissions: OnboardingPermissionSnapshot
    ) -> Bool {
        previousUseCase == .voiceNotes
            && OnboardingPermissionGate.hasRequiredDictationPermissions(permissions)
    }

    static func shouldStartDictationTestMonitor(
        currentStep: Int,
        dictationTestStep: Int,
        modelReady: Bool
    ) -> Bool {
        modelReady && isStep(currentStep, atOrAfter: dictationTestStep)
    }

    static func dictationTestMonitorAction(
        currentStep: Int,
        dictationTestStep: Int,
        modelReady: Bool,
        monitorActive: Bool,
        dictationTesting: Bool
    ) -> DictationTestMonitorAction {
        guard isStep(currentStep, atOrAfter: dictationTestStep) else { return .none }
        guard currentStep == dictationTestStep else {
            return monitorActive ? .stop(cancelTestDictation: dictationTesting) : .none
        }
        guard modelReady else {
            return .stop(cancelTestDictation: dictationTesting)
        }
        return monitorActive ? .none : .start
    }

    static func orderedSteps(for useCase: OnboardingUseCase) -> [Int] {
        var steps = [Step.welcome.rawValue, Step.learn.rawValue]
        if useCase.includesPushToTalk {
            steps.append(Step.model.rawValue)
        }
        if useCase.includesMeetings {
            steps += [Step.meetingTranscription.rawValue, Step.meetingSummary.rawValue]
        }
        if useCase.includesDictation {
            steps.append(Step.quill.rawValue)
        }
        steps.append(Step.vocabulary.rawValue)
        steps.append(Step.appearance.rawValue)
        if useCase.includesPushToTalk {
            steps.append(Step.hotkey.rawValue)
        }
        steps.append(Step.permissions.rawValue)
        if useCase.includesPushToTalk {
            steps.append(Step.dictationTest.rawValue)
        }
        if useCase.includesMeetings {
            steps.append(Step.calendarAccess.rawValue)
        }
        steps.append(Step.review.rawValue)
        return steps
    }

    static func normalizedStep(_ step: Int, for useCase: OnboardingUseCase) -> Int {
        let steps = orderedSteps(for: useCase)
        if steps.contains(step) { return step }
        guard let requestedPosition = position(of: step) else {
            return steps.last ?? Step.welcome.rawValue
        }
        return canonicalStepOrder
            .dropFirst(requestedPosition + 1)
            .map(\.rawValue)
            .first(where: steps.contains)
            ?? steps.last
            ?? Step.welcome.rawValue
    }

    static func stepIndex(_ step: Int, for useCase: OnboardingUseCase) -> Int {
        orderedSteps(for: useCase).firstIndex(of: step) ?? 0
    }

    static func canGoBack(from step: Int, useCase: OnboardingUseCase, dictationTestSucceeded: Bool) -> Bool {
        guard stepIndex(step, for: useCase) > 0 else { return false }
        return !(step == Step.dictationTest.rawValue && dictationTestSucceeded)
    }

    static func completionTab(for useCase: OnboardingUseCase) -> DashboardTab {
        useCase.includesMeetings && !useCase.includesPushToTalk ? .meetings : .dictations
    }
}
