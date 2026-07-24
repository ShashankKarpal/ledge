// First-run screen: one calm explanation, one action.
// Built by Claude (Anthropic).

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolderSetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.ledgeTextMuted)
            Text("Ledge")
                .font(.title2.weight(.semibold))
                .foregroundColor(.ledgeText)
            Text("Pick your Ledge folder. Create one in iCloud Drive to share with your Mac.")
                .font(.body)
                .foregroundColor(.ledgeTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingPicker = true
            } label: {
                Text("Choose folder")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ledgeAccent)
            if let notice = model.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundColor(.ledgeAttention)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ledgeBg.ignoresSafeArea())
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                model.connectFolder(url: url)
            }
        }
    }
}

/// UIDocumentPickerViewController wrapped for SwiftUI, folders only.
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        // Nothing to update.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }
            // Claim access before the model bookmarks it.
            _ = url.startAccessingSecurityScopedResource()
            onPick(url)
        }
    }
}
