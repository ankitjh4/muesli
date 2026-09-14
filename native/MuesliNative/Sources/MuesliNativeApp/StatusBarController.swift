import AppKit
import Foundation
import MuesliCore

final class CalendarMenuMeetingPayload: NSObject {
    let title: String
    let calendarOccurrence: CalendarOccurrenceReference
    let endDate: Date
    let autoStopSource: MeetingAutoStopSource?

    init(event: UnifiedCalendarEvent) {
        self.title = event.title
        self.calendarOccurrence = event.resolvedCalendarOccurrence
        self.endDate = event.endDate
        self.autoStopSource = event.meetingURL.flatMap { MeetingAutoStopSource(meetingURL: $0) }
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let controller: MuesliController
    private let runtime: RuntimePaths
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var countdownOverride: String?

    init(controller: MuesliController, runtime: RuntimePaths) {
        self.controller = controller
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        build()
    }

    func setStatus(_ text: String) {}

    func refresh() {
        rebuildMenu()
        updateMenuBarTitle()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func setCountdownOverride(_ text: String?) {
        countdownOverride = text
        updateMenuBarTitle()
    }

    func refreshIcon() {
        statusItem.button?.image = MenuBarIconRenderer.make(choice: controller.config.menuBarIcon)
        updateMenuBarTitle()
    }

    func updateMenuBarTitle() {
        let detail: String?
        if let countdownOverride {
            detail = countdownOverride
        } else if controller.config.showNextMeetingInMenuBar {
            let now = Date()
            let hidden = controller.appState.hiddenCalendarEventIDs
            let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
            let nextEvent = controller.appState.upcomingCalendarEvents
                .filter { !$0.isAllDay && $0.startDate > now && $0.startDate < endOfToday && !hidden.contains($0.id) }
                .sorted { $0.startDate < $1.startDate }
                .first

            if let event = nextEvent {
                let minutesUntil = Int(ceil(event.startDate.timeIntervalSince(now) / 60))
                let truncatedTitle = event.title.count > 20
                    ? String(event.title.prefix(18)) + "…"
                    : event.title
                detail = minutesUntil <= 60
                    ? "\(truncatedTitle) · \(formatTimeUntil(minutesUntil))"
                    : truncatedTitle
            } else {
                detail = nil
            }
        } else {
            detail = nil
        }
        let totalWords = controller.appState.dictationStats.totalWords
        statusItem.button?.attributedTitle = MenuBarIconRenderer.statusTitle(
            hotkey: controller.config.dictationHotkey,
            showsHotkey: controller.config.showHotkeyInMenuBar,
            wordCount: totalWords,
            detail: detail
        )
        statusItem.button?.toolTip = "\(AppIdentity.displayName) · \(totalWords.formatted()) words dictated"
    }

    private func build() {
        if let button = statusItem.button {
            button.image = MenuBarIconRenderer.make(choice: controller.config.menuBarIcon)
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = AppIdentity.displayName
        }
        rebuildMenu()
        updateMenuBarTitle()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(actionItem(
            title: controller.config.offlineInference ? "✓ Offline models (preview)" : "Use offline models (preview)",
            action: #selector(MuesliController.selectOfflineInferenceFromMenu)
        ))
        menu.addItem(actionItem(
            title: controller.config.offlineInference ? "Allow online models" : "✓ Online / mixed models",
            action: #selector(MuesliController.selectOnlineInferenceFromMenu)
        ))
        menu.addItem(.separator())

        // Upcoming calendar events
        let hidden = controller.appState.hiddenCalendarEventIDs
        let upcomingEvents = controller.appState.upcomingCalendarEvents.filter { !$0.isAllDay && !hidden.contains($0.id) }
        if !upcomingEvents.isEmpty {
            addUpcomingEventsSection(upcomingEvents)
            menu.addItem(.separator())
        }

        menu.addItem(actionItem(title: "Open \(AppIdentity.displayName)", action: #selector(MuesliController.openHistoryWindow as (MuesliController) -> () -> Void)))
        if controller.isMeetingRecording() {
            let pauseTitle = controller.isMeetingRecordingPaused() ? "Resume Meeting Recording" : "Pause Meeting Recording"
            menu.addItem(actionItem(title: pauseTitle, action: #selector(MuesliController.toggleMeetingRecordingPause)))
            menu.addItem(actionItem(title: "Stop Meeting Recording", action: #selector(MuesliController.toggleMeetingRecording)))
            menu.addItem(actionItem(title: "Discard Meeting Recording...", action: #selector(MuesliController.discardMeetingWithConfirmation)))
        } else {
            menu.addItem(actionItem(
                title: "Start Meeting Recording",
                action: #selector(MuesliController.startMeetingRecordingFromMenuBar)
            ))
        }
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let recentRows = controller.recentDictations()
        if recentRows.isEmpty {
            let empty = NSMenuItem(title: "No dictations yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for row in recentRows {
                let item = NSMenuItem(title: controller.truncate(row.rawText, limit: 54), action: #selector(MuesliController.copyRecentDictation(_:)), keyEquivalent: "")
                item.target = controller
                item.representedObject = row.rawText
                recentMenu.addItem(item)
            }
        }
        menu.setSubmenu(recentMenu, for: recentItem)
        menu.addItem(recentItem)

        let dictationModelItem = NSMenuItem(title: "Dictation Model", action: nil, keyEquivalent: "")
        let dictationModelMenu = NSMenu()
        dictationModelMenu.addItem(.sectionHeader(title: "Local"))
        for option in BackendOption.downloaded {
            let isSelected = controller.selectedDictationProvider == .local
                && controller.selectedBackend == option
            let prefix = isSelected ? "✓ " : ""
            let item = NSMenuItem(
                title: "\(prefix)\(option.label)",
                action: #selector(MuesliController.selectLocalDictationModelFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = controller
            item.representedObject = option.label
            dictationModelMenu.addItem(item)
        }

        let hostedVisibility = controller.hostedDictationModelVisibility
        if !controller.config.offlineInference && hostedVisibility.shows(.openAI) {
            dictationModelMenu.addItem(.separator())
            dictationModelMenu.addItem(.sectionHeader(title: "OpenAI"))
            var openAIModels = OpenAITranscriptionClient.modelPresets
            let configuredOpenAIModel = controller.config.openaiDictationModel
            if !openAIModels.contains(configuredOpenAIModel) {
                openAIModels.append(configuredOpenAIModel)
            }
            for model in openAIModels {
                let isSelected = controller.selectedDictationProvider == .openAI
                    && configuredOpenAIModel == model
                let prefix = isSelected ? "✓ " : ""
                let item = NSMenuItem(
                    title: "\(prefix)\(model)",
                    action: #selector(MuesliController.selectOpenAIDictationModelFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = controller
                item.representedObject = model
                dictationModelMenu.addItem(item)
            }
        }

        if !controller.config.offlineInference && hostedVisibility.shows(.openRouter) {
            controller.loadOpenRouterModels(.transcription)
            dictationModelMenu.addItem(.separator())
            dictationModelMenu.addItem(.sectionHeader(title: "OpenRouter"))
            let openRouterModels = OpenRouterModelSelection.presetsIncludingConfiguredModel(
                controller.appState.openRouterTranscriptionModels,
                configuredModel: controller.config.openRouterDictationModel
            )
            if openRouterModels.isEmpty {
                let item = NSMenuItem(title: "Choose a model in Settings…", action: nil, keyEquivalent: "")
                item.isEnabled = false
                dictationModelMenu.addItem(item)
            } else {
                for preset in openRouterModels {
                    let isSelected = controller.selectedDictationProvider == .openRouter
                        && controller.config.openRouterDictationModel == preset.id
                    let prefix = isSelected ? "✓ " : ""
                    let item = NSMenuItem(
                        title: "\(prefix)\(preset.label)",
                        action: #selector(MuesliController.selectOpenRouterDictationModelFromMenu(_:)),
                        keyEquivalent: ""
                    )
                    item.target = controller
                    item.representedObject = preset.id
                    dictationModelMenu.addItem(item)
                }
            }
        }
        if let active = dictationModelMenu.items.first(where: { $0.title.hasPrefix("✓ ") }) {
            dictationModelMenu.removeItem(active)
            dictationModelMenu.insertItem(active, at: 0)
        }
        menu.setSubmenu(dictationModelMenu, for: dictationModelItem)
        menu.addItem(dictationModelItem)

        let cleanupItem = NSMenuItem(title: "Text Cleanup Model", action: nil, keyEquivalent: "")
        let cleanupMenu = NSMenu()
        let off = NSMenuItem(
            title: controller.config.enablePostProcessor ? "Off" : "✓ Off",
            action: #selector(MuesliController.disableCleanupFromMenu(_:)), keyEquivalent: ""
        )
        off.target = controller
        cleanupMenu.addItem(off)
        cleanupMenu.addItem(.sectionHeader(title: "On this Mac — downloaded language models"))
        for option in PostProcessorOption.downloaded {
            let selected = controller.config.enablePostProcessor
                && controller.selectedPostProcessorBackend == .local
                && controller.config.activePostProcessorId == option.id
            let item = NSMenuItem(
                title: "\(selected ? "✓ " : "")\(option.label)",
                action: #selector(MuesliController.selectLocalCleanupFromMenu(_:)), keyEquivalent: ""
            )
            item.target = controller
            item.representedObject = option.id
            item.isEnabled = option.isCompatible(with: controller.selectedBackend)
            cleanupMenu.addItem(item)
        }
        if !controller.config.offlineInference && controller.appState.isOpenRouterAuthenticated {
            controller.loadOpenRouterModels(.text)
            cleanupMenu.addItem(.sectionHeader(title: "OpenRouter — sends transcript online"))
            for preset in OpenRouterModelSelection.presetsIncludingConfiguredModel(
                controller.appState.openRouterSummaryModels,
                configuredModel: controller.config.postProcessorOpenRouterModel
            ) {
                let selected = controller.config.enablePostProcessor
                    && controller.selectedPostProcessorBackend == .hosted(.openRouter)
                    && controller.config.postProcessorOpenRouterModel == preset.id
                let item = NSMenuItem(
                    title: "\(selected ? "✓ " : "")\(preset.label)",
                    action: #selector(MuesliController.selectOnlineCleanupFromMenu(_:)), keyEquivalent: ""
                )
                item.target = controller
                item.representedObject = preset.id
                cleanupMenu.addItem(item)
            }
        }
        cleanupMenu.addItem(.separator())
        cleanupMenu.addItem(actionItem(title: "Download models / configure cleanup…", action: #selector(MuesliController.openSettingsTab)))
        if let active = cleanupMenu.items.first(where: { $0.title.hasPrefix("✓ ") }) {
            cleanupMenu.removeItem(active)
            cleanupMenu.insertItem(active, at: 0)
        }
        menu.setSubmenu(cleanupMenu, for: cleanupItem)
        menu.addItem(cleanupItem)

        let quilItem = NSMenuItem(title: "Quill Writing Model", action: nil, keyEquivalent: "")
        let quilMenu = NSMenu()
        quilMenu.addItem(.sectionHeader(title: "On this Mac — downloaded language models"))
        for option in PostProcessorOption.downloaded where option.supportsQuil {
            let selected = controller.config.quilBackend == TranscriptCleanupBackendOption.local.backend
                && controller.config.quilModel == option.id
            let item = NSMenuItem(
                title: "\(selected ? "✓ " : "")\(option.quilLabel)",
                action: #selector(MuesliController.selectLocalQuilFromMenu(_:)), keyEquivalent: ""
            )
            item.target = controller
            item.representedObject = option.id
            quilMenu.addItem(item)
        }
        if !controller.config.offlineInference && controller.appState.isOpenRouterAuthenticated {
            controller.loadOpenRouterModels(.text)
            quilMenu.addItem(.sectionHeader(title: "OpenRouter — sends text online"))
            for preset in OpenRouterModelSelection.presetsIncludingConfiguredModel(
                controller.appState.openRouterSummaryModels,
                configuredModel: controller.config.quilBackend == TranscriptCleanupBackendOption.hosted(.openRouter).backend
                    ? controller.config.quilModel : ""
            ) {
                let selected = controller.config.quilBackend == TranscriptCleanupBackendOption.hosted(.openRouter).backend
                    && controller.config.quilModel == preset.id
                let item = NSMenuItem(
                    title: "\(selected ? "✓ " : "")\(preset.label)",
                    action: #selector(MuesliController.selectOnlineQuilFromMenu(_:)), keyEquivalent: ""
                )
                item.target = controller
                item.representedObject = preset.id
                quilMenu.addItem(item)
            }
        }
        quilMenu.addItem(.separator())
        quilMenu.addItem(actionItem(title: "Download models / configure Quill…", action: #selector(MuesliController.openSettingsTab)))
        if let active = quilMenu.items.first(where: { $0.title.hasPrefix("✓ ") }) {
            quilMenu.removeItem(active)
            quilMenu.insertItem(active, at: 0)
        }
        menu.setSubmenu(quilMenu, for: quilItem)
        menu.addItem(quilItem)

        let meetingBackendItem = NSMenuItem(title: "Meetings Backend", action: nil, keyEquivalent: "")
        let meetingBackendMenu = NSMenu()
        if controller.config.offlineInference {
            let local = NSMenuItem(title: "On this Mac — \(PostProcessorOption.defaultQuilOption.quilLabel)", action: nil, keyEquivalent: "")
            local.isEnabled = false
            meetingBackendMenu.addItem(local)
        }
        for option in MeetingSummaryBackendOption.all where !controller.config.offlineInference {
            let prefix = controller.selectedMeetingSummaryBackend == option ? "✓ " : ""
            let item = NSMenuItem(
                title: "\(prefix)\(option.label)",
                action: #selector(MuesliController.selectMeetingSummaryBackendFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = controller
            item.representedObject = option.label
            meetingBackendMenu.addItem(item)
        }
        menu.setSubmenu(meetingBackendMenu, for: meetingBackendItem)
        menu.addItem(meetingBackendItem)

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Settings…", action: #selector(MuesliController.openSettingsTab)))
        menu.addItem(actionItem(title: "What's New in Muesli+", action: #selector(MuesliController.showWhatsNew)))
        menu.addItem(checkForUpdatesItem())
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit", action: #selector(MuesliController.quitApp)))
    }

    private func addUpcomingEventsSection(_ events: [UnifiedCalendarEvent]) {
        let now = Date()
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let futureEvents = events
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
        let nextUpEvents = futureEvents.filter { $0.startDate.timeIntervalSince(now) <= 3600 }
        let laterEvents = futureEvents.filter { $0.startDate.timeIntervalSince(now) > 3600 }

        if !nextUpEvents.isEmpty {
            let firstEvent = nextUpEvents[0]
            let minutesUntil = Int(ceil(firstEvent.startDate.timeIntervalSince(now) / 60))
            addUpcomingEventGroup(
                title: "Starts in \(formatTimeUntil(minutesUntil))",
                events: nextUpEvents,
                timeFormatter: timeFormatter
            )
        }

        let groupedEvents = Dictionary(grouping: laterEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        for day in groupedEvents.keys.sorted() {
            let dayEvents = (groupedEvents[day] ?? []).sorted { $0.startDate < $1.startDate }
            addUpcomingEventGroup(
                title: upcomingMenuHeader(for: day, calendar: calendar),
                events: dayEvents,
                timeFormatter: timeFormatter,
                limit: 5
            )
        }
    }

    private func addUpcomingEventGroup(
        title: String,
        events: [UnifiedCalendarEvent],
        timeFormatter: DateFormatter,
        limit: Int? = nil
    ) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        header.attributedTitle = NSAttributedString(string: title, attributes: headerAttrs)
        menu.addItem(header)

        let displayedEvents = limit.map { Array(events.prefix($0)) } ?? events
        for event in displayedEvents {
            let timeStr = "\(timeFormatter.string(from: event.startDate)) – \(timeFormatter.string(from: event.endDate))"
            let item = NSMenuItem(
                title: "\(event.title)\n\(timeStr)",
                action: #selector(MuesliController.startMeetingFromCalendarMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = controller
            item.representedObject = CalendarMenuMeetingPayload(event: event)

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let attributed = NSMutableAttributedString(string: event.title, attributes: titleAttrs)
            attributed.append(NSAttributedString(string: "\n\(timeStr)", attributes: timeAttrs))
            item.attributedTitle = attributed
            menu.addItem(item)
        }
    }

    private func upcomingMenuHeader(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInTomorrow(day) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day)
    }

    private func formatTimeUntil(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = controller
        return item
    }

    private func checkForUpdatesItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(MuesliController.checkForUpdates),
            keyEquivalent: ""
        )
        item.target = controller
        item.isEnabled = controller.updaterController != nil
        return item
    }
}
