import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: EditorStore
    @AppStorage("autoStudioCheck") private var autoStudioCheck = true
    @AppStorage("floatingRecordingController") private var floatingController = true

    var body: some View {
        TabView {
            Form {
                Picker("Language", selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Toggle("Automatically run Studio Check", isOn: $autoStudioCheck)
                Toggle("Keep recording controller on top", isOn: $floatingController)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                LabeledContent("Screen access") {
                    permissionLabel(granted: !store.capturePermissionIssue)
                }
                LabeledContent("Microphone") {
                    permissionLabel(
                        granted: store.deviceMonitor.microphoneAuthorization == .authorized
                    )
                }
                LabeledContent("Camera") {
                    permissionLabel(
                        granted: store.deviceMonitor.cameraAuthorization == .authorized
                    )
                }
                Button("Refresh sources") {
                    Task {
                        await store.refreshPermissionState()
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Recording", systemImage: "record.circle")
            }
        }
        .frame(width: 520, height: 330)
        .padding(16)
    }

    private func permissionLabel(granted: Bool) -> some View {
        Label(
            granted ? "Ready" : "Permission required",
            systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(granted ? Color.green : Color.orange)
    }
}
