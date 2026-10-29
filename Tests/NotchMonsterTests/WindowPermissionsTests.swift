import Foundation
import ScreenCaptureKit
import Testing
@testable import NotchMonster

@MainActor
struct WindowPermissionsTests {
    @Test func windowGrabbingWaitsForTheCaptureProbeAndAccessibility() async {
        var accessibility = false
        let permissions = WindowPermissions(readAccessibility: { accessibility }, probeCapture: {})
        #expect(!permissions.ready)
        #expect(permissions.screenRecordingAccess == .unverified)
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
        var failure: NSError? = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue,
                                        userInfo: [NSLocalizedDescriptionKey: "Capture denied"])
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {
            if let failure { throw failure }
        })
        await permissions.check()
        #expect(!permissions.ready)
        #expect(permissions.screenRecordingAccess == .denied)
        #expect(!permissions.checking)
        #expect(permissions.captureError?.contains("Capture denied") == true)
        #expect(permissions.captureError?.contains("-3801") == true)
        failure = nil
        await permissions.check()
        #expect(permissions.ready)
        #expect(permissions.captureError == nil)
    }

    @Test func deniedCaptureDisablesPreviouslyVerifiedWindowGrabbing() async {
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {})
        await permissions.check()
        #expect(permissions.ready)
        permissions.captureFailed(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue))
        #expect(!permissions.ready)
        #expect(!permissions.screenRecordingGranted)
        #expect(permissions.screenRecordingAccess == .denied)
        #expect(permissions.captureError != nil)
    }

    @Test func unavailableCaptureRemainsUnverifiedUntilAProbeSucceeds() async {
        var unavailable = true
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {
            if unavailable {
                throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noDisplayList.rawValue)
            }
        })
        await permissions.check()
        #expect(!permissions.ready)
        #expect(permissions.screenRecordingAccess == .unverified)
        #expect(permissions.captureError != nil)
        unavailable = false
        await permissions.check()
        #expect(permissions.ready)
        #expect(permissions.captureError == nil)
    }

    @Test func transientFailurePreservesVerifiedAccessAndAllowsAnotherTry() async {
        var failure: NSError?
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {
            if let failure { throw failure }
        })
        await permissions.check()
        failure = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Capture service unavailable"])
        await permissions.check()
        #expect(permissions.ready)
        #expect(permissions.screenRecordingAccess == .granted)
        #expect(permissions.captureError?.contains("Capture service unavailable") == true)
        failure = nil
        await permissions.check()
        #expect(permissions.ready)
        #expect(permissions.captureError == nil)
    }

    @Test func matchingErrorCodeInAnotherDomainDoesNotRevokeVerifiedAccess() async {
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {})
        await permissions.check()
        permissions.captureFailed(NSError(domain: "OtherCaptureError", code: -3801))
        #expect(permissions.ready)
        #expect(permissions.screenRecordingAccess == .granted)
        #expect(permissions.captureError != nil)
    }

    @Test func successfulWindowCaptureClearsAnEarlierFailure() async {
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {})
        await permissions.check()
        permissions.captureFailed(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue))
        #expect(permissions.captureError != nil)
        permissions.captureSucceeded()
        #expect(permissions.ready)
        #expect(permissions.screenRecordingAccess == .granted)
        #expect(permissions.captureError == nil)
    }

    @Test func transientFailureAfterDenialRequiresVerification() async {
        let permissions = WindowPermissions(readAccessibility: { true }, probeCapture: {})
        permissions.captureFailed(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue))
        permissions.captureFailed(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noCaptureSource.rawValue))
        #expect(permissions.screenRecordingAccess == .unverified)
        #expect(!permissions.ready)
        await permissions.check()
        #expect(permissions.ready)
    }
}
