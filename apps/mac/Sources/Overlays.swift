// Search, Open Loops, and Notes as SwiftUI overlays inside the AppKit panel.
// Calm lists: no counts on icons, no red, age fades. Built by Claude (Anthropic).

import SwiftUI
#if canImport(LedgeCore)
import LedgeCore
#endif

private let relative: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

private func relativeLabel(_ date: Date?) -> String {
    guard let date else { return "" }
    return relative.localizedString(for: date, relativeTo: Date())
}

// MARK: Search

struct SearchOverlay: View {
    let store: LedgeStore
    let currentInbox: () -> Inbox
    let onOpenNote: (URL) -> Void
    let onRevealInbox: (String) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private var hits: [SearchHit] {
        query.isEmpty ? [] : store.search(query, inbox: currentInbox())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search everything, vaguely is fine", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: Theme.surface2)))

            if query.isEmpty {
                Text("Recency-weighted and typo-tolerant. Inbox, notes, and the Attic.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: Theme.textAged))
            } else if hits.isEmpty {
                Text("Nothing yet. Fewer or looser words often help.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: Theme.textMuted))
            }

            List(hits) { hit in
                Button {
                    if hit.fileURL == store.inboxURL {
                        onRevealInbox(hit.snippet)
                    } else if hit.fileURL.path.contains("/attic/") {
                        onOpenNote(hit.fileURL)
                    } else {
                        onOpenNote(hit.fileURL)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(nsColor: Theme.textMuted))
                        Text(hit.snippet)
                            .font(.system(size: 13))
                            .foregroundColor(Color(nsColor: Theme.text))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onAppear { focused = true }
    }
}

// MARK: Open Loops

struct LoopsOverlay: View {
    let store: LedgeStore
    let currentInbox: () -> Inbox
    let onComplete: (OpenLoop) -> Void
    let onJump: (OpenLoop) -> Void

    @State private var refresh = UUID()

    private var loops: [OpenLoop] {
        _ = refresh
        return store.openLoops(inbox: currentInbox())
    }

    private func bucket(_ loop: OpenLoop) -> String {
        guard let when = loop.when else { return "Older" }
        return when > Date().addingTimeInterval(-7 * 86_400) ? "This week" : "Older"
    }

    var body: some View {
        let all = loops
        let thisWeek = all.filter { bucket($0) == "This week" }
        let older = all.filter { bucket($0) == "Older" }

        return VStack(alignment: .leading, spacing: 8) {
            Text(headline(count: all.count, recent: thisWeek.count))
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: Theme.textMuted))

            List {
                if !thisWeek.isEmpty {
                    Section(header: sectionHeader("This week")) {
                        ForEach(thisWeek) { loop in row(loop) }
                    }
                }
                if !older.isEmpty {
                    Section(header: sectionHeader("Older, no judgment")) {
                        ForEach(older) { loop in row(loop) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func headline(count: Int, recent: Int) -> String {
        if count == 0 { return "No open loops. Nothing is waiting on you here." }
        if count == 1 { return "One open loop." }
        return "\(count) open loops, \(recent) from this week."
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(nsColor: Theme.textAged))
    }

    private func row(_ loop: OpenLoop) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                onComplete(loop)
                refresh = UUID()
            } label: {
                Image(systemName: "square")
                    .foregroundColor(Color(nsColor: Theme.accent))
            }
            .buttonStyle(.plain)

            Button {
                onJump(loop)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(loop.text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(nsColor: Theme.text))
                        .lineLimit(2)
                    Text(loop.sourceLabel + " · " + relativeLabel(loop.when))
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: Theme.textAged))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Morning Ledge

/// First summon of the day: where you left off, calmly. No badges, no red,
/// one click to start writing instead.
struct MorningOverlay: View {
    let store: LedgeStore
    let currentInbox: () -> Inbox
    let onComplete: (OpenLoop) -> Void
    let onJump: (OpenLoop) -> Void
    let onStart: () -> Void

    @State private var refresh = UUID()

    private var loops: [OpenLoop] {
        _ = refresh
        return store.openLoops(inbox: currentInbox())
    }

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private var startOfYesterday: Date { startOfToday.addingTimeInterval(-86_400) }

    private func isFromYesterday(_ loop: OpenLoop) -> Bool {
        guard let when = loop.when else { return false }
        return when >= startOfYesterday && when < startOfToday
    }

    var body: some View {
        let all = loops
        let yesterday = all.filter { isFromYesterday($0) }
        let earlier = all.filter { !isFromYesterday($0) }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Where you left off. Nothing here is urgent.")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: Theme.textMuted))

            List {
                if !yesterday.isEmpty {
                    Section(header: sectionHeader("From yesterday")) {
                        ForEach(yesterday) { loop in row(loop) }
                    }
                }
                if !earlier.isEmpty {
                    Section(header: sectionHeader("Still open, no judgment")) {
                        ForEach(earlier) { loop in row(loop) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                Button("Start writing") { onStart() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(nsColor: Theme.accent))
                Spacer()
                Text("Esc closes this")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: Theme.textAged))
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(nsColor: Theme.textAged))
    }

    private func row(_ loop: OpenLoop) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                onComplete(loop)
                refresh = UUID()
            } label: {
                Image(systemName: "square")
                    .foregroundColor(Color(nsColor: Theme.accent))
            }
            .buttonStyle(.plain)

            Button {
                onJump(loop)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(loop.text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(nsColor: Theme.text))
                        .lineLimit(2)
                    Text(loop.sourceLabel + " · " + relativeLabel(loop.when))
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: Theme.textAged))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Notes

struct NotesOverlay: View {
    let store: LedgeStore
    let onOpen: (URL) -> Void
    let onNew: () -> Void

    private var notes: [NoteMeta] {
        (try? store.listNotes()) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(notes.isEmpty ? "No named notes yet. The inbox is enough until it is not." : "Newest first.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: Theme.textMuted))
                Spacer()
                Button("New (⌘N)") { onNew() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(nsColor: Theme.accent))
            }

            List(notes) { note in
                Button {
                    onOpen(note.url)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(.system(size: 13))
                            .foregroundColor(Color(nsColor: Theme.text))
                        Text(relativeLabel(note.modified))
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: Theme.textAged))
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
