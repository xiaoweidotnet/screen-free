import SwiftUI

struct ExportSheet: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Label("Export video", systemImage: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Text(store.formatted(store.project.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 44) {
                exportFormatSection
                    .frame(width: 250, alignment: .leading)
                frameRateSection
                    .frame(width: 220, alignment: .leading)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 44) {
                resolutionSection
                    .frame(width: 370, alignment: .leading)
                compressionSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            destinationSection

            Divider()
                .overlay(.white.opacity(0.08))

            if store.isVideoExporting {
                exportProgress
            }

            footer
        }
        .padding(30)
        .frame(width: 940)
        .background(StudioTheme.canvas)
        .tint(StudioTheme.accent)
        .interactiveDismissDisabled(store.isVideoExporting)
        .onChange(of: store.exportFormat) { _, format in
            store.exportFrameRate = ExportFrameRateOptions.normalized(
                store.exportFrameRate,
                for: format
            )
        }
    }

    private var exportFormatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExportSectionTitle(title: "Format", symbol: "video")
            HStack(spacing: 8) {
                ForEach(ExportFormat.allCases) { format in
                    ExportChoiceButton(
                        title: format.rawValue,
                        isSelected: store.exportFormat == format
                    ) {
                        store.exportFormat = format
                    }
                }
            }
        }
    }

    private var frameRateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExportSectionTitle(
                title: "Frame rate",
                symbol: "camera.aperture"
            )
            Menu {
                ForEach(
                    ExportFrameRateOptions.supported(
                        for: store.exportFormat
                    ),
                    id: \.self
                ) { frameRate in
                    Button {
                        store.exportFrameRate = frameRate
                    } label: {
                        if store.exportFrameRate == frameRate {
                            Label(
                                "\(frameRate) FPS",
                                systemImage: "checkmark"
                            )
                        } else {
                            Text("\(frameRate) FPS")
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("\(store.exportFrameRate) FPS")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15)
                .frame(height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(.white.opacity(0.045))
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 180)

            if store.exportFormat == .gif {
                Text("GIF exports are limited to 20 FPS to keep file size and rendering time practical.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExportSectionTitle(
                title: "Resolution",
                symbol: "rectangle.dashed"
            )
            HStack(spacing: 7) {
                ForEach(ExportResolution.allCases) { resolution in
                    ExportChoiceButton(
                        title: resolution.rawValue,
                        isSelected: store.exportResolution == resolution,
                        compact: true
                    ) {
                        store.exportResolution = resolution
                    }
                }
            }

            if store.exportResolution == .custom {
                HStack(spacing: 8) {
                    TextField(
                        "Width",
                        value: Binding(
                            get: { store.exportCustomWidth },
                            set: { store.setCustomExportWidth($0) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    Text("×")
                        .foregroundStyle(.secondary)
                    TextField(
                        "Height",
                        value: Binding(
                            get: { store.exportCustomHeight },
                            set: { store.setCustomExportHeight($0) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    Text("px")
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "\(store.resolvedExportDimensions.width)px × \(store.resolvedExportDimensions.height)px"
            )
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private var compressionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExportSectionTitle(
                title: "Compression",
                symbol: "scribble.variable"
            )
            HStack(spacing: 7) {
                ForEach(ExportQuality.allCases) { quality in
                    ExportChoiceButton(
                        title: quality.rawValue,
                        isSelected: store.exportQuality == quality,
                        compact: true
                    ) {
                        store.exportQuality = quality
                    }
                }
            }
            Text(LocalizedStringKey(store.exportQuality.explanation))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export to")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 9) {
                ForEach(ExportDestination.allCases) { destination in
                    ExportChoiceButton(
                        title: destination.rawValue,
                        symbol: destination.symbolName,
                        isSelected: store.exportDestination == destination
                    ) {
                        store.exportDestination = destination
                    }
                }
            }
            if store.exportDestination == .shareableLink {
                Text("The video is exported locally, then opened in the macOS sharing picker so you can create or send a link with an available service.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var exportProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rendering timeline edits…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    store.exportProgress,
                    format: .percent.precision(.fractionLength(0))
                )
                .font(.system(.caption, design: .monospaced))
            }
            ProgressView(value: store.exportProgress)
                .progressViewStyle(.linear)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(estimateText)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Spacer(minLength: 18)

            Button(store.isVideoExporting ? "Cancel export" : "Cancel") {
                if store.isVideoExporting {
                    store.cancelExport()
                } else {
                    store.isExportSheetPresented = false
                }
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(ExportFooterButtonStyle(isPrimary: false))

            Button {
                store.exportVideo()
            } label: {
                Label(
                    primaryActionTitle,
                    systemImage: store.exportDestination.symbolName
                )
                .frame(minWidth: 170)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(ExportFooterButtonStyle(isPrimary: true))
            .disabled(store.isVideoExporting)
        }
    }

    private var primaryActionTitle: LocalizedStringKey {
        switch store.exportDestination {
        case .file:
            return "Export to file…"
        case .clipboard:
            return "Export and copy"
        case .shareableLink:
            return "Export and share…"
        }
    }

    private var estimateText: String {
        let estimate = store.exportEstimate
        let size = ByteCountFormatter.string(
            fromByteCount: estimate.fileSizeBytes,
            countStyle: .file
        )
        let time: String
        if estimate.processingDuration < 60 {
            time = L10n.text(
                "less than a minute",
                language: store.appLanguage
            )
        } else {
            time = L10n.text(
                "about %d minutes",
                language: store.appLanguage,
                Int(ceil(estimate.processingDuration / 60))
            )
        }
        return L10n.text(
            "Estimation — Export time %@ — Output size %@",
            language: store.appLanguage,
            time,
            size
        )
    }
}

private struct ExportSectionTitle: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 15, weight: .semibold))
    }
}

private struct ExportChoiceButton: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(LocalizedStringKey(title))
                    .lineLimit(1)
            }
            .font(.system(size: compact ? 13 : 15, weight: .medium))
            .padding(.horizontal, compact ? 11 : 16)
            .frame(height: compact ? 40 : 46)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        isSelected
                            ? StudioTheme.accentMuted
                            : StudioTheme.raisedSurface
                    )
                    .stroke(
                        isSelected
                            ? StudioTheme.accent
                            : StudioTheme.border.opacity(0.58),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ExportFooterButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .foregroundStyle(isPrimary ? .white : .primary)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isPrimary
                            ? StudioTheme.accent.opacity(
                                configuration.isPressed ? 0.72 : 1
                            )
                            : Color.white.opacity(
                                configuration.isPressed ? 0.1 : 0.055
                            )
                    )
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
