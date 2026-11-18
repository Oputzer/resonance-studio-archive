import AVFoundation
import Foundation

struct QueueItem: Equatable {
    let file: URL
    let title: String
    let artist: String
    let artwork: URL?
}

@MainActor
final class Player: ObservableObject {
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var time = 0.0
    @Published private(set) var duration = 0.0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    var current: QueueItem? { queue.indices.contains(index) ? queue[index] : nil }

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    func play(_ items: [QueueItem], startAt i: Int = 0) {
        queue = items
        load(i)
    }

    func isCurrent(_ file: URL) -> Bool { current?.file == file }

    func toggle() {
        guard current != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func next() {
        if index + 1 < queue.count { load(index + 1) } else { stop() }
    }

    func previous() {
        if time > 3 { seek(to: 0) } else if index > 0 { load(index - 1) } else { seek(to: 0) }
    }

    func seek(to seconds: Double) {
        time = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        isPlaying = false
        time = 0
        duration = 0
    }

    private func load(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        time = 0
        duration = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: queue[i].file))
        player.play()
        isPlaying = true
    }

    private func tick(_ t: CMTime) {
        if t.seconds.isFinite { time = t.seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
    }
}
