import SwiftUI

struct SettingsView: View {
    @Bindable var model: MonsterModel
    let permissions: WindowPermissions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WindowPermissionsView(permissions: permissions)
                Divider()
                Toggle("Keep the monster awake", isOn: $model.enabled)
                Toggle("Let it close dragged windows", isOn: $model.closeWindows)
                Toggle("Reduce motion", isOn: $model.reduceMotion)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Bat the cursor away", isOn: $model.batCursorAway)
                    Text("Come under the notch empty-handed for a playful swat. Move or click to stop the flight. Reduce motion keeps your cursor still.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Sound effects", isOn: $model.soundEffectsEnabled)
                    HStack {
                        Picker("Sound set", selection: $model.soundSet) {
                            ForEach(MonsterSoundSet.allCases) { soundSet in
                                Text(soundSet.title).tag(soundSet)
                            }
                        }
                        Button("Preview") { model.previewSound() }
                            .disabled(!model.soundEffectsEnabled)
                    }
                    Text("A soft reach, a quick yank, and a crunch for windows.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Picker("When I feed it files", selection: $model.fileAction) {
                        ForEach(FileDropAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    if model.fileAction == .raycast {
                        Text("Choose Open With, Quick Look, or another action in Raycast. Files stay in place. Requires the companion extension.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Raycast setup instructions…") {
                            do { try RaycastHandoff.showSetup() }
                            catch { model.fail("Raycast setup: \(error.localizedDescription)") }
                        }
                            .font(.caption)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Arm length")
                        Slider(value: $model.armLength, in: 80...360)
                            .accessibilityLabel("Arm length")
                        Text("\(Int(model.armLength)) pt").monospacedDigit().frame(width: 55)
                    }
                    Text("Move away to let go. Move closer to grab again.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Release while grabbed to feed the monster. After moving away, release to place the window safely, even within arm’s reach.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Notch Monster") \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unpackaged"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: min(760, (NSScreen.main?.visibleFrame.height ?? 860) - 100))
    }
}
