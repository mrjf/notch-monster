import AppKit
import ApplicationServices
import SwiftUI

struct WindowPermissionsView: View {
    let permissions: WindowPermissions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(permissions.ready ? "Ready to grab windows" : "Set up window grabbing")
                .font(.headline)
            Text(permissions.ready
                 ? "Drag a window toward the notch, then release while grabbed."
                 : "Window grabbing needs both permissions. Enable Notch Monster in each pane of System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            permissionRow("Accessibility", detail: "Find and close the window you feed it.", granted: permissions.accessibilityGranted) {
                if !AXIsProcessTrusted() {
                    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
                openPrivacyPane("Privacy_Accessibility")
            }
            permissionRow("Screen Recording", detail: "Capture that window for the eating animation.", granted: permissions.screenRecordingGranted) {
                openPrivacyPane("Privacy_ScreenCapture")
            }
            Button(permissions.checking ? "Checking capture…" : "Check permissions again") {
                Task { await permissions.check() }
            }
            .disabled(permissions.checking)
            if let error = permissions.captureError {
                Text("Capture check failed: \(error)")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !permissions.ready {
                Text("If Screen Recording is already on but this check fails, quit Notch Monster, turn its permission off and back on, then reopen the app. After replacing the app, you may need to remove its old entry and add the copy in Applications again.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("If macOS asks you to quit and reopen, do so. You can always reopen Notch Monster from Applications or click its Dock icon to return here. Files work without these permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            permissions.refreshAccessibility()
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
