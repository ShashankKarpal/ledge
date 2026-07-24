// The whole watch app: type or dictate, send, see a brief checkmark.
// Queued transfers wait quietly; the line about them is muted, never alarmist.
// Built by Claude (Anthropic).

import SwiftUI

struct CaptureView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var text = ""
    @State private var sent = false

    // Done color from design tokens, dark variant (#A0D392); watch UI is dark.
    private let doneColor = Color(red: 160.0 / 255.0, green: 211.0 / 255.0, blue: 146.0 / 255.0)

    var body: some View {
        VStack(spacing: 10) {
            if sent {
                Image(systemName: "checkmark")
                    .font(.title2)
                    .foregroundColor(doneColor)
                Text("Captured")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                TextField("Thought", text: $text)
                    .onSubmit(send)
                Button("Capture", action: send)
                    .disabled(trimmed.isEmpty)
            }
            if session.outstandingCount > 0 {
                Text(waitingLine)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var waitingLine: String {
        session.outstandingCount == 1
            ? "1 waiting for iPhone"
            : "\(session.outstandingCount) waiting for iPhone"
    }

    private func send() {
        let thought = trimmed
        guard !thought.isEmpty else { return }
        session.send(thought)
        text = ""
        withAnimation(.easeOut(duration: 0.15)) {
            sent = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.25)) {
                sent = false
            }
        }
    }
}
