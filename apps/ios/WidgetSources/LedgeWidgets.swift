// A7: capture widgets and a Control Center control. Every surface opens
// straight into the inbox keyboard via the ledge://capture deep link.
// No data is read or shown: widgets stay calm, badge-free, and count-free.
// Built by Claude (Anthropic).

import WidgetKit
import SwiftUI
import AppIntents

struct CaptureEntry: TimelineEntry {
    let date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

/// The Step mark as a template image. Tinted by whatever context draws it,
/// so the Lock Screen gets the system tint and the Home Screen gets the rose.
private struct StepGlyph: View {
    let size: CGFloat
    var body: some View {
        Image("LedgeStep")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            StepGlyph(size: 22)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                StepGlyph(size: 17)
                Text("Capture to Ledge")
                    .font(.headline)
            }
        default:
            VStack(spacing: 8) {
                StepGlyph(size: 34)
                    .foregroundStyle(Color(red: 0.906, green: 0.533, blue: 0.573))
                Text("Capture a thought")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.shashankkarpal.ledge.capturewidget", provider: CaptureProvider()) { _ in
            CaptureWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "ledge://capture"))
        }
        .configurationDisplayName("Capture to Ledge")
        .description("Opens straight into the inbox keyboard.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct LaunchCaptureIntent: AppIntent {
    // Deliberately NOT titled "Capture to Ledge": that name belongs to the
    // spool-writing CaptureIntent in the app. Two identically named actions
    // made Siri and the Shortcuts app ambiguous about which one to run.
    // Hidden from discovery entirely; the Control Center button invokes it
    // directly and does not need Shortcuts to list it.
    static var title: LocalizedStringResource = "Open Ledge Capture"
    static var description = IntentDescription("Opens Ledge ready to capture a thought.")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "ledge://capture")!))
    }
}

struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.shashankkarpal.ledge.capturecontrol") {
            ControlWidgetButton(action: LaunchCaptureIntent()) {
                // ControlWidgetButton labels only accept SF Symbols, so this stays a
                // system symbol until the Step ships as a custom symbol.
                Label("Capture to Ledge", systemImage: "sidebar.right")
            }
        }
        .displayName("Capture to Ledge")
        .description("Opens straight into the inbox keyboard.")
    }
}

@main
struct LedgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureWidget()
        CaptureControl()
    }
}
