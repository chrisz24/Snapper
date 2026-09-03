import SwiftUI
import AppKit

/// Settings, laid out the way System Settings does it: a source list on the left, one pane on the
/// right.
///
/// This replaced a `TabView`. With six sections its tab bar could not fit the window and collapsed
/// every tab into an overflow chevron, leaving the window with no visible navigation at all. A
/// sidebar has no such ceiling and is the current macOS convention besides.
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bindings: HotkeyBindings
    @ObservedObject var tabSelection: SettingsTabSelection
    var onHotkeysChanged: () -> Void
    var onRunSetup: () -> Void

    public init(
        settings: SettingsStore,
        bindings: HotkeyBindings,
        tabSelection: SettingsTabSelection,
        onHotkeysChanged: @escaping () -> Void,
        onRunSetup: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.bindings = bindings
        self.tabSelection = tabSelection
        self.onHotkeysChanged = onHotkeysChanged
        self.onRunSetup = onRunSetup
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(SettingsTab.allCases) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: tab.symbol)
                            .foregroundStyle(.white)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(color(for: tab))
                            )
                    }
                    .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 186, ideal: 196, max: 240)
        } detail: {
            detail
                .navigationTitle(tabSelection.selection.title)
                .frame(minWidth: 440)
        }
        .frame(minWidth: 660, minHeight: 460)
    }

    private var selectionBinding: Binding<SettingsTab?> {
        Binding(
            get: { tabSelection.selection },
            set: { tabSelection.selection = $0 ?? tabSelection.selection }
        )
    }

    private func color(for tab: SettingsTab) -> Color {
        switch tab.tint {
        case "blue": .blue
        case "purple": .purple
        case "orange": .orange
        case "teal": .teal
        default: .gray
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch tabSelection.selection {
        case .general: GeneralPane(settings: settings)
        case .capture: CapturePane(settings: settings)
        case .text: TextPane(settings: settings)
        case .quickActions: QuickActionsPane(settings: settings, bindings: bindings)
        case .shortcuts: ShortcutsPane(bindings: bindings, onHotkeysChanged: onHotkeysChanged, onRunSetup: onRunSetup)
        case .about: AboutPane(settings: settings)
        }
    }
}

/// A slider with its readout, sized so every row in a pane lines up.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let readout: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 150)
                Text(readout)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var launchAtLogin = LoginItem.isEnabled
    /// Set only when a login-item change was refused, so the reason can be shown.
    @State private var loginItemProblem: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show the menu bar icon", isOn: $settings.showMenuBarIcon)
            } header: {
                Text("Menu bar")
            } footer: {
                if settings.showMenuBarIcon {
                    Text("The icon is where the capture history, setup and this window live. "
                         + "macOS hides menu bar icons it has no room for, which looks the same as "
                         + "this being switched off.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("The shortcuts keep working. Open \(AppInfo.name) from the Applications "
                          + "folder or Spotlight to get back to Settings — that is the only way in "
                          + "while the icon is hidden.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show a preview after each capture", isOn: $settings.showPreview)
                Picker("Corner", selection: $settings.previewCorner) {
                    ForEach(PreviewCorner.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                SliderRow(title: "Stays for", value: $settings.previewDuration,
                          range: 0...30, step: 1, readout: durationLabel)
                SliderRow(title: "Thumbnail size", value: $settings.previewSize,
                          range: 120...400, step: 10, readout: "\(Int(settings.previewSize)) pt")
            } header: {
                Text("Preview")
            } footer: {
                Text("How long the preview lingers is also how long the quick-action shortcuts stay active.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.showPreview)

            Section("Feedback") {
                Toggle("Play the shutter sound", isOn: $settings.playCaptureSound)
                Toggle("Show confirmations", isOn: $settings.showHUD)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        let outcome = LoginItem.setEnabled(newValue)
                        launchAtLogin = outcome.isEnabled
                        settings.launchAtLogin = launchAtLogin
                        // Only a refusal needs explaining; success speaks for itself.
                        loginItemProblem = {
                            switch outcome {
                            case .enabled, .disabled: nil
                            case .needsApproval: LoginItem.statusDescription
                            case .failed(let reason): reason
                            }
                        }()
                    }
                    // Disabled only where macOS genuinely will not register one — outside an
                    // Applications folder. Anywhere else the attempt is allowed to happen and
                    // report its own outcome, rather than being pre-emptively refused.
                    .disabled(!LoginItem.isAvailable)
            } footer: {
                if let loginItemProblem {
                    Label(loginItemProblem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if !LoginItem.isAvailable {
                    Label(LoginItem.statusDescription, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var durationLabel: String {
        settings.previewDuration <= 0 ? "Until dismissed" : "\(Int(settings.previewDuration)) seconds"
    }
}

// MARK: - Capture

private struct CapturePane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Saving") {
                Toggle("Save every capture automatically", isOn: $settings.autoSaveToDisk)
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(settings.saveDirectory.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section {
                TextField("Filename", text: $settings.filenameTemplate)
                LabeledContent("Example") {
                    Text(previewName)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("Filename")
            } footer: {
                Text(FilenameTemplate.tokens.map(\.token).joined(separator: "   "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Section("Options") {
                Toggle("Copy to the clipboard as well", isOn: $settings.autoCopyToClipboard)
                Toggle("Include the window shadow", isOn: $settings.includeWindowShadow)
                Toggle("Include the pointer", isOn: $settings.includeCursor)
                Picker("Delay", selection: $settings.captureDelay) {
                    Text("None").tag(0)
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }

            Section {
                Toggle("Remember recent captures", isOn: $settings.historyEnabled)
                Picker("Keep", selection: $settings.historyLimit) {
                    ForEach([10, 25, 50, 100], id: \.self) { Text("\($0) captures").tag($0) }
                }
                .disabled(!settings.historyEnabled)
            } header: {
                Text("History")
            } footer: {
                Text("Recent captures stay reachable from the menu bar after their preview is gone.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var previewName: String {
        var context = FilenameContext(appName: "Safari", pixelWidth: 1600, pixelHeight: 1000)
        context.modeName = "Screenshot"
        return FilenameTemplate.render(settings.filenameTemplate, context: context)
            + "." + settings.imageFormat.fileExtension
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}

// MARK: - Text recognition

private struct TextPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Line breaks", selection: $settings.lineBreakMode) {
                    ForEach(LineBreakMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Rejoin words split across a line break", isOn: $settings.dehyphenate)
                    .disabled(settings.lineBreakMode == .preserveLines)
                Toggle("Collapse repeated spaces", isOn: $settings.collapseWhitespace)
            } header: {
                Text("Layout")
            } footer: {
                Text(settings.lineBreakMode.explanation)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Quality", selection: $settings.recognitionLevel) {
                    ForEach(RecognitionLevelSetting.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Detect the language automatically", isOn: $settings.automaticLanguageDetection)
                Toggle("Correct with a language model", isOn: $settings.usesLanguageCorrection)
                Toggle("Sharpen small selections first", isOn: $settings.enhanceSmallSelections)
            } header: {
                Text("Recognition")
            } footer: {
                Text("Sharpening upscales anything under 600 px before reading it, which noticeably helps with small interface text.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Copy the text straight to the clipboard", isOn: $settings.autoCopyOCR)
                Toggle("Show the text first so I can edit it", isOn: $settings.showOCRReview)
                Toggle("Also keep the image, with its preview", isOn: $settings.keepOCRImage)
            } header: {
                Text("After reading")
            } footer: {
                Text("A text grab captures the selection in order to read it. Left off, that image "
                     + "is discarded once the text has been taken from it — nothing is previewed "
                     + "and no file is kept.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Quick actions

private struct QuickActionsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bindings: HotkeyBindings

    var body: some View {
        Form {
            Section {
                Picker("Listen", selection: $settings.quickActionActivation) {
                    ForEach(QuickActionActivation.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Hand them back as soon as I switch apps", isOn: $settings.releaseOnAppSwitch)
                    .disabled(settings.quickActionActivation != .global)
            } header: {
                Text("When shortcuts are active")
            } footer: {
                if settings.quickActionActivation == .global {
                    Label(
                        "While a preview is on screen these shortcuts belong to Snapper, so ⌘C in another app copies the screenshot instead. They are handed straight back when the preview goes away.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(QuickAction.allCases, id: \.self) { action in
                    QuickActionRow(action: action, bindings: bindings)
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Click a shortcut to record a new one. Esc cancels, Delete clears it back to the default.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct QuickActionRow: View {
    let action: QuickAction
    @ObservedObject var bindings: HotkeyBindings
    @State private var hotkey: Hotkey?
    @State private var enabled: Bool = true
    @State private var conflict: String?

    var body: some View {
        LabeledContent {
            ShortcutField(hotkey: $hotkey, isEnabled: enabled) { newValue in
                bindings.setHotkey(newValue, for: action)
                refreshConflict()
            }
        } label: {
            Toggle(action.title, isOn: $enabled)
                .onChange(of: enabled) { _, newValue in bindings.setEnabled(newValue, for: action) }
            if let conflict, enabled {
                Text("Also used by \(conflict)")
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            hotkey = bindings.hotkey(for: action)
            enabled = bindings.isEnabled(action)
            refreshConflict()
        }
    }

    private func refreshConflict() {
        conflict = bindings.conflict(with: bindings.hotkey(for: action), excludingQuick: action)
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var bindings: HotkeyBindings
    @ObservedObject private var registry = HotkeyRegistry.shared
    var onHotkeysChanged: () -> Void
    var onRunSetup: () -> Void
    @State private var showingKeyboardGuide = false
    /// Bumped after the guide closes, to re-read the system's table for the footer below.
    @State private var systemStateToken = 0

    var body: some View {
        Form {
            Section {
                ForEach(GlobalAction.allCases, id: \.self) { action in
                    GlobalShortcutRow(action: action, bindings: bindings,
                                      registry: registry, onHotkeysChanged: onHotkeysChanged)
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Click a shortcut to record a new one. Esc cancels, Delete clears it back to the default.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("macOS screenshot shortcuts") {
                    Button("Show Me How…") { showingKeyboardGuide = true }
                }
            } footer: {
                // Stated from the system's actual configuration rather than assumed, since these
                // are exactly the combinations people want to hand over to an app like this.
                if SystemShortcuts.screenshotShortcutsEnabled {
                    Text("macOS currently owns ⌘⇧3, ⌘⇧4 and ⌘⇧5. Turn one off there first, then record it here.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("⌘⇧3, ⌘⇧4 and ⌘⇧5 are switched off on this Mac, so you can record them here.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Restore the shipped shortcuts") {
                    Button("Reset All") {
                        bindings.resetToDefaults()
                        onHotkeysChanged()
                    }
                }
                LabeledContent("First-run setup") {
                    Button("Run Setup Again…") { onRunSetup() }
                }
            }
        }
        .formStyle(.grouped)
        .id(systemStateToken)
        .sheet(isPresented: $showingKeyboardGuide) {
            KeyboardSettingsGuide(
                rows: SystemShortcuts.screenshotRows(
                    for: GlobalAction.allCases.map { bindings.hotkey(for: $0) }),
                onOpenSettings: { PermissionsChecker.openKeyboardShortcutSettings() },
                verify: {
                    SystemShortcuts.settingsLabels(
                        toFreeUp: GlobalAction.allCases.map { bindings.hotkey(for: $0) })
                },
                onDone: {
                    showingKeyboardGuide = false
                    systemStateToken += 1
                },
                onCancel: {
                    showingKeyboardGuide = false
                    systemStateToken += 1
                }
            )
        }
    }
}

private struct GlobalShortcutRow: View {
    let action: GlobalAction
    @ObservedObject var bindings: HotkeyBindings
    @ObservedObject var registry: HotkeyRegistry
    var onHotkeysChanged: () -> Void
    @State private var hotkey: Hotkey?
    @State private var conflict: String?
    @State private var systemConflict: String?

    var body: some View {
        LabeledContent {
            ShortcutField(hotkey: $hotkey) { newValue in
                bindings.setHotkey(newValue, for: action)
                refresh()
                onHotkeysChanged()
            }
        } label: {
            Text(action.title)
            if let systemConflict {
                // macOS wins these silently, so the shortcut would look set but never fire.
                Text("macOS uses this for \(systemConflict) — turn that off first")
                    .foregroundStyle(.red)
            } else if registry.isUnavailable(action) {
                Text("Another app already owns this combination")
                    .foregroundStyle(.red)
            } else if let conflict {
                Text("Also used by \(conflict)")
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            hotkey = bindings.hotkey(for: action)
            refresh()
        }
    }

    private func refresh() {
        let current = bindings.hotkey(for: action)
        conflict = bindings.conflict(with: current, excludingGlobal: action)
        systemConflict = SystemShortcuts.conflict(with: current)
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var hasScreenRecording = PermissionsChecker.hasScreenRecordingAccess
    @State private var showingUninstall = SettingsDemo.opensUninstallSheet
    /// The pane's own checker. Separate from the delegate's, which only matters in that a check
    /// started here and one started from the menu bar are independent — both read and write the
    /// same stored timestamp and skipped version, so they stay consistent.
    @StateObject private var updates: UpdateChecker

    init(settings: SettingsStore) {
        self.settings = settings
        _updates = StateObject(wrappedValue: UpdateChecker(settings: settings))
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    // The bundle's own icon, which is what an About box is expected to show. Read
                    // from NSApp rather than by name so it still resolves outside a built bundle,
                    // where AppKit substitutes the generic application icon.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppInfo.name).font(.title2.weight(.semibold))
                        Text("Version \(AppInfo.version) (\(AppInfo.build))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.automaticUpdateChecks)
                Toggle("Include pre-releases", isOn: $settings.includePrereleaseUpdates)
                    .disabled(!settings.automaticUpdateChecks)

                LabeledContent("Last checked") {
                    HStack(spacing: 10) {
                        Text(lastCheckedLabel)
                            .foregroundStyle(.secondary)
                        if updates.isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Check Now") { check() }
                        }
                    }
                }

                if !updates.skippedVersion.isEmpty {
                    LabeledContent("Skipped") {
                        HStack(spacing: 10) {
                            Text(updates.skippedVersion).foregroundStyle(.secondary)
                            Button("Stop Skipping") { updates.clearSkippedVersion() }
                        }
                    }
                }

                LabeledContent("Releases") {
                    Link("View on GitHub", destination: AppInfo.releasesPageURL)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Snapper asks GitHub once a day whether a newer release has been published. "
                     + "Nothing is downloaded or installed without you choosing to.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Screen Recording") {
                    HStack(spacing: 6) {
                        Image(systemName: hasScreenRecording ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasScreenRecording ? .green : .orange)
                        Text(hasScreenRecording ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                    }
                }
                if !hasScreenRecording {
                    LabeledContent("Permission") {
                        HStack {
                            Button("Open System Settings") { PermissionsChecker.openScreenRecordingSettings() }
                            Button("Re-check") { hasScreenRecording = PermissionsChecker.hasScreenRecordingAccess }
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                if !hasScreenRecording {
                    Text("Without it, macOS will not let Snapper capture anything. A newly granted permission takes effect after the app is relaunched.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Remove \(AppInfo.name) and its data") {
                    Button("Uninstall…") { showingUninstall = true }
                }
            } header: {
                Text("Uninstall")
            } footer: {
                Text("Deletes the settings, capture history and caches, unregisters the login item "
                     + "and moves the app to the Trash. You are shown the full list first.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingUninstall) {
            UninstallSheet(
                onFinished: { showingUninstall = false },
                onCancel: { showingUninstall = false }
            )
        }
    }

    private var lastCheckedLabel: String {
        guard let date = updates.lastCheckedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Reports both outcomes, the same way the menu item does — a button that gives no answer
    /// leaves you wondering whether it did anything.
    private func check() {
        Task {
            switch await updates.check() {
            case .updateAvailable(let release):
                UpdatePresenter.presentAvailable(release, current: updates.currentVersion) {
                    updates.skip(release)
                }
            case .upToDate:
                UpdatePresenter.presentUpToDate(current: updates.currentVersion)
            case .failed(let error):
                UpdatePresenter.presentFailure(error)
            }
        }
    }
}
