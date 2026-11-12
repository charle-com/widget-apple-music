import AppKit
import PlatineCore
import ServiceManagement
import WidgetKit

/// Agent sans interface. Tant que Musique tourne, il suit la lecture, prépare les pochettes, écrit l'état
/// partagé et recharge le widget seulement quand la prévision déjà envoyée ne colle plus à la réalité.
@MainActor
final class Coordinator: NSObject, NSApplicationDelegate {
    private static let musicID = "com.apple.Music"
    private static let widgetKind = "PlatineWidget"

    private let adapter = AdapterProcess()
    /// Dernier état envoyé au widget. nil au lancement : le premier relevé est toujours publié.
    private var published: PlayerState?
    private var generation = 0
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let me = NSRunningApplication.current
        let twins = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if twins.contains(where: { $0 != me && $0.processIdentifier != me.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        Log.write("Platine démarre")
        // kill, fermeture de session : on arrête l'adaptateur avant de sortir, sans attendre qu'il le remarque.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.adapter.stop() }
            exit(0)
        }
        source.resume()
        termSource = source
        registerLoginItemOnce()
        ArtworkCache.prune()

        adapter.onSnapshot = { [weak self] snapshot in
            MainActor.assumeIsolated { self?.handle(snapshot) }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.musicID).isEmpty {
            freezeAsPaused(from: SharedStore.load())
        } else {
            adapter.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        adapter.stop()
    }

    /// Clic sur le widget : macOS ouvre l'app hôte avec l'URL du lien cliqué.
    /// `platine://play`, `pause`, `next`, `previous` : boutons de lecture. `platine://open` (reste du widget) : Musique.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let command = url.host ?? ""
            let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.musicID).isEmpty
            if ["play", "pause", "next", "previous"].contains(command), musicRunning {
                // L'URL peut arriver avant la fin du lancement de l'app : l'adaptateur démarre ici au besoin.
                if !adapter.isRunning { adapter.start() }
                adapter.send(command)
                Log.write("commande : \(command)")
            } else {
                openMusic()
            }
        }
        // L'app n'a aucune fenêtre : elle rend la main tout de suite à l'app qui était devant.
        NSApp.deactivate()
    }

    private func openMusic() {
        guard let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.musicID) else { return }
        NSWorkspace.shared.openApplication(at: music, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Musique se lance, Musique quitte

    @objc private func appLaunched(_ note: Notification) {
        guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Self.musicID else { return }
        Log.write("Musique lancée")
        adapter.start()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Self.musicID else { return }
        Log.write("Musique fermée")
        adapter.stop()
        generation += 1
        freezeAsPaused(from: published ?? SharedStore.load())
    }

    /// Musique ne tourne pas : le widget garde la dernière piste, figée en pause à sa position du moment.
    private func freezeAsPaused(from state: PlayerState?) {
        guard let state, state.isPlaying else { return }
        let now = Date()
        var frozen = PlayerState(tracks: [], isPlaying: false, elapsed: 0, anchor: now)
        if let pos = Planner.position(in: state, at: now) {
            frozen.tracks = Array(state.tracks[pos.index...])
            frozen.elapsed = pos.elapsed
        } else if let last = state.tracks.last {
            frozen.tracks = [last]
        }
        publish(frozen, reason: "Musique fermée")
    }

    // MARK: - Relevés

    private func handle(_ snapshot: Snapshot) {
        // Une autre app a pris la main (vidéo dans un navigateur...) : on garde le dernier état de Musique.
        guard snapshot.music, !snapshot.items.isEmpty else { return }
        generation += 1
        let mine = generation
        Task {
            var keys = [String?](repeating: nil, count: snapshot.items.count)
            await ArtworkCache.shared.resolve(snapshot.items)
            await withTaskGroup(of: (Int, String?).self) { group in
                for (i, item) in snapshot.items.enumerated() {
                    group.addTask { (i, await ArtworkCache.shared.ensure(item)) }
                }
                for await (i, key) in group { keys[i] = key }
            }
            // Un relevé plus récent est arrivé pendant le téléchargement des pochettes : celui-ci est périmé.
            guard mine == generation else { return }
            let tracks = snapshot.items.enumerated().map { i, item in
                Track(title: item.title, artist: item.artist, album: item.album, duration: item.duration, artKey: keys[i])
            }
            let state = PlayerState(tracks: tracks, isPlaying: snapshot.playing, elapsed: snapshot.elapsed,
                                    anchor: Date(timeIntervalSince1970: snapshot.timestamp))
            if Planner.needsPublish(published: published, actual: state, now: Date()) {
                publish(state, reason: published == nil ? "premier relevé" : "écart avec la prévision")
            }
        }
    }

    private func publish(_ state: PlayerState, reason: String) {
        do {
            try SharedStore.save(state)
            published = state
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
            let title = state.tracks.first?.title ?? "aucune piste"
            Log.write("publié (\(reason)) : \(state.isPlaying ? "lecture" : "pause"), « \(title) », \(max(0, state.tracks.count - 1)) à suivre")
        } catch {
            Log.write("écriture de l'état impossible : \(error.localizedDescription)")
        }
    }

    // MARK: - Ouverture de session

    /// Inscrit l'app à l'ouverture de session une seule fois : si elle est retirée ensuite dans
    /// Réglages > Général > Ouverture, ce choix est respecté.
    private func registerLoginItemOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "loginItemRegistered") else { return }
        // Seule la copie installée s'inscrit, jamais celle du dossier de build.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: "loginItemRegistered")
            Log.write("inscrite à l'ouverture de session")
        } catch {
            Log.write("inscription à l'ouverture de session impossible : \(error.localizedDescription)")
        }
    }
}
