import AVFoundation
import Foundation

enum MonsterSoundSet: String, CaseIterable, Identifiable {
    case fuzzy, rubber, arcade

    var id: Self { self }
    var title: String {
        switch self {
        case .fuzzy: "Fuzzy"
        case .rubber: "Rubber"
        case .arcade: "Arcade"
        }
    }
}

enum MonsterSoundEvent: String, CaseIterable {
    case reach, file, window
}

@MainActor
protocol MonsterSoundPlaying: AnyObject {
    func prepare(set: MonsterSoundSet)
    func play(_ event: MonsterSoundEvent, set: MonsterSoundSet)
    func stop()
}

/// One voice at a time: a yank replaces its reach instead of stacking effects.
/// All clips are short, pre-leveled Earshot renders bundled with the app.
@MainActor
final class MonsterSoundPlayer: MonsterSoundPlaying {
    private var players: [String: AVAudioPlayer] = [:]
    private var activePlayer: AVAudioPlayer?

    func prepare(set: MonsterSoundSet) {
        for event in MonsterSoundEvent.allCases { _ = player(for: event, set: set) }
    }

    func play(_ event: MonsterSoundEvent, set: MonsterSoundSet) {
        stop()
        guard let player = player(for: event, set: set) else { return }
        player.currentTime = 0
        activePlayer = player
        player.play()
    }

    func stop() {
        activePlayer?.stop()
        activePlayer = nil
    }

    private func player(for event: MonsterSoundEvent, set: MonsterSoundSet) -> AVAudioPlayer? {
        let name = "\(set.rawValue)-\(event.rawValue)"
        if let player = players[name] { return player }
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Sounds/\(name).wav")
        // The source fallback keeps `swift run` useful from the repository.
        // Distributed builds always load from their signed app bundle.
        let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") ?? sourceURL
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 1
        player.numberOfLoops = 0
        player.prepareToPlay()
        players[name] = player
        return player
    }
}
