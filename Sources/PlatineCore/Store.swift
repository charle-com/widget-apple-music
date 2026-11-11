import Foundation

/// Fichiers partagés entre l'app (qui écrit) et le widget (qui lit), dans `~/Library/Application Support/Platine/`.
/// Pas de conteneur de groupe : sans équipe Apple, macOS le protège par TCC. Le widget sandboxé lit ce dossier
/// grâce à une exception `home-relative-path.read-only` (voir PlatineWidget.entitlements).
public enum SharedStore {
    public enum ArtSize: String {
        /// 600 px, grands widgets.
        case large = "l"
        /// 300 px, petits widgets.
        case medium = "m"
        /// 96 px, vignettes de la file.
        case small = "s"
        /// Pochette floutée, fond du widget.
        case background = "bg"
    }

    /// Vrai dossier perso, même depuis la sandbox du widget, où `homeDirectoryForCurrentUser` renvoie le
    /// conteneur `~/Library/Containers/<id>/Data`.
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["PLATINE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return realHome.appendingPathComponent("Library/Application Support/Platine", isDirectory: true)
    }

    public static var stateURL: URL { directory.appendingPathComponent("state.json") }
    public static var artDirectory: URL { directory.appendingPathComponent("art", isDirectory: true) }

    public static func artURL(key: String, size: ArtSize) -> URL {
        artDirectory.appendingPathComponent("\(key)-\(size.rawValue).jpg")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func load() -> PlayerState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? decoder.decode(PlayerState.self, from: data)
    }

    public static func save(_ state: PlayerState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Écriture atomique : le widget ne lit jamais un fichier à moitié écrit.
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}
