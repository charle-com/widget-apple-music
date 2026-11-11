import Foundation
import Testing
@testable import PlatineCore

private func track(_ name: String, _ duration: Double = 100) -> Track {
    Track(title: name, artist: "Artiste", album: "Album", duration: duration, artKey: name)
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func framesAdvanceThroughTheQueue() {
    let state = PlayerState(tracks: [track("A"), track("B"), track("C")], isPlaying: true, elapsed: 40, anchor: t0)
    let frames = Planner.frames(for: state, now: t0.addingTimeInterval(10))
    #expect(frames.count == 3)
    #expect(frames[0].current?.title == "A")
    #expect(frames[0].upcoming.map(\.title) == ["B", "C"])
    #expect(frames[0].start == t0.addingTimeInterval(-40))
    #expect(frames[1].date == t0.addingTimeInterval(60))
    #expect(frames[1].current?.title == "B")
    #expect(frames[2].date == t0.addingTimeInterval(160))
    #expect(frames[2].upcoming.isEmpty)
}

@Test func staleStateSkipsFinishedTracks() {
    let state = PlayerState(tracks: [track("A"), track("B"), track("C")], isPlaying: true, elapsed: 0, anchor: t0)
    let frames = Planner.frames(for: state, now: t0.addingTimeInterval(150))
    #expect(frames.first?.current?.title == "B")
    #expect(frames.first?.start == t0.addingTimeInterval(100))
}

@Test func pausedStateGivesOneStaticFrame() {
    let state = PlayerState(tracks: [track("A"), track("B")], isPlaying: false, elapsed: 25, anchor: t0)
    let frames = Planner.frames(for: state, now: t0.addingTimeInterval(500))
    #expect(frames.count == 1)
    #expect(frames[0].fraction == 0.25)
    #expect(frames[0].isPlaying == false)
}

@Test func unknownDurationStopsThePrediction() {
    let state = PlayerState(tracks: [track("A", 0), track("B")], isPlaying: true, elapsed: 5, anchor: t0)
    let frames = Planner.frames(for: state, now: t0.addingTimeInterval(1000))
    #expect(frames.count == 1)
    #expect(frames[0].current?.title == "A")
    #expect(frames[0].end == nil)
}

@Test func emptyStateGivesPlaceholderFrame() {
    #expect(Planner.frames(for: nil, now: t0).first?.current == nil)
}

@Test func naturalTrackChangeNeedsNoReload() {
    let queue = (0..<10).map { track("T\($0)") }
    let published = PlayerState(tracks: queue, isPlaying: true, elapsed: 0, anchor: t0)
    // 130 s plus tard, Musique est passée seule à T1, 30 s écoulées, la file a glissé d'un cran.
    let actual = PlayerState(tracks: Array(queue.dropFirst()), isPlaying: true, elapsed: 28, anchor: t0.addingTimeInterval(128))
    #expect(Planner.needsPublish(published: published, actual: actual, now: t0.addingTimeInterval(130)) == false)
}

@Test func skipPauseAndQueueEditNeedReload() {
    let queue = (0..<10).map { track("T\($0)") }
    let published = PlayerState(tracks: queue, isPlaying: true, elapsed: 0, anchor: t0)
    let now = t0.addingTimeInterval(30)
    let skipped = PlayerState(tracks: Array(queue.dropFirst()), isPlaying: true, elapsed: 0, anchor: now)
    #expect(Planner.needsPublish(published: published, actual: skipped, now: now))
    let paused = PlayerState(tracks: queue, isPlaying: false, elapsed: 30, anchor: now)
    #expect(Planner.needsPublish(published: published, actual: paused, now: now))
    var edited = queue
    edited.swapAt(2, 3)
    let reordered = PlayerState(tracks: edited, isPlaying: true, elapsed: 30, anchor: now)
    #expect(Planner.needsPublish(published: published, actual: reordered, now: now))
    let seeked = PlayerState(tracks: queue, isPlaying: true, elapsed: 80, anchor: now)
    #expect(Planner.needsPublish(published: published, actual: seeked, now: now))
}

@Test func rollingQueueReloadsOnlyWhenRunningLow() {
    let all = (0..<30).map { track("T\($0)") }
    let published = PlayerState(tracks: Array(all[0..<11]), isPlaying: true, elapsed: 0, anchor: t0)
    // Radio : la file garde 10 pistes à venir et en ajoute une à chaque changement.
    func actual(after n: Int) -> (PlayerState, Date) {
        let now = t0.addingTimeInterval(Double(n) * 100 + 10)
        return (PlayerState(tracks: Array(all[n..<(n + 11)]), isPlaying: true, elapsed: 10, anchor: now), now)
    }
    let (a1, n1) = actual(after: 1)
    #expect(Planner.needsPublish(published: published, actual: a1, now: n1) == false)
    let (a4, n4) = actual(after: 4)
    #expect(Planner.needsPublish(published: published, actual: a4, now: n4) == false)
    let (a5, n5) = actual(after: 5)
    #expect(Planner.needsPublish(published: published, actual: a5, now: n5))
}
