import Foundation
import Testing
@testable import NotchMonster

@MainActor
struct WindowPermissionsTests {
    @Test func windowGrabbingWaitsForTheCaptureProbeAndAccessibility() async {
        var accessibility = false
        let permissions = WindowPermissions(readAccessibility: { accessibility }, probeCapture: {})
        #expect(!permissions.ready)
        await permissions.check()
        #expect(permissions.screenRecordingGranted)
        #expect(!permissions.ready)
        accessibility = true
        permissions.refreshAccessibility()
        #expect(permissions.ready)
        accessibility = false
        permissions.refreshAccessibility()
        #expect(!permissions.ready)
    }

    @Test func failedCaptureIsVisibleAndRecheckingCanRecover() async {
        var failure: NSError? = NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3801,
                                        userInfo: [NSLocalizedDescriptionKey: "Capture denied"])
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {
            if let failure { throw failure }
        })
        await permissions.check()
        #expect(!permissions.ready)
        #expect(!permissions.checking)
        #expect(permissions.captureError?.contains("Capture denied") == true)
        #expect(permissions.captureError?.contains("-3801") == true)
        failure = nil
        await permissions.check()
        #expect(permissions.ready)
        #expect(permissions.captureError == nil)
    }

    @Test func captureFailureDisablesPreviouslyVerifiedWindowGrabbing() async {
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {})
        await permissions.check()
        #expect(permissions.ready)
        permissions.captureFailed(NSError(domain: "Capture", code: 9))
        #expect(!permissions.ready)
        #expect(!permissions.screenRecordingGranted)
        #expect(permissions.captureError != nil)
    }
}
