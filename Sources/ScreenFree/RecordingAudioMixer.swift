import AVFoundation
import Foundation

enum RecordingAudioMixError: LocalizedError {
    case missingPrimaryVideo
    case cannotCreateTrack
    case cannotCreateExportSession
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingPrimaryVideo:
            return "The screen recording did not contain a video track."
        case .cannotCreateTrack:
            return "The selected application audio could not be added."
        case .cannotCreateExportSession:
            return "The selected application audio mix could not start."
        case .exportFailed:
            return "The selected application audio could not be finalized."
        }
    }
}

struct SupplementalAudioRecording: Sendable {
    let url: URL
    let firstPresentationTime: CMTime
}

struct RecordingAudioMixer {
    func mix(
        primaryURL: URL,
        supplemental: SupplementalAudioRecording,
        primaryFirstPresentationTime: CMTime?
    ) async throws -> URL {
        let primaryAsset = AVURLAsset(url: primaryURL)
        let primaryDuration = try await primaryAsset.load(.duration)
        guard let sourceVideoTrack = try await primaryAsset.loadTracks(
            withMediaType: .video
        ).first else {
            throw RecordingAudioMixError.missingPrimaryVideo
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingAudioMixError.cannotCreateTrack
        }
        let videoRange = try await sourceVideoTrack.load(.timeRange)
        try videoTrack.insertTimeRange(
            videoRange,
            of: sourceVideoTrack,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideoTrack.load(
            .preferredTransform
        )

        for sourceAudioTrack in try await primaryAsset.loadTracks(
            withMediaType: .audio
        ) {
            guard let destination = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecordingAudioMixError.cannotCreateTrack
            }
            let sourceRange = try await sourceAudioTrack.load(.timeRange)
            let duration = CMTimeMinimum(primaryDuration, sourceRange.duration)
            guard duration > .zero else { continue }
            try destination.insertTimeRange(
                CMTimeRange(start: sourceRange.start, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        let supplementalAsset = AVURLAsset(url: supplemental.url)
        if let sourceAudioTrack = try await supplementalAsset.loadTracks(
            withMediaType: .audio
        ).first {
            let sourceRange = try await sourceAudioTrack.load(.timeRange)
            let offset: CMTime
            if let primaryFirstPresentationTime {
                offset = supplemental.firstPresentationTime
                    - primaryFirstPresentationTime
            } else {
                offset = .zero
            }
            let destinationStart = CMTimeMaximum(.zero, offset)
            let sourceTrim = CMTimeMaximum(.zero, .zero - offset)
            let sourceStart = sourceRange.start + sourceTrim
            let availableSource = sourceRange.duration - sourceTrim
            let availableDestination = primaryDuration - destinationStart
            let duration = CMTimeMinimum(
                availableSource,
                availableDestination
            )
            if duration > .zero {
                guard let destination = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw RecordingAudioMixError.cannotCreateTrack
                }
                try destination.insertTimeRange(
                    CMTimeRange(start: sourceStart, duration: duration),
                    of: sourceAudioTrack,
                    at: destinationStart
                )
            }
        }

        let outputURL = primaryURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Mixed-\(UUID().uuidString).mp4"
            )
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw RecordingAudioMixError.cannotCreateExportSession
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? RecordingAudioMixError.exportFailed
        }
        return outputURL
    }
}
