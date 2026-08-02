import AppKit
import SwiftUI

@MainActor
final class AreaSelectionCoordinator {
    private var panel: AreaSelectionPanel?

    func present(
        onDisplayID displayID: UInt32?,
        initialSelection: CGRect,
        onConfirm: @escaping (CGRect) -> Void
    ) {
        let screen = screen(for: displayID) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let view = AreaSelectionView(
            initialSelection: initialSelection,
            displayPixelSize: displayPixelSize(for: screen),
            onCancel: { [weak self] in self?.dismiss() },
            onConfirm: { [weak self] selection in
                onConfirm(selection)
                self?.dismiss()
            }
        )
        let panel = AreaSelectionPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func screen(for displayID: UInt32?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }
    }

    private func displayPixelSize(for screen: NSScreen) -> CGSize {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return CGSize(
                width: screen.frame.width * screen.backingScaleFactor,
                height: screen.frame.height * screen.backingScaleFactor
            )
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return CGSize(
            width: CGDisplayPixelsWide(displayID),
            height: CGDisplayPixelsHigh(displayID)
        )
    }
}

private final class AreaSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct AreaSelectionView: View {
    let initialSelection: CGRect
    let displayPixelSize: CGSize
    let onCancel: () -> Void
    let onConfirm: (CGRect) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let initialRect = CGRect(
                x: geometry.size.width * initialSelection.minX,
                y: geometry.size.height * initialSelection.minY,
                width: geometry.size.width * initialSelection.width,
                height: geometry.size.height * initialSelection.height
            )
            let selection = currentRect ?? initialRect

            ZStack {
                Path { path in
                    path.addRect(
                        CGRect(origin: .zero, size: geometry.size)
                    )
                    path.addRect(selection)
                }
                .fill(
                    Color.black.opacity(0.48),
                    style: FillStyle(eoFill: true)
                )

                Rectangle()
                    .fill(.clear)
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .overlay {
                        Rectangle()
                            .stroke(Color.purple, lineWidth: 3)
                            .shadow(color: .purple.opacity(0.75), radius: 7)
                    }

                VStack {
                    Label(
                        "Drag anywhere to select a recording area",
                        systemImage: "viewfinder"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(.ultraThickMaterial, in: Capsule())
                    .padding(.top, 24)

                    Spacer()

                    HStack(spacing: 12) {
                        Text(
                            "\(Int((selection.width / geometry.size.width * displayPixelSize.width).rounded())) × \(Int((selection.height / geometry.size.height * displayPixelSize.height).rounded()))"
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                        Button("Cancel", action: onCancel)
                            .keyboardShortcut(.cancelAction)
                        Button("Use Area") {
                            let normalized = CGRect(
                                x: selection.minX / geometry.size.width,
                                y: selection.minY / geometry.size.height,
                                width: selection.width / geometry.size.width,
                                height: selection.height / geometry.size.height
                            )
                            onConfirm(normalized)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(selection.width < 80 || selection.height < 80)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(.ultraThickMaterial, in: Capsule())
                    .padding(.bottom, 28)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                        }
                        dragCurrent = value.location
                    }
            )
        }
        .ignoresSafeArea()
    }

    private var currentRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }
}
