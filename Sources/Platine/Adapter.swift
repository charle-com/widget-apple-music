import Foundation

/// Relevé émis par l'adaptateur MediaRemote (une ligne JSON par changement, voir Adapter/adapter.m).
struct Snapshot: Decodable {
    struct Item: Decodable {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        /// URL de la pochette, vide quand Musique n'en donne pas (piste de la bibliothèque).
        let art: String
        /// Identifiant de catalogue Apple Music de la piste : il permet de retrouver l'adresse de la pochette.
        let store: String?
        /// Image de la pochette posée par l'adaptateur dans un fichier temporaire, piste en cours seulement.
        let file: String?
    }

    /// Vrai si l'app en lecture est Musique (et pas un navigateur ou un autre lecteur).
    let music: Bool
    let playing: Bool
    let elapsed: Double
    let timestamp: Double
    let items: [Item]
}

/// Fait tourner l'adaptateur dans `/usr/bin/perl` : macOS n'ouvre MediaRemote qu'aux binaires système.
final class AdapterProcess {
    var onSnapshot: ((Snapshot) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()

    var isRunning: Bool { process != nil }

    /// Transmet une commande au lecteur : `play`, `pause`, `next` ou `previous`.
    func send(_ command: String) {
        guard let input, let data = "\(command)\n".data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }
    private var wanted = false

    private static let script = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "platine_run") or die "symbole introuvable";
    DynaLoader::dl_install_xsub("main::platine_run", $sym);
    main::platine_run();
    """

    func start() {
        wanted = true
        launch()
    }

    func stop() {
        wanted = false
        process?.terminate()
        process = nil
        input = nil
        buffer.removeAll()
    }

    private func launch() {
        guard wanted, process == nil else { return }
        guard let lib = Bundle.main.url(forResource: "libPlatineAdapter", withExtension: "dylib") else {
            Log.write("adaptateur introuvable dans le bundle")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.script, lib.path]
        let pipe = Pipe()
        let commands = Pipe()
        p.standardOutput = pipe
        p.standardInput = commands
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                self.process = nil
                self.input = nil
                Log.write("adaptateur arrêté (code \(finished.terminationStatus))")
                // Relance tant que Musique tourne, sans boucle serrée si l'adaptateur meurt d'emblée.
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.launch() }
            }
        }
        do {
            try p.run()
            process = p
            input = commands.fileHandleForWriting
            Log.write("adaptateur lancé (pid \(p.processIdentifier))")
        } catch {
            Log.write("lancement de l'adaptateur impossible : \(error.localizedDescription)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: line) {
                onSnapshot?(snapshot)
            }
        }
    }
}

/// Journal minimal, pour vérifier après coup ce que l'app a publié : `~/Library/Logs/Platine/platine.log`.
enum Log {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Platine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("platine.log")
        // Le journal repart de zéro au-delà de 300 Ko.
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 300_000 {
            try? FileManager.default.removeItem(at: file)
        }
        return file
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
