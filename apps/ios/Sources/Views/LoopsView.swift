// Open loops: every unchecked checkbox, pull not push. No counts on icons,
// no badges, no overdue markers. The Attic rests.
// Built by Claude (Anthropic).

import SwiftUI
import LedgeCore

struct LoopsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let loops = model.openLoops()
        let split = Self.split(loops)

        List {
            Section {
                if split.thisWeek.isEmpty {
                    Text("Nothing open from this week.")
                        .font(.footnote)
                        .foregroundColor(.ledgeTextMuted)
                        .listRowBackground(Color.ledgeSurface)
                } else {
                    ForEach(split.thisWeek) { loop in
                        LoopRow(loop: loop)
                    }
                }
            } header: {
                Text(Self.headline(count: split.thisWeek.count))
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.ledgeTextMuted)
                    .textCase(nil)
            }

            if !split.older.isEmpty {
                Section {
                    ForEach(split.older) { loop in
                        LoopRow(loop: loop)
                    }
                } header: {
                    Text("Older")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.ledgeTextMuted)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ledgeBg.ignoresSafeArea())
        .navigationTitle("Open loops")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func split(_ loops: [OpenLoop]) -> (thisWeek: [OpenLoop], older: [OpenLoop]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var thisWeek: [OpenLoop] = []
        var older: [OpenLoop] = []
        for loop in loops {
            if let when = loop.when, when >= cutoff {
                thisWeek.append(loop)
            } else {
                older.append(loop)
            }
        }
        return (thisWeek, older)
    }

    static func headline(count: Int) -> String {
        switch count {
        case 0: return "This week"
        case 1: return "1 open loop from this week"
        default: return "\(count) open loops from this week"
        }
    }
}

struct LoopRow: View {
    let loop: OpenLoop

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loop.text)
                .font(.body)
                .foregroundColor(.ledgeText)
            Text(loop.sourceLabel)
                .font(.caption2)
                .foregroundColor(.ledgeTextMuted)
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.ledgeSurface)
    }
}
