import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var model: SetupModel
    @State private var showingKeyboardGuide = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    permissionStep
                    shortcutStep
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 480)
        .onAppear {
            if model.opensGuideImmediately { showingKeyboardGuide = true }
        }
        .sheet(isPresented: $showingKeyboardGuide) {
            KeyboardSettingsGuide(
                rows: model.screenshotRows,
                onOpenSettings: { PermissionsChecker.openKeyboardShortcutSettings() },
                verify: { model.verifyShortcutsFreed() },
                onDone: { showingKeyboardGuide = false },
                onCancel: {
                    // Whatever was changed while it was open still counts.
                    model.refresh()
                    showingKeyboardGuide = false
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to \(AppInfo.name)")
                    .font(.title2.weight(.semibold))
                Text("Two things to check. You can skip either and change them later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Step 1

    private var permissionStep: some View {
        StepCard(
            number: 1,
            title: "Screen Recording",
            isDone: model.hasScreenRecording,
            doneLabel: "Granted"
        ) {
            Text("macOS will not let any app capture the screen without this. Snapper cannot take a screenshot until it is granted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.hasScreenRecording {
                HStack {
                    Button("Open System Settings") { model.requestScreenRecording() }
                        .buttonStyle(.borderedProminent)
                    Button("Re-check") { model.refresh() }
                    // A granted permission does not apply to the running process, so "Re-check"
                    // keeps saying no until the app restarts. Offering the restart here means nobody
                    // has to work that out, or quit by hand and hope setup comes back.
                    Button("Quit & Reopen") { model.relaunch() }
                }
                Text("Enable Snapper under Privacy & Security → Screen & System Audio Recording. "
                     + "macOS only applies it to a new launch, so use Quit & Reopen afterwards — "
                     + "setup picks up where it left off.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Step 2

    private var shortcutStep: some View {
        StepCard(
            number: 2,
            title: "Keyboard shortcuts",
            isDone: model.shortcutsAreClear,
            doneLabel: "Clear"
        ) {
            Text("Snapper captures with ⌘⇧3, ⌘⇧4 and ⌘⇧5 — the same combinations macOS uses for its own screenshots. While macOS still owns them it handles them first, and Snapper never sees the keystroke.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.shortcutsAreClear {
                Text("Nothing is in the way — these are free on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.blocked, id: \.0) { action, owner in
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(action.title).font(.callout)
                            Spacer()
                            Text(owner)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))

                Text("Snapper does not change these for you — rewriting the system's shortcut settings is unreliable and can disturb your other shortcuts. Show Me How walks through it and checks the result.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Show Me How…") { showingKeyboardGuide = true }
                        .buttonStyle(.borderedProminent)
                        .help("Which pane to open, which entries to switch off, and a check that it worked")
                    Button("Re-check") { model.refresh() }
                    Spacer()
                    Button("Use ⌥⌘ instead") { model.useAlternativeShortcuts() }
                        .help("Rebinds Snapper to ⌥⌘3, ⌥⌘4 and ⌥⌘5, which macOS does not use")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.hasScreenRecording && model.shortcutsAreClear
                 ? "All set."
                 : "You can finish this later from the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.hasScreenRecording && model.shortcutsAreClear ? "Done" : "Skip for Now") {
                model.onClose?()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

/// One numbered step, with a tick once it no longer needs attention.
private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let isDone: Bool
    let doneLabel: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(isDone ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 20, height: 20)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(title).font(.headline)
                if isDone {
                    Text(doneLabel)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.leading, 29)
        }
    }
}
