import Foundation
import Testing
@testable import NotchMonster

struct RaycastHandoffTests {
    @Test func deeplinkPreservesEveryExactPathIncludingQueryCharacters() throws {
        let files = [
            URL(fileURLWithPath: "/tmp/Notch Monster/café & #1?.txt"),
            URL(fileURLWithPath: "/tmp/Notch Monster/second + 50%.pdf")
        ]
        let url = try RaycastHandoff.url(for: files)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "raycast")
        #expect(components.host == "extensions")
        #expect(components.path == "/notchmonster/notch-monster/file-actions")
        let context = try #require(components.queryItems?.first(where: { $0.name == "context" })?.value)
        let decoded = try JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: [String]]
        #expect(decoded?["paths"] == files.map(\.path))
        #expect(components.fragment == nil)
    }

    @Test func handoffRejectsEmptyOrNonFilePayloads() {
        #expect(throws: RaycastHandoff.Failure.self) { try RaycastHandoff.url(for: []) }
        #expect(throws: RaycastHandoff.Failure.self) { try RaycastHandoff.url(for: [URL(string: "https://example.com/file")!]) }
    }

    @MainActor
    @Test func fileActionDefaultsToTrashAndPersistsExplicitChoice() {
        let suite = "notch-monster-preferences-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = MonsterModel(defaults: defaults)
        #expect(original.fileAction == .trash)
        original.fileAction = .raycast
        #expect(MonsterModel(defaults: defaults).fileAction == .raycast)
    }
}
