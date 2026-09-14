import SwiftUI

/// A readable explanation of the selected pipeline, not a readiness guarantee.
struct HomePipelineSummary: Equatable {
    let speech: String
    let speechLocation: String
    let cleanup: String
    let cleanupLocation: String
    let output: String

    init(config: AppConfig, backend: BackendOption) {
        switch config.resolvedDictationProvider {
        case .local:
            speech = backend.label
            speechLocation = backend.backend == "apple-speech" ? "Managed by macOS"
                : backend.isDownloaded ? "On this Mac" : "Download needed · open Models"
        case .openAI:
            speech = config.openaiDictationModel
            speechLocation = "Audio sent to OpenAI"
        case .openRouter:
            speech = config.openRouterDictationModel.isEmpty ? "Choose a speech model" : config.openRouterDictationModel
            speechLocation = "Audio sent to OpenRouter"
        }
        let cleanupBackend = TranscriptCleanupBackendOption.resolved(config.postProcessorBackend)
        if !config.enablePostProcessor {
            cleanup = "Original transcript"
            cleanupLocation = config.pendingLocalCleanupSetup
                ? "Waiting for local language model · open Models"
                : "Language-model cleanup is off"
        } else if cleanupBackend == .local {
            let option = PostProcessorOption.resolve(id: config.activePostProcessorId)
            cleanup = option.label
            cleanupLocation = !option.isCompatible(with: backend) ? "Choose a compatible cleanup model"
                : option.isDownloaded ? "Language model on this Mac" : "Download needed · open Models"
        } else {
            cleanup = cleanupBackend.label
            cleanupLocation = cleanupBackend.isOnDevice ? "Language model on this Mac" : "Transcript sent to selected service"
        }
        output = config.romanizeHindi && config.resolvedDictationProvider == .local && backend.backend == "bodhan"
            ? "Hindi → Roman letters · local LLM" : "Your words, ready to use"
    }
}

struct HomeView: View {
    let appState: AppState
    let controller: MuesliController
    @State private var needsRecordingSetup = false

    var body: some View {
        VStack(spacing: 0) {
        if needsRecordingSetup {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mic.slash").foregroundStyle(MuesliTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore first. Enable recording when you're ready.").font(MuesliTheme.headline())
                    Text("You can browse models, edit your dictionary, and change settings without granting recording permissions.")
                        .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                    Button("Set up recording") { controller.resumeRecordingSetup() }
                        .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MuesliTheme.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24).padding(.top, 16)
        }
        HomeDashboardContent(
            name: appState.config.userName,
            hotkey: appState.config.dictationHotkey.label,
            offline: appState.config.offlineInference,
            quillEnabled: appState.config.enableQuilMode,
            pipeline: HomePipelineSummary(config: appState.config, backend: appState.selectedBackend),
            onModels: { appState.selectedTab = .models },
            onHistory: { controller.showTimelineHome() },
            onMeetings: { controller.showMeetingsHome() },
            onQuill: {
                appState.selectedSettingsPane = .dictation
                controller.openSettingsTab()
            },
            onDictionary: { appState.selectedTab = .dictionary },
            onShortcuts: { appState.selectedTab = .shortcuts }
        )
        }
        .onAppear { needsRecordingSetup = controller.needsRecordingSetup }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            needsRecordingSetup = controller.needsRecordingSetup
        }
    }
}

/// Separate from app services so narrow, light, and dark layouts can be rendered in tests.
struct HomeDashboardContent: View {
    let name: String
    let hotkey: String
    let offline: Bool
    let quillEnabled: Bool
    let pipeline: HomePipelineSummary
    let onModels: () -> Void
    let onHistory: () -> Void
    let onMeetings: () -> Void
    let onQuill: () -> Void
    let onDictionary: () -> Void
    let onShortcuts: () -> Void

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("START HERE").font(.system(size: 10, weight: .bold)).tracking(1.5)
                            .foregroundStyle(MuesliTheme.textSecondary)
                        Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Welcome to muesli+" : "Hello, \(name)")
                            .font(.system(size: 23, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "waveform")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                    Text("Your words.\nLess work.")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Click where you want to write. Hold your dictation shortcut, speak, then release.")
                        .font(.system(size: 15))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onShortcuts) {
                        Label(hotkey, systemImage: "keyboard")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(MuesliTheme.backgroundBase)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuesliTheme.surfaceBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("View or change your shortcuts")
                    .accessibilityLabel("Dictation shortcut: \(hotkey). Open shortcut settings.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(LinearGradient(colors: [MuesliTheme.accent.opacity(0.10), MuesliTheme.accent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(MuesliTheme.accent.opacity(0.12), lineWidth: 1))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: geometry.size.width >= 560 ? 2 : 1), spacing: 14) {
                    actionCard("Meeting notes", detail: "Record a conversation, then review its transcript and notes.", icon: "person.2", action: onMeetings)
                    actionCard("Write with Quill", detail: quillEnabled ? "Highlight text and tell Quill how to change it. Adjust its style here." : "Set up an optional writing assistant for text you select.", icon: "pencil.and.scribble", action: onQuill)
                    actionCard("Your dictionary", detail: "Teach names, work terms, and corrections that matter to you.", icon: "character.book.closed", action: onDictionary)
                    actionCard("Recent activity", detail: "Find, review, and copy earlier dictations and meeting notes.", icon: "clock", action: onHistory)
                }

                VStack(alignment: .leading, spacing: 18) {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text("How your words are processed").font(.headline); Spacer(); modelsButton }
                        VStack(alignment: .leading, spacing: 10) { Text("How your words are processed").font(.headline); modelsButton }
                    }
                    Label(offline ? "Offline models · preview" : "Online / mixed models", systemImage: offline ? "internaldrive" : "network")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                    pipelineRow("1", title: "Speech to text", model: pipeline.speech, detail: pipeline.speechLocation)
                    Divider()
                    pipelineRow("2", title: "Spelling & grammar", model: pipeline.cleanup, detail: pipeline.cleanupLocation)
                    Divider()
                    pipelineRow("3", title: "Ready to insert", model: pipeline.output, detail: "Review important names, numbers, and messages")
                    Text(offline ? "Inference uses local models. Strict no-network behavior is still being verified; background services may connect." : "You can combine local speech with online cleanup, or run both locally. Change models from the menu-bar icon at the top of your screen.")
                        .font(.caption).foregroundStyle(MuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(MuesliTheme.surfaceBorder, lineWidth: 1))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .frame(maxWidth: 940, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MuesliTheme.backgroundBase)
        }
    }

    private var modelsButton: some View {
        Button("Manage models", action: onModels).buttonStyle(.link)
    }

    private func actionCard(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(MuesliTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(MuesliTheme.textSecondary)
                }
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .padding(20)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MuesliTheme.surfaceBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func pipelineRow(_ number: String, title: String, model: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 26, height: 26)
                .background(MuesliTheme.accent.opacity(0.10)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(MuesliTheme.textSecondary)
                Text(model).font(.system(size: 14, weight: .medium)).textSelection(.enabled)
                Text(detail).font(.caption).foregroundStyle(MuesliTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
