import Foundation

/// Calcul de ce que le widget affiche dans le temps.
///
/// macOS rationne les rechargements de widget. Comme on connaît la file et la durée de chaque piste, le widget
/// reçoit d'avance une image par piste à venir et passe de l'une à l'autre tout seul. L'app ne demande un
/// rechargement que si la réalité s'écarte de cette prévision (pause, saut, file modifiée).
public enum Planner {
    /// Nombre maximal d'images préparées d'avance.
    public static let maxFrames = 12
    /// Écart de position toléré, en secondes, entre la prévision et la lecture réelle.
    public static let tolerance: Double = 4
    /// En dessous de ce nombre de pistes à venir encore prévues, on recharge pour regarnir la file affichée.
    public static let minUpcoming = 6

    /// Piste en cours et position dans cette piste à l'instant `date`, selon l'état publié.
    /// Renvoie nil si l'état ne permet pas de le dire (file vide, ou file entièrement écoulée).
    public static func position(in state: PlayerState, at date: Date) -> (index: Int, elapsed: Double)? {
        guard !state.tracks.isEmpty else { return nil }
        guard state.isPlaying else { return (0, state.elapsed) }
        var elapsed = state.elapsed + date.timeIntervalSince(state.anchor)
        for (i, track) in state.tracks.enumerated() {
            // Durée inconnue : impossible de prévoir la suite, on reste sur cette piste.
            if track.duration <= 0 || elapsed < track.duration { return (i, max(0, elapsed)) }
            elapsed -= track.duration
        }
        return nil
    }

    /// Images à afficher à partir de `now`, la première immédiatement.
    public static func frames(for state: PlayerState?, now: Date) -> [Frame] {
        guard let state, !state.tracks.isEmpty else { return [Frame(date: now, current: nil)] }
        let tracks = state.tracks

        guard state.isPlaying else {
            let t = tracks[0]
            let fraction = t.duration > 0 ? min(1, max(0, state.elapsed / t.duration)) : 0
            return [Frame(date: now, current: t, upcoming: Array(tracks.dropFirst()), fraction: fraction)]
        }
        guard let pos = position(in: state, at: now) else {
            // Toute la file prévue est écoulée et l'app n'a rien republié : on fige sur la dernière piste.
            return [Frame(date: now, current: tracks[tracks.count - 1], fraction: 1)]
        }

        var out: [Frame] = []
        var start = now.addingTimeInterval(-pos.elapsed)
        var index = pos.index
        while index < tracks.count && out.count < maxFrames {
            let t = tracks[index]
            let known = t.duration > 0
            let end = known ? start.addingTimeInterval(t.duration) : nil
            out.append(Frame(date: out.isEmpty ? now : start, current: t, upcoming: Array(tracks[(index + 1)...]),
                             isPlaying: true, start: known ? start : nil, end: end))
            guard let end else { break }
            start = end
            index += 1
        }
        return out
    }

    /// Instant où la prévision s'arrête : le widget redemande alors sa timeline.
    public static func horizon(of frames: [Frame], now: Date) -> Date {
        let fallback = now.addingTimeInterval(30 * 60)
        guard let last = frames.last, last.isPlaying, let end = last.end else { return fallback }
        return min(max(end, now.addingTimeInterval(5)), fallback)
    }

    /// Faut-il republier l'état et recharger le widget ? `published` est le dernier état envoyé au widget,
    /// `actual` celui qu'on vient de relever.
    public static func needsPublish(published: PlayerState?, actual: PlayerState, now: Date) -> Bool {
        guard let published else { return true }
        if published.isPlaying != actual.isPlaying { return true }
        if published.tracks.isEmpty != actual.tracks.isEmpty { return true }
        if actual.tracks.isEmpty { return false }

        guard actual.isPlaying else {
            return published.tracks != actual.tracks || abs(published.elapsed - actual.elapsed) > 1
        }

        guard let pos = position(in: published, at: now) else { return true }
        let predicted = published.tracks[pos.index]
        guard predicted.signature == actual.tracks[0].signature, predicted.artKey == actual.tracks[0].artKey else { return true }
        let actualElapsed = actual.elapsed + now.timeIntervalSince(actual.anchor)
        if abs(pos.elapsed - actualElapsed) > tolerance { return true }

        let predictedNext = Array(published.tracks[(pos.index + 1)...])
        let actualNext = Array(actual.tracks.dropFirst())
        let common = min(predictedNext.count, actualNext.count)
        for i in 0..<common where predictedNext[i].signature != actualNext[i].signature || predictedNext[i].artKey != actualNext[i].artKey {
            return true
        }
        // La file réelle est plus courte que prévu : des pistes ont été retirées.
        if actualNext.count < predictedNext.count { return true }
        // La file réelle est plus longue : on ne recharge que si l'affichage commence à se dégarnir.
        return actualNext.count > predictedNext.count && predictedNext.count < minUpcoming
    }
}
