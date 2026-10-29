import AppKit
import ApplicationServices
import SwiftUI

struct WindowPermissionsView: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    private var ready: Bool { accessibilityGranted && screenRecordingGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ready ? "Ready to grab windows" : "Set up window grabbing")
                .font(.headline)
            Text(ready
                 ? "Drag a window toward the notch, then release while grabbed."
                 : "Window grabbing needs both permissions. Enable Notch Monster in each pane of System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            permissionRow("Accessibility", detail: "Find and close the window you feed it.", granted: accessibilityGranted) {
                if !AXIsProcessTrusted() {
                    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
                openPrivacyPane("Privacy_Accessibility")
            }
            permissionRow("Screen Recording", detail: "Capture that window for the eating animation.", granted: screenRecordingGranted) {
                if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                openPrivacyPane("Privacy_ScreenCapture")
            }
            if !ready {
                Text("If macOS asks you to quit and reopen, do so. You can always reopen Notch Monster from Applications or click its Dock icon to return here. Files work without these permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Button("Enable…", action: request)
                    .accessibilityLabel("Enable \(title)")
            }
        }
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
