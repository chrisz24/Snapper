import SwiftUI

/// What to do in System Settings to hand a macOS screenshot shortcut over to Snapper, plus a Done
/// button that checks the result rather than taking it on trust.
///
/// The deep link can open the Keyboard Shortcuts sheet but cannot select a category inside it. The
/// Keyboard settings extension declares URL anchors only for Modifier Keys, Function Keys,
/// Presenter Overlay and Windows, so a `Shortcuts` anchor resolves to nothing and the sheet opens
/// on whichever category was last used — usually Modifier Keys. Dropping someone into the wrong
/// pane with no explanation is worse than telling them which one to click, so the instructions
/// carry the deep link rather than replacing it.
struct KeyboardSettingsGuide: View {
    /// Every row of the Screenshots pane, in the order System Settings lists them.
    let rows: [SystemShortcuts.ScreenshotRow]
    var onOpenSettings: () -> Void
    /// Re-reads the system's shortcut table and returns whatever macOS still owns. Empty means done.
    var verify: () -> [String]
    var onDone: () -> Void
    var onCancel: () -> Void

    @State private var stillOwned: [String] = []
    @State private var showingNotDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { steps }
                    .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 545)
        .alert("Still switched on", isPresented: $showingNotDone) {
            Button("Open Keyboard Settings") { onOpenSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(notDoneMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free up the macOS screenshot shortcuts")
                    .font(.headline)
                Text("macOS handles these first, so Snapper never sees the keystroke until they are switched off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var steps: some View {
        GuideStep(number: 1, text: "Click **Open Keyboard Settings** below. macOS opens Keyboard → Keyboard Shortcuts.")

        GuideStep(number: 2, text: "Choose **Screenshots** in the sidebar. That sheet opens on whichever category you last used — often Modifier Keys — and macOS provides no way to send you straight to Screenshots, so this step is by hand.")

        GuideStep(number: 3, text: step3Text) {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    // The whole pane, in its own order, so it can be read side by side with the
                    // real thing — including the rows to leave alone.
                    ForEach(rows) { row in RowLine(row: row) }
                }
                .padding(11)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }

        GuideStep(number: 4, text: "Come back here and press **Done**. Snapper re-reads the system's shortcut table and says so if anything is still switched on.")
    }

    private var step3Text: String {
        let outstanding = rows.filter { $0.blocksSnapper && $0.isEnabled }.count
        guard outstanding > 0 else {
            return "Nothing left to switch off here — every row Snapper needs is already off."
        }
        let subject = outstanding == 1 ? "the row" : "the \(outstanding) rows"
        return "Switch off \(subject) marked below. The rest are not Snapper shortcuts, so leave them as they are:"
    }

    private var footer: some View {
        HStack {
            Button("Open Keyboard Settings") { onOpenSettings() }
                .buttonStyle(.borderedProminent)
            Spacer()
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { checkAndFinish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    /// Verifies rather than assuming: someone can close the sheet without changing anything, or
    /// switch off the wrong row, and either way the shortcut stays silently dead.
    private func checkAndFinish() {
        let remaining = verify()
        if remaining.isEmpty {
            onDone()
        } else {
            stillOwned = remaining
            showingNotDone = true
        }
    }

    private var notDoneMessage: String {
        let list = stillOwned.map { "“\($0)”" }.formatted(.list(type: .and))
        let subject = stillOwned.count == 1 ? "is" : "are"
        return "\(list) \(subject) still switched on in Keyboard Shortcuts → Screenshots, "
             + "so macOS keeps handling that keystroke. Switch it off there and press Done again — "
             + "or close this and use ⌥⌘ shortcuts instead."
    }
}

/// One row of the Screenshots pane: what to do to it, or that there is nothing to do.
private struct RowLine: View {
    let row: SystemShortcuts.ScreenshotRow

    var body: some View {
        HStack(spacing: 8) {
            marks
                .frame(width: 54, alignment: .leading)
            Text(row.label)
                .font(.callout)
                .foregroundStyle(row.blocksSnapper ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(note)
                .font(.caption)
                .foregroundStyle(row.blocksSnapper && row.isEnabled ? .secondary : .tertiary)
                .fixedSize()
        }
        .font(.system(size: 14))
        .symbolRenderingMode(.hierarchical)
    }

    /// Ticked → unticked for a row to change, and a single box for one to leave, so the action is
    /// legible from the glyphs alone rather than only from the note beside them.
    @ViewBuilder
    private var marks: some View {
        if row.blocksSnapper && row.isEnabled {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.square.fill").foregroundStyle(.tint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Image(systemName: "square").foregroundStyle(.secondary)
            }
        } else if row.blocksSnapper {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            // Nothing to do to this one, so it just mirrors however it currently stands.
            Image(systemName: row.isEnabled ? "checkmark.square.fill" : "square")
                .foregroundStyle(.tertiary)
        }
    }

    private var note: String {
        if row.blocksSnapper && row.isEnabled { "switch off" }
        else if row.blocksSnapper { "already off" }
        else { "leave as is" }
    }
}

/// One numbered instruction, with room for content underneath it.
private struct GuideStep<Content: View>: View {
    let number: Int
    let text: String
    @ViewBuilder var content: Content

    init(number: Int, text: String, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.number = number
        self.text = text
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 20, height: 20)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                // Markdown so the interface elements being named stand out from the prose.
                Text(LocalizedStringKey(text))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            Spacer(minLength: 0)
        }
    }
}
