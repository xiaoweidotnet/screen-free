import AppKit
import ScreenFreeCore
import SwiftUI

extension Notification.Name {
    static let screenFreeEscapePressed = Notification.Name(
        "ScreenFreeEscapePressed"
    )
    static let screenFreeDeletePressed = Notification.Name(
        "ScreenFreeDeletePressed"
    )
    static let screenFreeUndoPressed = Notification.Name(
        "ScreenFreeUndoPressed"
    )
    static let screenFreeRedoPressed = Notification.Name(
        "ScreenFreeRedoPressed"
    )
}

final class ScreenFreeKeyEventContext {
    var isHandled = false
}

enum ScreenFreeUndoRouting {
    static func shouldRouteToTimeline(
        firstResponder: NSResponder?
    ) -> Bool {
        if let textView = firstResponder as? NSTextView,
           textView.isEditable {
            return false
        }
        if let textField = firstResponder as? NSTextField,
           textField.isEditable,
           textField.isEnabled {
            return false
        }
        return true
    }
}

final class ScreenFreeAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { event in
            if event.keyCode == 53 {
                let context = ScreenFreeKeyEventContext()
                NotificationCenter.default.post(
                    name: .screenFreeEscapePressed,
                    object: context
                )
                return context.isHandled ? nil : event
            }
            let modifiers = event.modifierFlags.intersection(
                .deviceIndependentFlagsMask
            )
            let firstResponder = event.window?.firstResponder
                ?? NSApp.keyWindow?.firstResponder
            if (event.keyCode == 51 || event.keyCode == 117),
               !modifiers.contains(.command),
               !modifiers.contains(.control),
               !modifiers.contains(.option),
               ScreenFreeUndoRouting.shouldRouteToTimeline(
                   firstResponder: firstResponder
               ) {
                let context = ScreenFreeKeyEventContext()
                NotificationCenter.default.post(
                    name: .screenFreeDeletePressed,
                    object: context
                )
                return context.isHandled ? nil : event
            }
            if event.charactersIgnoringModifiers?.lowercased() == "z",
               modifiers.contains(.control) != modifiers.contains(.command),
               !modifiers.contains(.option),
               ScreenFreeUndoRouting.shouldRouteToTimeline(
                   firstResponder: firstResponder
               ) {
                let context = ScreenFreeKeyEventContext()
                NotificationCenter.default.post(
                    name: modifiers.contains(.shift)
                        ? .screenFreeRedoPressed
                        : .screenFreeUndoPressed,
                    object: context
                )
                return context.isHandled ? nil : event
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The editor is intentionally hidden while a recording-only NSPanel is
        // visible. Terminating after the last regular window disappears would
        // kill an active capture.
        false
    }
}

@main
struct ScreenFreeApp: App {
    @NSApplicationDelegateAdaptor(ScreenFreeAppDelegate.self) private var appDelegate
    @StateObject private var store = EditorStore()

    var body: some Scene {
        WindowGroup {
            MainView(store: store)
                .frame(minWidth: 1120, minHeight: 720)
                .environment(\.locale, store.appLanguage.locale)
                .task { await store.prepare() }
                .onOpenURL { url in
                    Task { await store.openExternalURL(url) }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    Task { await store.refreshPermissionState() }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    store.applicationWillTerminate()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") { store.openProject() }
                    .keyboardShortcut("o")
                Button("Save Project…") { store.saveProject() }
                    .keyboardShortcut("s")
                Divider()
                Button("Import Video…") { store.importVideo() }
                    .keyboardShortcut("i")
                Button("Import Background Music…") {
                    store.importBackgroundMusic()
                }
                Divider()
                Button("Import Style Preset…") {
                    store.importStylePreset()
                }
                Button("Save Style Preset…") {
                    store.saveStylePreset()
                }
            }
            CommandMenu("Record") {
                Button(store.isRecording ? "Stop Recording" : "Start Recording") {
                    Task { await store.startOrStopRecording() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button(store.isRecordingPaused ? "Resume" : "Pause") {
                    Task { await store.toggleRecordingPause() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!store.isRecording || store.isTransitioningRecording)
            }
            CommandMenu("Edit Video") {
                Button("Split Tool") { store.toggleSplitTool() }
                    .keyboardShortcut("b", modifiers: [])
                Button("Exit Editing Tool") {
                    store.cancelTimelineTool()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(store.activeTimelineTool == .selection)
                Button("Add Cursor Zoom") { store.addZoomAtPlayhead() }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                Divider()
                Button("Delete Selection") { store.deleteCurrentSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                Divider()
                Button("Zoom In Timeline") {
                    store.zoomTimeline(by: TimelineScale.stepFactor)
                }
                .keyboardShortcut("=", modifiers: [.command])
                Button("Zoom Out Timeline") {
                    store.zoomTimeline(by: 1 / TimelineScale.stepFactor)
                }
                .keyboardShortcut("-", modifiers: [.command])
                Button("Fit Timeline") { store.fitTimeline() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
            CommandMenu("Export") {
                Button("Export Video…") {
                    store.presentExportSheet(destination: .file)
                }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Copy Video") {
                    store.presentExportSheet(destination: .clipboard)
                }
                Divider()
                Button("Copy Current Frame") { store.copyCurrentFrame() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Save Current Frame…") { store.saveCurrentFrame() }
            }
            CommandMenu("Language") {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        store.appLanguage = language
                    } label: {
                        if store.appLanguage == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            }
        }

        Settings {
            SettingsView(store: store)
                .environment(\.locale, store.appLanguage.locale)
        }
    }
}
