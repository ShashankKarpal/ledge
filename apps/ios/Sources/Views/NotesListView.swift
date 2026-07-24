// Named notes: a flat list plus a create-note alert, and the note editor.
// Built by Claude (Anthropic).

import SwiftUI
import LedgeCore

struct NotesListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var notes: [NoteMeta] = []
    @State private var showingCreate = false
    @State private var newTitle = ""

    var body: some View {
        List(notes) { note in
            NavigationLink {
                NoteEditorView(noteURL: note.url, fallbackTitle: note.title)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.body)
                        .foregroundColor(.ledgeText)
                        .lineLimit(1)
                    Text(EntryRow.relative(note.modified))
                        .font(.caption2)
                        .foregroundColor(.ledgeTextMuted)
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(Color.ledgeSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ledgeBg.ignoresSafeArea())
        .overlay {
            if notes.isEmpty {
                Text("No notes yet. Most thoughts belong in the inbox; notes are for the few that earn a name.")
                    .font(.footnote)
                    .foregroundColor(.ledgeTextMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newTitle = ""
                    showingCreate = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .alert("New note", isPresented: $showingCreate) {
            TextField("Title", text: $newTitle)
            Button("Create") {
                createNote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Notes are plain Markdown files in your Ledge folder.")
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        notes = model.listNotes()
    }

    private func createNote() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = model.createNote(title: title)
        reload()
    }
}

// MARK: - Note editor

struct NoteEditorView: View {
    @EnvironmentObject private var model: AppModel
    let noteURL: URL
    let fallbackTitle: String

    @State private var text = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .foregroundColor(.ledgeText)
            .scrollContentBackground(.hidden)
            .background(Color.ledgeBg.ignoresSafeArea())
            .padding(.horizontal, 8)
            .navigationTitle(fallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !loaded {
                    text = model.readNote(at: noteURL)
                    loaded = true
                }
            }
            .onChange(of: text) { _ in
                guard loaded else { return }
                saveTask?.cancel()
                saveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    model.writeNote(text, to: noteURL)
                }
            }
            .onDisappear {
                saveTask?.cancel()
                if loaded {
                    model.writeNote(text, to: noteURL)
                }
            }
    }
}
