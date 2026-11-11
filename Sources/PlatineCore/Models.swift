import Foundation

/// Une piste, en cours ou à venir.
public struct Track: Codable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    /// Durée en secondes, 0 si inconnue.
    public var duration: Double
    /// Clé des fichiers de pochette dans `art/` (voir `SharedStore.artURL`), nil sans pochette.
    public var artKey: String?

    public init(title: String, artist: String, album: String = "", duration: Double = 0, artKey: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artKey = artKey
    }

    /// Identité d'une piste d'un relevé à l'autre. Les identifiants de MediaRemote changent à chaque
    /// reconstruction de la file (radio, lecture automatique) : on compare donc le contenu.
    public var signature: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }
}

/// État écrit par l'app et lu par le widget.
public struct PlayerState: Codable, Equatable {
    /// `tracks[0]` est la piste en cours, la suite est la file d'attente dans l'ordre.
    public var tracks: [Track]
    public var isPlaying: Bool
    /// Position dans la piste en cours, en secondes, mesurée à `anchor`.
    public var elapsed: Double
    public var anchor: Date

    public init(tracks: [Track] = [], isPlaying: Bool = false, elapsed: Double = 0, anchor: Date = Date()) {
        self.tracks = tracks
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.anchor = anchor
    }
}

/// Ce que le widget affiche à partir d'un instant donné.
public struct Frame: Equatable {
    /// Instant à partir duquel cette image est affichée.
    public var date: Date
    public var current: Track?
    public var upcoming: [Track]
    public var isPlaying: Bool
    /// Début et fin théoriques de la piste en cours, quand la lecture tourne et que la durée est connue.
    public var start: Date?
    public var end: Date?
    /// Avancement figé (0 à 1), utilisé en pause.
    public var fraction: Double

    public init(date: Date, current: Track?, upcoming: [Track] = [], isPlaying: Bool = false,
                start: Date? = nil, end: Date? = nil, fraction: Double = 0) {
        self.date = date
        self.current = current
        self.upcoming = upcoming
        self.isPlaying = isPlaying
        self.start = start
        self.end = end
        self.fraction = fraction
    }
}
