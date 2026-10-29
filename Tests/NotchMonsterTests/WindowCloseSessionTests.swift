import ApplicationServices
import Testing
@testable import NotchMonster

@MainActor
struct WindowCloseSessionTests {
    // Opaque AX identities only; these tests never close or quit user apps.
    @MainActor private final class Fixture {
        let target = AXUIElementCreateApplication(41_001)
        let other = AXUIElementCreateApplication(41_002)
        var windows: [AXUIElement]?
        var terminated = false
        var acceptsQuit = true
        var quitRequests = 0

        init() { windows = [target] }

        func session() -> WindowCloseSession {
            WindowCloseSession(window: target, isTerminated: { self.terminated },
                readWindows: { self.windows }, requestQuit: {
                    self.quitRequests += 1
                    return self.acceptsQuit
                })
        }
    }

    @Test func closingLastWindowRequestsNormalQuitExactlyOnce() {
        let app = Fixture()
        let session = app.session()
        #expect(!session.isClosed())
        app.windows = []
        #expect(session.isClosed())
        #expect(session.quitIfLastWindow() == .requested)
        // A delayed exit is not a reason to send the request again.
        #expect(session.quitIfLastWindow() == .requested)
        #expect(app.quitRequests == 1)
    }

    @Test func anyRemainingWindowKeepsApplicationRunning() {
        let app = Fixture()
        app.windows = [app.target, app.other]
        let session = app.session()
        app.windows = [app.other]
        #expect(session.isClosed())
        #expect(session.quitIfLastWindow() == .windowsRemain)
        #expect(app.quitRequests == 0)
    }

    @Test func refusedCloseOrSaveDialogDoesNotQuit() {
        let app = Fixture()
        let session = app.session()
        // A close confirmation leaves the target open alongside a dialog.
        app.windows = [app.target, app.other]
        #expect(!session.isClosed())
        #expect(session.quitIfLastWindow() == .closeNotConfirmed)
        #expect(app.quitRequests == 0)
    }

    @Test func aNewWindowDuringAnimationPreventsQuit() {
        let app = Fixture()
        let session = app.session()
        app.windows = []
        #expect(session.isClosed())
        app.windows = [app.other]
        #expect(session.quitIfLastWindow() == .windowsRemain)
        #expect(app.quitRequests == 0)
    }

    @Test func inaccessibleWindowListIsNotAnEmptyList() {
        let app = Fixture()
        let session = app.session()
        app.windows = nil
        #expect(!session.isClosed())
        app.windows = []
        #expect(session.isClosed())
        app.windows = nil
        #expect(session.quitIfLastWindow() == .unavailable)
        #expect(app.quitRequests == 0)
    }

    @Test func applicationThatAlreadyQuitNeedsNoQuitRequest() {
        let app = Fixture()
        let session = app.session()
        app.terminated = true
        app.windows = nil
        #expect(session.isClosed())
        #expect(session.quitIfLastWindow() == .alreadyTerminated)
        #expect(app.quitRequests == 0)
    }

    @Test func rejectedQuitIsNotRetriedOrForced() {
        let app = Fixture()
        let session = app.session()
        app.windows = []
        app.acceptsQuit = false
        #expect(session.isClosed())
        #expect(session.quitIfLastWindow() == .declined)
        #expect(session.quitIfLastWindow() == .declined)
        #expect(app.quitRequests == 1)
    }
}
