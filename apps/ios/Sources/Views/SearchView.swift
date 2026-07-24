// Vague-memory search over inbox, notes, and the Attic.
// Built by Claude (Anthropic).

import SwiftUI
import LedgeCore

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var hits: [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return model.search(trimmed)
    }

    var body: some View {
        List(hits) { hit in
            if isNote(hit) {
                NavigationLink {
                    NoteEditorView(noteURL: hit.fileURL, fallbackTitle: hit.title)
                } label: {
                    SearchRow(hit: hit)
                }
                .listRowBackground(Color.ledgeSurface)
            } else {
                // Inbox and Attic hits: the inbox is one screen away, keep it simple.
                Button {
                    dismiss()
                } label: {
                    SearchRow(hit: hit)
                }
                .listRowBackground(Color.ledgeSurface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ledgeBg.ignoresSafeArea())
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search everything"
        )
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isNote(_ hit: SearchHit) -> Bool {
        hit.fileURL.deletingLastPathComponent().lastPathComponent == "notes"
    }
}

struct SearchRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.ledgeText)
                .lineLimit(1)
            if !hit.snippet.isEmpty {
                Text(hit.snippet)
                    .font(.footnote)
                    .foregroundColor(.ledgeTextMuted)
                    .lineLimit(2)
            }
            if let when = hit.when {
                Text(EntryRow.relative(when))
                    .font(.caption2)
                    .foregroundColor(.ledgeAged)
            }
        }
        .padding(.vertical, 2)
    }
}
