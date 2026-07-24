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
                        // Only when the saved folder stopped resolving: a quiet way back.
                        if !model.isConnected {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    showingRepicker = true
                                } label: {
                                    Image(systemName: "folder")
                                }
                            }
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
