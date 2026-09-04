// The inbox: capture bar pinned on top, day sections newest first,
// tappable checkboxes, tap an entry to edit it in a sheet.
// Built by Claude (Anthropic).

import SwiftUI
import LedgeCore

struct InboxView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var justCaptured = false
    @State private var editingEntry: Entry?
    @FocusState private var captureFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let fault = model.fault {
                // The blocking card (brief item M1/M3): one cause, one message,
                // one button that is the fix for that cause and no other.
                faultCard(fault)
            } else if let notice = model.notice {
                noticeBanner(notice)
            }
            captureBar
            // Muted lines under the capture bar. Each is nil in the healthy
            // case, so a healthy inbox shows nothing here (the no-badges rule).
            if let outcome = model.refreshOutcome {
                mutedLine(outcome)
            }
            if let waiting = model.waitingLine {
                // Capture trust: appears only while a capture is stuck outside the inbox.
                mutedLine(waiting)
            }
            if let peer = model.peerLine {
                // Sync health (M4): another device has not been heard from in hours.
                mutedLine(peer)
            }
            List {
                if !model.inbox.preamble.isEmpty {
                    // Text the parser could not file under a day. It used to be
                    // invisible here while the Mac showed it as normal content
                    // (incident 2026-09-03). Nothing in the file may be hidden.
                    Section {
                        Text(model.inbox.preamble)
                            .font(.body)
                            .foregroundColor(.ledgeText)
                            .listRowBackground(Color.ledgeSurface)
                    } header: {
                        Text("Unfiled text")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.ledgeTextMuted)
                            .textCase(nil)
                    }
                }
                ForEach(model.inbox.days, id: \.day) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            EntryRow(entry: entry) {
                                editingEntry = entry
                            }
                            .contextMenu {
                                ShareLink(item: entry.text) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    UIPasteboard.general.string = Self.markdownBlock(for: entry)
                                } label: {
                                    Label("Copy as Markdown", systemImage: "doc.on.doc")
                                }
                                Button {
                                    model.sendToReminders(entry)
                                } label: {
                                    Label("Send to Reminders", systemImage: "checklist")
                                }
                            }
                        }
                    } header: {
                        Text(Self.dayTitle(day))
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.ledgeTextMuted)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable {
                // Same path as the toolbar button, so a pull also reports an outcome.
                await model.refreshNow()
            }
        }
        .background(Color.ledgeBg.ignoresSafeArea())
        .sheet(item: $editingEntry) { entry in
            EntryEditor(entry: entry)
                .environmentObject(model)
        }
    }

    // MARK: Capture bar

    private var captureBar: some View {
        HStack(spacing: 8) {
            TextField("Capture a thought", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($captureFocused)
                .onReceive(NotificationCenter.default.publisher(for: .ledgeFocusCapture)) { _ in
                    captureFocused = true
                }
                .foregroundColor(.ledgeText)
                .onSubmit(capture)
            Button(action: capture) {
                Image(systemName: justCaptured ? "checkmark" : "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundColor(justCaptured ? .ledgeDone : .ledgeAccent)
            }
            .buttonStyle(.plain)
            .disabled(trimmedDraft.isEmpty && !justCaptured)
        }
        .padding(12)
        .background(Color.ledgeSurface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// A6: the exact on-disk representation of one entry, ready to paste.
    static func markdownBlock(for entry: Entry) -> String {
        var header = "### " + LedgeFormat.timeFormatter.string(from: entry.timestamp)
        if let device = entry.device, !device.isEmpty {
            header += " · " + device
        }
        return header + "\n\n" + entry.text
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capture() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        model.capture(text: text)
        // Keep the text in the field when nothing durable was written. The
        // checkmark plus a cleared field told the user their thought was safe
        // even when it had reached nowhere (review 2026-09-03).
        guard model.lastCaptureLanded else { return }
        draft = ""
        withAnimation(.easeOut(duration: 0.15)) {
            justCaptured = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.25)) {
                justCaptured = false
            }
        }
    }

    // MARK: Sync fault card and muted lines

    private func faultCard(_ fault: SyncFault) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fault.message)
                .font(.footnote)
                .foregroundColor(.ledgeAttention)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task {
                    if await model.performFaultAction() {
                        NotificationCenter.default.post(name: .ledgeShowRepicker, object: nil)
                    }
                }
            } label: {
                if model.refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text(fault.actionTitle)
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.refreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.ledgeSurface)
    }

    private func mutedLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.ledgeTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
    }

    // MARK: Banner

    private func noticeBanner(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.ledgeAttention)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.ledgeSurface)
    }

    // MARK: Day titles

    static func dayTitle(_ day: DaySection) -> String {
        guard let date = day.date else { return day.day }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return headerFormatter.string(from: date)
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()
}

// MARK: - Entry row

struct EntryRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: Entry
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.relative(entry.timestamp) + (entry.device.map { " · " + $0 } ?? ""))
                .font(.caption2)
                .foregroundColor(.ledgeTextMuted)
            ForEach(Array(entry.text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                if LedgeStore.isOpenCheckbox(line) || AppModel.isClosedCheckbox(line) {
                    checkboxRow(line: line, index: index)
                } else {
                    Text(line.isEmpty ? " " : line)
                        .font(.body)
                        .foregroundColor(.ledgeText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .listRowBackground(Color.ledgeSurface)
    }

    private func checkboxRow(line: String, index: Int) -> some View {
        let done = AppModel.isClosedCheckbox(line)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                model.toggleCheckbox(in: entry, lineIndex: index)
            } label: {
                Image(systemName: done ? "checkmark.square" : "square")
                    .foregroundColor(done ? .ledgeDone : .ledgeTextMuted)
            }
            .buttonStyle(.borderless)
            Text(LedgeStore.taskText(line))
                .font(.body)
                .foregroundColor(done ? .ledgeTextMuted : .ledgeText)
                .strikethrough(done, color: .ledgeTextMuted)
            Spacer(minLength: 0)
        }
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

// MARK: - Entry editor sheet

struct EntryEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: Entry
    @State private var text: String

    init(entry: Entry) {
        self.original = entry
        self._text = State(initialValue: entry.text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.ledgeText)
                .scrollContentBackground(.hidden)
                .background(Color.ledgeBg)
                .padding(.horizontal, 8)
                .navigationTitle(timeLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .onDisappear {
            // Save on dismiss, however the sheet was closed.
            model.updateEntry(original: original, newText: text)
        }
    }

    private var timeLabel: String {
        LedgeFormat.spoolFormatter.string(from: original.timestamp)
    }
}
