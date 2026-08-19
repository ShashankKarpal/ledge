// Root switch: folder setup on first run, otherwise the inbox with minimal chrome.
// Built by Claude (Anthropic).

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingRepicker = false

    var body: some View {
        if !model.hasFolder {
            FolderSetupView()
        } else {
            NavigationStack {
                InboxView()
                    .navigationTitle("Ledge")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            NavigationLink {
                                SearchView()
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            NavigationLink {
                                NotesListView()
                            } label: {
                                Image(systemName: "doc.text")
                            }
                            NavigationLink {
                                LoopsView()
                            } label: {
                                Image(systemName: "circle.dashed")
                            }
                        }
                        // Always available: change or re-pick the notes folder.
                        // A reinstall can kill the bookmark while the app still
                        // believes it is connected, so this must never be gated
                        // on connection state (learned 2026-08-19).
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                showingRepicker = true
                            } label: {
                                Image(systemName: model.isConnected ? "folder" : "folder.badge.questionmark")
                            }
                            .accessibilityLabel("Change notes folder")
                        }
                    }
                    .sheet(isPresented: $showingRepicker) {
                        FolderPicker { url in
                            model.connectFolder(url: url)
                        }
                    }
            }
        }
    }
}
