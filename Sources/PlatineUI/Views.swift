import AppKit
import PlatineCore
import SwiftUI
import WidgetKit

/// Tailles de widget prises en charge, indépendantes de WidgetKit pour que l'app puisse rendre un aperçu.
public enum PlatineSize: String, CaseIterable {
    case small, medium, large, extraLarge
}

// MARK: - Réglages par taille

private struct Metrics {
    var padding: CGFloat
    var gap: CGFloat
    var title: CGFloat
    var artist: CGFloat
    var thumb: CGFloat
    var rowTitle: CGFloat
    var rowArtist: CGFloat
    var rowGap: CGFloat
    var header: CGFloat
    var panelPadding: CGFloat
    var panelRadius: CGFloat
    var showTimes: Bool
    var showDurations: Bool

    static func of(_ size: PlatineSize) -> Metrics {
        switch size {
        case .small:
            return Metrics(padding: 13, gap: 8, title: 12.5, artist: 11, thumb: 0, rowTitle: 0, rowArtist: 0, rowGap: 0,
                           header: 0, panelPadding: 0, panelRadius: 0, showTimes: false, showDurations: false)
        case .medium:
            return Metrics(padding: 12, gap: 11, title: 12.5, artist: 11, thumb: 24, rowTitle: 11, rowArtist: 9.5, rowGap: 5,
                           header: 8.5, panelPadding: 9, panelRadius: 15, showTimes: false, showDurations: false)
        case .large:
            return Metrics(padding: 14, gap: 12, title: 15, artist: 12.5, thumb: 32, rowTitle: 12.5, rowArtist: 11, rowGap: 8,
                           header: 9.5, panelPadding: 12, panelRadius: 18, showTimes: true, showDurations: true)
        case .extraLarge:
            return Metrics(padding: 16, gap: 16, title: 17, artist: 13.5, thumb: 36, rowTitle: 13, rowArtist: 11.5, rowGap: 8,
                           header: 10, panelPadding: 14, panelRadius: 20, showTimes: true, showDurations: true)
        }
    }
}

// MARK: - Pochettes

enum ArtLoader {
    static func image(_ key: String?, _ size: SharedStore.ArtSize) -> NSImage? {
        guard let key else { return nil }
        return NSImage(contentsOf: SharedStore.artURL(key: key, size: size))
    }
}

private struct ArtworkView: View {
    let track: Track?
    let size: SharedStore.ArtSize
    let side: CGFloat

    var body: some View {
        let radius = max(5, side * 0.115)
        Group {
            if let image = ArtLoader.image(track?.artKey, size) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.10)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.42, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.6))
        .shadow(color: .black.opacity(side > 60 ? 0.32 : 0.18), radius: side > 60 ? 9 : 3, y: side > 60 ? 5 : 1.5)
    }
}

// MARK: - Fond et verre

/// Fond du widget : la pochette en cours, floutée d'avance par l'app, sous un voile sombre pour la lisibilité.
public struct PlatineBackground: View {
    let frame: Frame

    public init(frame: Frame) { self.frame = frame }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.33, green: 0.20, blue: 0.50), Color(red: 0.09, green: 0.10, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image = ArtLoader.image(frame.current?.artKey, .background) {
                Color.clear.overlay(
                    Image(nsImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                )
                .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.14), .black.opacity(0.46)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct Glass: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                shape
                    .fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.09)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.10), .white.opacity(0.30)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8)
            )
    }
}

private extension View {
    func glass(_ radius: CGFloat) -> some View { modifier(Glass(radius: radius)) }
}

// MARK: - Progression

private func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

private struct ProgressSection: View {
    let frame: Frame
    let live: Bool
    let showTimes: Bool

    private var staticFraction: Double {
        if frame.isPlaying, let s = frame.start, let e = frame.end, e > s {
            return min(1, max(0, frame.date.timeIntervalSince(s) / e.timeIntervalSince(s)))
        }
        return frame.fraction
    }

    var body: some View {
        VStack(spacing: 4) {
            if live, frame.isPlaying, let s = frame.start, let e = frame.end, e > s {
                // Seul le style système s'anime tout seul dans un widget, sans rechargement.
                ProgressView(timerInterval: s...e, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.linear)
                    .tint(.white)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.24))
                        Capsule().fill(.white).frame(width: max(4, geo.size.width * staticFraction))
                    }
                }
                .frame(height: 4)
            }
            if showTimes, let duration = frame.current?.duration, duration > 0 {
                HStack {
                    if live, frame.isPlaying, let s = frame.start, let e = frame.end, e > s {
                        Text(timerInterval: s...e, countsDown: false)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(clock(staticFraction * duration))
                    }
                    Spacer(minLength: 4)
                    Text(clock(duration))
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.62))
            }
        }
    }
}

// MARK: - Boutons de lecture

/// Précédent, lecture ou pause, suivant. Chaque bouton est un lien vers l'app hôte (`platine://<commande>`),
/// qui transmet la commande à Musique : c'est ce qu'un widget sait cliquer sans projet Xcode.
private struct Controls: View {
    let isPlaying: Bool
    /// Taille de l'icône centrale, les deux autres sont un peu plus petites.
    let size: CGFloat
    /// Faux pour l'aperçu rendu en image : `ImageRenderer` ne sait pas dessiner un `Link`.
    let live: Bool

    var body: some View {
        HStack(spacing: size * 0.35) {
            control("previous", "backward.fill", size * 0.80)
            control(isPlaying ? "pause" : "play", isPlaying ? "pause.fill" : "play.fill", size)
            control("next", "forward.fill", size * 0.80)
        }
    }

    @ViewBuilder
    private func control(_ command: String, _ symbol: String, _ pointSize: CGFloat) -> some View {
        let label = Image(systemName: symbol)
            .font(.system(size: pointSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size * 1.75, height: size * 1.6)
            .contentShape(Rectangle())
        if live {
            Link(destination: URL(string: "platine://\(command)")!) { label }
        } else {
            label
        }
    }
}

/// Les mêmes boutons dans une pastille de verre sombre, à poser sur la pochette quand la place manque.
private struct ControlsPill: View {
    let isPlaying: Bool
    let size: CGFloat
    let live: Bool

    var body: some View {
        Controls(isPlaying: isPlaying, size: size, live: live)
            .padding(.horizontal, size * 0.3)
            .background(Capsule().fill(.black.opacity(0.46)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .padding(.bottom, size * 0.5)
    }
}

// MARK: - Piste en cours

private struct PausedBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "pause.fill").font(.system(size: 7, weight: .bold))
            Text("En pause").font(.system(size: 8.5, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.48)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
        .padding(5)
    }
}

private struct TrackTitles: View {
    let track: Track
    let m: Metrics
    var showAlbum = false
    var titleLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(track.title)
                .font(.system(size: m.title, weight: .semibold))
                .lineLimit(titleLines)
            Text(track.artist)
                .font(.system(size: m.artist, weight: .regular))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
            if showAlbum, !track.album.isEmpty {
                Text(track.album)
                    .font(.system(size: m.artist - 1.5))
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Où placer les boutons de lecture dans la colonne de la piste en cours.
private enum ControlsPlacement {
    /// Pas de boutons (petit widget : macOS n'y accepte qu'un seul lien, celui du widget entier).
    case none
    /// Dans une pastille posée sur le bas de la pochette.
    case onArtwork(CGFloat)
    /// Sous la barre de progression.
    case below(CGFloat)
}

/// Pochette au-dessus, titres et progression dessous. La pochette prend la hauteur qui reste.
private struct NowPlayingColumn: View {
    let frame: Frame
    let track: Track
    let m: Metrics
    let artSize: SharedStore.ArtSize
    let live: Bool
    var controls: ControlsPlacement = .none

    var body: some View {
        VStack(alignment: .leading, spacing: m.gap * 0.62) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ArtworkView(track: track, size: artSize, side: side)
                    .overlay(alignment: .bottomLeading) {
                        if case .none = controls, !frame.isPlaying { PausedBadge() }
                    }
                    .overlay(alignment: .bottom) {
                        if case .onArtwork(let size) = controls { ControlsPill(isPlaying: frame.isPlaying, size: size, live: live) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            TrackTitles(track: track, m: m)
            ProgressSection(frame: frame, live: live, showTimes: m.showTimes)
            if case .below(let size) = controls {
                Controls(isPlaying: frame.isPlaying, size: size, live: live)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - File d'attente

private struct QueueRow: View {
    let track: Track
    let m: Metrics

    var body: some View {
        HStack(spacing: m.thumb * 0.28) {
            ArtworkView(track: track, size: .small, side: m.thumb)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(track.title)
                    .font(.system(size: m.rowTitle, weight: .medium))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: m.rowArtist))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if m.showDurations, track.duration > 0 {
                Text(clock(track.duration))
                    .font(.system(size: m.rowArtist, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(height: m.thumb)
    }
}

private struct QueuePanel: View {
    let tracks: [Track]
    let m: Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: m.rowGap + 1) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text("À SUIVRE").kerning(0.9)
            }
            .font(.system(size: m.header, weight: .bold))
            .foregroundStyle(.white.opacity(0.66))

            GeometryReader { geo in
                let rows = max(0, Int((geo.size.height + m.rowGap) / (m.thumb + m.rowGap)))
                let shown = min(rows, tracks.count)
                // Les lignes se répartissent sur la hauteur du panneau quand il reste un peu de place.
                let spread = shown > 1 ? (geo.size.height - CGFloat(shown) * m.thumb) / CGFloat(shown - 1) : m.rowGap
                let gap = shown == rows ? min(max(m.rowGap, spread), m.rowGap * 1.8) : m.rowGap
                if tracks.isEmpty {
                    Text("Rien à suivre")
                        .font(.system(size: m.rowTitle))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(Array(tracks.prefix(shown).enumerated()), id: \.offset) { _, track in
                            QueueRow(track: track, m: m)
                        }
                    }
                }
            }
        }
        .padding(m.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(m.panelRadius)
    }
}

// MARK: - Vue principale

/// Contenu du widget, sans son fond (voir `PlatineBackground`).
/// `live` : barre de progression animée par le système (widget). À false, barre figée (aperçu rendu en image).
public struct PlatineView: View {
    let frame: Frame
    let size: PlatineSize
    let live: Bool

    public init(frame: Frame, size: PlatineSize, live: Bool = true) {
        self.frame = frame
        self.size = size
        self.live = live
    }

    public var body: some View {
        let m = Metrics.of(size)
        Group {
            if let track = frame.current {
                switch size {
                case .small:
                    NowPlayingColumn(frame: frame, track: track, m: m, artSize: .medium, live: live)
                case .medium:
                    GeometryReader { geo in
                        HStack(spacing: m.gap) {
                            NowPlayingColumn(frame: frame, track: track, m: m, artSize: .medium, live: live, controls: .onArtwork(11))
                                .frame(width: geo.size.width * 0.37)
                            QueuePanel(tracks: frame.upcoming, m: m)
                        }
                    }
                case .large:
                    VStack(spacing: m.gap) {
                        HStack(alignment: .top, spacing: m.gap) {
                            ArtworkView(track: track, size: .medium, side: 96)
                            VStack(alignment: .leading, spacing: 0) {
                                TrackTitles(track: track, m: m)
                                Spacer(minLength: 2)
                                Controls(isPlaying: frame.isPlaying, size: 15, live: live)
                                    .frame(maxWidth: .infinity)
                                Spacer(minLength: 2)
                                ProgressSection(frame: frame, live: live, showTimes: true)
                            }
                        }
                        .frame(height: 96)
                        QueuePanel(tracks: frame.upcoming, m: m)
                    }
                case .extraLarge:
                    GeometryReader { geo in
                        HStack(spacing: m.gap) {
                            NowPlayingColumn(frame: frame, track: track, m: m, artSize: .large, live: live, controls: .below(20))
                                .frame(width: min(geo.size.width * 0.36, geo.size.height - 124))
                            QueuePanel(tracks: frame.upcoming, m: m)
                        }
                    }
                }
            } else {
                EmptyState(compact: size == .small)
            }
        }
        .padding(m.padding)
        .foregroundStyle(.white)
    }
}

private struct EmptyState: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: compact ? 22 : 26, weight: .medium))
                .frame(width: compact ? 50 : 58, height: compact ? 50 : 58)
                .glass(compact ? 25 : 29)
            Text("Rien en lecture")
                .font(.system(size: 13, weight: .semibold))
            if !compact {
                Text("Lance Musique pour voir la file d'attente.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Exemple (galerie de widgets)

public extension Frame {
    /// Image d'exemple, sans pochette, pour la galerie de widgets et les aperçus.
    static func sample(at date: Date = Date()) -> Frame {
        let names: [(String, String, Double)] = [
            ("Lumière d'été", "Les Persiennes", 201), ("Rue des Vignes", "Mona Vale", 187), ("Minuit moins une", "Cargo Bleu", 224),
            ("Parallèles", "Élio Marchetti", 176), ("Les Grands Soirs", "Vitrine", 243), ("Avenue du Port", "Mona Vale", 198),
            ("Tout doux", "Cargo Bleu", 165), ("Septembre", "Les Persiennes", 212), ("Le Phare", "Vitrine", 233),
        ]
        let tracks = names.map { Track(title: $0.0, artist: $0.1, album: "Album", duration: $0.2) }
        return Frame(date: date, current: tracks[0], upcoming: Array(tracks.dropFirst()), isPlaying: true,
                     start: date.addingTimeInterval(-74), end: date.addingTimeInterval(tracks[0].duration - 74))
    }
}
