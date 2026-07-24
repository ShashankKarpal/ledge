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

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.notice {
                noticeBanner(notice)
            }
            captureBar
            List {
                ForEach(model.inbox.days, id: \.day) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            EntryRow(entry: entry) {
                                editingEntry = entry
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
                await MainActor.run {
                    model.becameActive()
                }
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

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capture() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        model.capture(text: text)
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
