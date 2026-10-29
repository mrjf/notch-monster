import Foundation
import Testing
@testable import NotchMonster

@MainActor
struct MonsterSoundTests {
    @Test func defaultAndUnknownSoundSetsUseFuzzy() throws {
        let fixture = try SoundFixture()
        defer { fixture.close() }
        #expect(!fixture.model.soundEffectsEnabled)
        #expect(fixture.model.soundSet == .fuzzy)
        #expect(fixture.player.prepared == [.fuzzy])

        fixture.defaults.set("a-removed-set", forKey: "soundSet")
        let restored = MonsterModel(defaults: fixture.defaults, soundPlayer: fixture.player)
        #expect(restored.soundSet == .fuzzy)
    }

    @Test func freshInstallStaysSilentUntilSoundsAreEnabled() throws {
        let fixture = try SoundFixture()
        defer { fixture.close() }
        #expect(fixture.defaults.object(forKey: "soundEffectsEnabled") == nil)
        #expect(!fixture.model.soundEffectsEnabled)
        fixture.approach()
        fixture.model.playYankSound(crumple: false)
        fixture.model.playYankSound(crumple: true)
        fixture.model.previewSound()
        #expect(fixture.player.events.isEmpty)

        fixture.model.soundEffectsEnabled = true
        fixture.model.previewSound()
        #expect(fixture.player.events == [.init(.window, .fuzzy)])
        let restored = MonsterModel(defaults: fixture.defaults, soundPlayer: fixture.player)
        #expect(restored.soundEffectsEnabled)
    }

    @Test func muteAndSelectionPersistAcrossLaunches() throws {
        let fixture = try SoundFixture(soundEffectsEnabled: true)
        defer { fixture.close() }
        fixture.model.soundEffectsEnabled = false
        fixture.model.soundSet = .arcade
        let restored = MonsterModel(defaults: fixture.defaults, soundPlayer: fixture.player)
        #expect(!restored.soundEffectsEnabled)
        #expect(restored.soundSet == .arcade)
    }

    @Test func mutingStopsPlaybackAndPreventsAllNewSounds() throws {
        let fixture = try SoundFixture(soundEffectsEnabled: true)
        defer { fixture.close() }
        fixture.model.previewSound()
        #expect(fixture.player.events == [.init(.window, .fuzzy)])
        fixture.model.soundEffectsEnabled = false
        #expect(fixture.player.stops == 1)
        fixture.approach()
        fixture.model.playYankSound(crumple: false)
        fixture.model.previewSound()
        #expect(fixture.player.events.count == 1)
    }

    @Test func selectionStopsPreviousSoundAndPreparesTheNewSet() throws {
        let fixture = try SoundFixture(soundEffectsEnabled: true)
        defer { fixture.close() }
        fixture.model.previewSound()
        fixture.model.soundSet = .rubber
        #expect(fixture.player.stops == 1)
        #expect(fixture.player.prepared == [.fuzzy, .rubber])
        fixture.model.previewSound()
        #expect(fixture.player.events.last == .init(.window, .rubber))
    }

    @Test func reachSoundsOncePerEntryAndDoesNotChatterAtTheBoundary() throws {
        let fixture = try SoundFixture(soundEffectsEnabled: true)
        defer { fixture.close() }
        fixture.approach()
        for _ in 0..<120 { fixture.approach() }
        #expect(fixture.player.events == [.init(.reach, .fuzzy)])

        fixture.model.reset()
        fixture.clock.time += 0.1
        fixture.approach()
        #expect(fixture.player.events.count == 1)
        fixture.clock.time += 1
        fixture.approach() // Staying attached is still quiet after the cooldown.
        #expect(fixture.player.events.count == 1)
        fixture.model.reset()
        fixture.approach()
        #expect(fixture.player.events.count == 2)
    }

    @Test func confirmedYanksChooseTheCorrectCueAndResetDoesNotCutTheTail() throws {
        let fixture = try SoundFixture(soundEffectsEnabled: true)
        defer { fixture.close() }
        fixture.model.playYankSound(crumple: false)
        fixture.model.playYankSound(crumple: true)
        #expect(fixture.player.events == [.init(.file, .fuzzy), .init(.window, .fuzzy)])
        fixture.model.reset()
        #expect(fixture.player.stops == 0)
        fixture.model.fail("The window did not close.")
        #expect(fixture.player.stops == 1)
        #expect(fixture.player.events.count == 2)
        fixture.model.reset()
    }

    @Test func sleepingMonsterStopsPlaybackAndStaysSilentDuringDrags() throws {
        let fixture = try SoundFixture(soundEffectsEnabled: true)
        defer { fixture.close() }
        fixture.approach()
        fixture.model.enabled = false
        #expect(fixture.player.stops == 1)
        fixture.approach()
        fixture.model.playYankSound(crumple: true)
        #expect(fixture.player.events == [.init(.reach, .fuzzy)])
    }
}

@MainActor
private final class SoundSpy: MonsterSoundPlaying {
    struct Event: Equatable {
        let event: MonsterSoundEvent
        let set: MonsterSoundSet
        init(_ event: MonsterSoundEvent, _ set: MonsterSoundSet) { self.event = event; self.set = set }
    }
    var events: [Event] = []
    var prepared: [MonsterSoundSet] = []
    var stops = 0
    func prepare(set: MonsterSoundSet) { prepared.append(set) }
    func play(_ event: MonsterSoundEvent, set: MonsterSoundSet) { events.append(Event(event, set)) }
    func stop() { stops += 1 }
}

@MainActor
private final class SoundClock {
    var time: TimeInterval = 0
}

@MainActor
private struct SoundFixture {
    let defaults: UserDefaults
    let player = SoundSpy()
    let clock = SoundClock()
    let model: MonsterModel
    private let suite = "notch-sound-tests.\(UUID().uuidString)"

    init(soundEffectsEnabled: Bool? = nil) throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        if let soundEffectsEnabled {
            defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled")
        }
        let clock = clock
        model = MonsterModel(defaults: defaults, soundPlayer: player, soundClock: { clock.time })
    }
    func approach() {
        model.approach(cursor: CGPoint(x: 0, y: -60), center: .zero, dragging: true)
    }
    func close() {
        model.reset()
        defaults.removePersistentDomain(forName: suite)
    }
}
