import SwiftUI

/// Confirms an uninstall by listing what will go, then reports what actually happened.
///
/// A list rather than a yes/no alert: this removes a capture history that is not recoverable, and
/// "are you sure?" gives someone nothing to be sure about.
struct UninstallSheet: View {
    var onFinished: () -> Void
    var onCancel: () -> Void

    @State private var items: [Uninstaller.Item] = Uninstaller.plan()
    @State private var report: Uninstaller.Report?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if let report {
                    resultList(report)
                        .padding(20)
                } else {
                    plannedList
                        .padding(20)
                }
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 460)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: report == nil ? "trash" : "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(report == nil ? AnyShapeStyle(.red) : AnyShapeStyle(.green))
            VStack(alignment: .leading, spacing: 2) {
                Text(report == nil ? "Uninstall \(AppInfo.name)" : "\(AppInfo.name) removed")
                    .font(.headline)
                Text(report == nil
                     ? "Everything below is removed. Captures you never saved elsewhere cannot be recovered."
                     : "Here is what happened.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
    }

    private var plannedList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: item.exists ? "trash.fill" : "minus")
                        .font(.system(size: 11))
                        .foregroundStyle(item.exists ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label)
                            .font(.callout)
                            .foregroundStyle(item.exists ? .primary : .secondary)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func resultList(_ report: Uninstaller.Report) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !report.removed.isEmpty {
                group("Removed", report.removed, icon: "checkmark", tint: .green)
            }
            if !report.failed.isEmpty {
                group("Could not be removed", report.failed, icon: "xmark", tint: .red)
            }
            if !report.manual.isEmpty {
                group("Left for you to finish", report.manual,
                      icon: "exclamationmark.triangle", tint: .orange)
            }
        }
    }

    private func group(_ title: String, _ lines: [String],
                       icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 14)
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if report == nil {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Remove Everything") { report = Uninstaller.removeEverything() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                // Quitting is not optional: the settings have been cleared, and a normal shutdown
                // would write this session's copy of them straight back.
                Button("Quit \(AppInfo.name)") {
                    onFinished()
                    Uninstaller.quit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
