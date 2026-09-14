import SwiftUI

enum OnboardingQuillModelSelection {
    static func openRouterModel(in config: AppConfig) -> String {
        guard config.quilBackend == TranscriptCleanupBackendOption.hosted(.openRouter).backend else { return "" }
        return config.quilModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func completedModel(backend: TranscriptCleanupBackendOption, config: AppConfig) -> String {
        if backend == .hosted(.openRouter) { return openRouterModel(in: config) }
        return backend.isOnDevice ? PostProcessorOption.defaultQuilOption.id
            : TranscriptCleanupClient.defaultModel(for: backend)
    }
}

/// A catalog-backed choice, never an automatically selected hosted default.
struct OpenRouterTextModelSetupView: View {
    let controller: MuesliController
    let appState: AppState
    @Binding var modelID: String

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Picker("Text model", selection: $modelID) {
                Text("Choose a model…").tag("")
                ForEach(appState.openRouterSummaryModels, id: \.id) { model in
                    Text(model.label).tag(model.id)
                }
                if !modelID.isEmpty && !appState.openRouterSummaryModels.contains(where: { $0.id == modelID }) {
                    Text("Saved: \(modelID)").tag(modelID)
                }
            }
            .pickerStyle(.menu)
            if appState.openRouterSummaryCatalogState == .loading {
                ProgressView("Loading current text models…").controlSize(.small)
            }
            if case .failed(let message) = appState.openRouterSummaryCatalogState {
                Text("\(message). Retry to choose a current model.")
                    .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
            }
            Button("Refresh text models") { controller.loadOpenRouterModels(.text, force: true) }
                .disabled(appState.openRouterSummaryCatalogState == .loading)
            Text("Your request and selected text go to this provider. Internet access and provider credits may be required. Saving a key does not test the connection.")
                .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { controller.loadOpenRouterModels(.text) }
    }
}

enum OnlineDictationSetupPolicy {
    static func isMeetingReady(config: AppConfig, authenticated: Bool, localModelReady: Bool) -> Bool {
        if config.useOpenRouterForMeetings && !config.offlineInference {
            return isReady(authenticated: authenticated, modelID: config.openRouterMeetingModel)
        }
        return localModelReady
    }

    static func isReady(authenticated: Bool, modelID: String) -> Bool {
        authenticated && !OpenRouterTranscriptionClient.normalizedModel(modelID).isEmpty
    }
}

/// First-run configuration only. Saving a key does not claim a successful
/// inference request, and the live catalogue is never replaced by a fixed list.
struct OnlineDictationSetupView: View {
    let controller: MuesliController
    let appState: AppState
    var forMeetings = false
    @State private var apiKey = ""
    @State private var credentialError: String?

    private var selectedModel: String {
        forMeetings ? appState.config.openRouterMeetingModel : appState.config.openRouterDictationModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Text("Speech recognition without a model download")
                .font(MuesliTheme.headline())
                .fixedSize(horizontal: false, vertical: true)
            Text("OpenRouter sends your recording to the model provider you choose. You need internet access and may pay per use. Your key can also power text cleanup and Quill, with a different model for each task.")
                .font(MuesliTheme.body())
                .fixedSize(horizontal: false, vertical: true)

            if appState.isOpenRouterAuthenticated {
                Label("OpenRouter key saved · connection not yet tested", systemImage: "key.fill")
                    .font(MuesliTheme.caption())
            } else {
                SecureField("OpenRouter API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save key and load models") {
                    credentialError = controller.storeManualOpenRouterAPIKey(apiKey, selectMeetingSummaryBackend: false)
                    if credentialError == nil {
                        apiKey = ""
                        controller.loadOpenRouterModels(.transcription, force: true)
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let credentialError {
                    Text(credentialError).foregroundStyle(MuesliTheme.recording)
                }
            }

            if appState.isOpenRouterAuthenticated {
                Picker("Speech model", selection: Binding(
                    get: { selectedModel },
                    set: { model in
                        if forMeetings { controller.updateConfig { $0.openRouterMeetingModel = model } }
                        else { controller.selectOpenRouterDictationModel(model) }
                    }
                )) {
                    Text("Choose a model…").tag("")
                    ForEach(ActiveModelOrder.first(appState.openRouterTranscriptionModels, matching: { $0.id == selectedModel }), id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                    let configured = selectedModel
                    if !configured.isEmpty && !appState.openRouterTranscriptionModels.contains(where: { $0.id == configured }) {
                        Text("Saved: \(configured)").tag(configured)
                    }
                }
                .pickerStyle(.menu)
                if appState.openRouterTranscriptionCatalogState == .loading {
                    ProgressView("Loading current speech models…").controlSize(.small)
                }
                if case .failed(let message) = appState.openRouterTranscriptionCatalogState {
                    Text("\(message). Retry to get the current list; no model will be chosen automatically.")
                        .font(MuesliTheme.caption())
                }
                Button("Refresh model list") {
                    controller.loadOpenRouterModels(.transcription, force: true)
                }
                .disabled(appState.openRouterTranscriptionCatalogState == .loading)
            }

            Text("You can mix online speech with local cleanup, or use OpenRouter for both. Change Speech, Text Cleanup, and Quill from the menu-bar icon. For offline use, download both a speech model and a language model first.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(forMeetings
                 ? "Meeting audio goes to this provider in short chunks. Imports and re-transcription ask before uploading. Online transcripts have approximate timestamps and no automatic speaker labels. Summary generation is a separate choice on the next screen."
                 : "Meetings have their own speech-model choice. You can use a different online model or keep meeting audio on this Mac.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .onAppear {
            if appState.isOpenRouterAuthenticated {
                controller.loadOpenRouterModels(.transcription)
            }
        }
    }
}
