import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class SessionStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String?
    init() { if let token = SecureStore.read() { isAuthenticated = true; Task { await ZvukAPI.shared.configure(token: token) } } }
    func signIn(token: String) async { error = nil; do { try await ZvukAPI.shared.verifyToken(token); SecureStore.save(token); isAuthenticated = true } catch { self.error = error.localizedDescription } }
    func signOut() { SecureStore.delete(); isAuthenticated = false; Task { await ZvukAPI.shared.configure(token: nil) } }
}

@MainActor
final class PlayerStore: NSObject, ObservableObject {
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    @Published private(set) var queue: [Track] = []
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var queueIndex = 0

    override init() {
        super.init()
        configureRemoteCommands()
        NotificationCenter.default.addObserver(self, selector: #selector(trackEnded), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    deinit { if let timeObserver { player?.removeTimeObserver(timeObserver) }; NotificationCenter.default.removeObserver(self) }

    func play(_ track: Track, in newQueue: [Track]? = nil) async {
        if let newQueue, !newQueue.isEmpty { queue = newQueue; queueIndex = newQueue.firstIndex(where: { $0.id == track.id }) ?? 0 }
        else { queue = [track]; queueIndex = 0 }
        await startCurrentTrack()
    }
    private func startCurrentTrack() async {
        guard queue.indices.contains(queueIndex) else { return }
        let track = queue[queueIndex]
        error = nil
        do {
            try configureAudioSession()
            let url = try await ZvukAPI.shared.streamURL(for: track.id)
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            let newPlayer = AVPlayer(url: url)
            player = newPlayer; current = track; progress = 0; duration = Double(track.duration ?? 0)
            observeTime(for: newPlayer)
            newPlayer.play(); isPlaying = true; updateNowPlayingInfo()
        } catch { self.error = error.localizedDescription }
    }
    func toggle() { isPlaying ? pause() : resume() }
    func pause() { player?.pause(); isPlaying = false; updateNowPlayingInfo() }
    func resume() { guard player != nil else { return }; try? configureAudioSession(); player?.play(); isPlaying = true; updateNowPlayingInfo() }
    func seek(_ value: Double) { player?.seek(to: CMTime(seconds: value, preferredTimescale: 600)); progress = value; updateNowPlayingInfo() }
    func skip(by seconds: Double) { seek(min(max(progress + seconds, 0), duration)) }
    func next() async { guard !queue.isEmpty else { return }; queueIndex = (queueIndex + 1) % queue.count; await startCurrentTrack() }
    func previous() async { if progress > 3 { seek(0); return }; guard !queue.isEmpty else { return }; queueIndex = (queueIndex - 1 + queue.count) % queue.count; await startCurrentTrack() }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setActive(true)
    }
    private func observeTime(for newPlayer: AVPlayer) {
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.player === newPlayer else { return }
                self.progress = time.seconds.isFinite ? time.seconds : 0
                let itemDuration = newPlayer.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite, itemDuration > 0 { self.duration = itemDuration }
                self.updateNowPlayingInfo()
            }
        }
    }
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { await self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { await self?.previous() }; return .success }
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(by: 15) }; return .success }
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(by: -15) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
    private func updateNowPlayingInfo() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.artistText, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: progress, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
    }
    @objc private func trackEnded() { Task { await next() } }
}
