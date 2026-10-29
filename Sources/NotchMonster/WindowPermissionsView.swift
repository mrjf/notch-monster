import AppKit
import ApplicationServices
import SwiftUI

struct WindowPermissionsView: View {
    let permissions: WindowPermissions
    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Notch Monster" }
    private var captureUnavailable: Bool { permissions.captureError != nil && permissions.screenRecordingAccess != .denied }

    private var guidance: String {
        if captureUnavailable {
            return permissions.screenRecordingGranted
                ? "Screen Recording was verified. A capture failed; try another window or check again."
                : "The capture check could not finish. Check again to verify access."
        }
        return permissions.ready
            ? "Drag a window toward the notch, then release while grabbed."
            : "Window grabbing needs both permissions. Use the Enable buttons below to allow \(appName) in System Settings."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(captureUnavailable ? "Capture failed" : permissions.ready ? "Ready to grab windows" : "Set up window grabbing")
                .font(.headline)
            Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            permissionRow("Accessibility", detail: "Find and close the window you feed it.", granted: permissions.accessibilityGranted) {
                if !AXIsProcessTrusted() {
                    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
                openPrivacyPane("Privacy_Accessibility")
            }
            permissionRow("Screen Recording", detail: "Capture that window for the eating animation.", granted: permissions.screenRecordingGranted,
                          unverified: permissions.screenRecordingAccess == .unverified) {
                openPrivacyPane("Privacy_ScreenCapture")
            }
            Button(permissions.checking ? "Checking capture…" : permissions.captureError != nil ? "Retry capture check" : "Check permissions again") {
                Task { await permissions.check() }
            }
            .disabled(permissions.checking)
            if let error = permissions.captureError {
                Text("Capture failed: \(error)")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if permissions.screenRecordingAccess == .denied {
                Text("If Screen Recording is already on but this check fails, quit \(appName), remove its old permission entry, then add this copy of the app again. A changed signing identity can leave the old entry enabled without granting access to this build.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !permissions.accessibilityGranted || permissions.screenRecordingAccess == .denied {
                Text("If macOS asks you to quit and reopen, do so. Reopen \(appName) or click its Dock icon to return here. Files work without these permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            permissions.refreshAccessibility()
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, unverified: Bool = false, request: @escaping () -> Void) -> some View {
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
            } else if unverified {
                Text(permissions.checking ? "Checking…" : "Not verified")
                    .foregroundStyle(.secondary)
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
