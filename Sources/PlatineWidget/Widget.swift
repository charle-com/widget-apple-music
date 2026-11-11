import OSLog
import PlatineCore
import PlatineUI
import SwiftUI
import WidgetKit

/// Trace des demandes de timeline, pour voir si macOS honore les rechargements :
/// `log show --last 10m --predicate 'subsystem == "platine"'`
private let logger = Logger(subsystem: "platine", category: "widget")

/// Extension WidgetKit : lit l'état écrit par l'app et prépare une image par piste à venir.
@main
struct PlatineWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlatineWidget()
    }
}

struct PlatineEntry: TimelineEntry {
    let date: Date
    let frame: Frame
}

struct PlatineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlatineEntry {
        PlatineEntry(date: Date(), frame: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlatineEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(PlatineEntry(date: now, frame: .sample(at: now)))
            return
        }
        let frame = Planner.frames(for: SharedStore.load(), now: now)[0]
        completion(PlatineEntry(date: now, frame: frame))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlatineEntry>) -> Void) {
        let now = Date()
        let frames = Planner.frames(for: SharedStore.load(), now: now)
        let entries = frames.map { PlatineEntry(date: $0.date, frame: $0) }
        logger.notice("timeline : \(frames.count, privacy: .public) images, \(frames[0].isPlaying ? "lecture" : "pause", privacy: .public), \(frames[0].current?.title ?? "aucune piste", privacy: .public)")
        completion(Timeline(entries: entries, policy: .after(Planner.horizon(of: frames, now: now))))
    }
}

struct PlatineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlatineEntry

    private var size: PlatineSize {
        switch family {
        case .systemSmall: return .small
        case .systemLarge: return .large
        case .systemExtraLarge: return .extraLarge
        default: return .medium
        }
    }

    var body: some View {
        PlatineView(frame: entry.frame, size: size, live: true)
            .containerBackground(for: .widget) { PlatineBackground(frame: entry.frame) }
            .widgetURL(URL(string: "platine://open"))
    }
}

struct PlatineWidget: Widget {
    static let kind = "PlatineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PlatineProvider()) { entry in
            PlatineWidgetView(entry: entry)
        }
        .configurationDisplayName("Platine")
        .description("La piste en cours et la file d'attente d'Apple Music.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
