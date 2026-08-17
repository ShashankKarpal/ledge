// Watch face complications: the Step mark, one tap into capture.
// Static by design: no counts, no data, no red, per the design bans.
// The watch app's root view IS CaptureView, so opening the app is the
// deep link; widgetURL carries ledge://capture for parity with iOS.
// Built by Claude (Anthropic).

import WidgetKit
import SwiftUI

struct WatchCaptureEntry: TimelineEntry {
    let date: Date
}

struct WatchCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchCaptureEntry {
        WatchCaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchCaptureEntry) -> Void) {
        completion(WatchCaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchCaptureEntry>) -> Void) {
        completion(Timeline(entries: [WatchCaptureEntry(date: .now)], policy: .never))
    }
}

/// The Step mark as a template image, tinted by the face.
private struct StepGlyph: View {
    let size: CGFloat
    var body: some View {
        Image("LedgeStep")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct WatchCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline renders a single line of text beside the time.
            Text("Capture to Ledge")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                StepGlyph(size: 17)
                Text("Capture to Ledge")
                    .font(.headline)
            }
        case .accessoryCorner:
            StepGlyph(size: 20)
                .widgetLabel { Text("Ledge") }
        default: // .accessoryCircular
            StepGlyph(size: 22)
        }
    }
}

struct WatchCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.shashankkarpal.ledge.watchcapturewidget",
            provider: WatchCaptureProvider()
        ) { _ in
            WatchCaptureWidgetView()
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "ledge://capture"))
        }
        .configurationDisplayName("Capture to Ledge")
        .description("Opens straight into capture.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct LedgeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchCaptureWidget()
    }
}
