import AVFoundation
import CoreImage
import ScreenFreeCore

final class RoundedCameraCompositionInstruction:
    NSObject,
    AVVideoCompositionInstructionProtocol,
    @unchecked Sendable
{
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let screenLayerInstruction: AVVideoCompositionLayerInstruction
    let cameraLayerInstruction: AVVideoCompositionLayerInstruction?
    let cameraFrame: CGRect
    let cameraCornerRadius: CGFloat
    let privacyRedactions: [PrivacyRedaction]

    init(
        timeRange: CMTimeRange,
        screenTrackID: CMPersistentTrackID,
        cameraTrackID: CMPersistentTrackID? = nil,
        screenLayerInstruction: AVVideoCompositionLayerInstruction,
        cameraLayerInstruction: AVVideoCompositionLayerInstruction? = nil,
        cameraFrame: CGRect = .zero,
        cameraCornerRadius: CGFloat = 0,
        privacyRedactions: [PrivacyRedaction] = []
    ) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
        self.screenLayerInstruction = screenLayerInstruction
        self.cameraLayerInstruction = cameraLayerInstruction
        self.cameraFrame = cameraFrame
        self.cameraCornerRadius = cameraCornerRadius
        self.privacyRedactions = privacyRedactions
        requiredSourceTrackIDs = [screenTrackID, cameraTrackID]
            .compactMap { $0 }
            .map { NSNumber(value: $0) }
        super.init()
    }
}

final class RoundedCameraVideoCompositor:
    NSObject,
    AVVideoCompositing,
    @unchecked Sendable
{
    private let context = CIContext()

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction
            as? RoundedCameraCompositionInstruction,
            let screenBuffer = request.sourceFrame(
                byTrackID: instruction.screenTrackID
            ),
            let destination = request.renderContext.newPixelBuffer() else {
            request.finish(
                with: NSError(
                    domain: "ScreenFree.RoundedCameraVideoCompositor",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The rounded camera frame could not be composed."
                    ]
                )
            )
            return
        }

        let bounds = CGRect(
            origin: .zero,
            size: request.renderContext.size
        )
        let screenTransform = transform(
            from: instruction.screenLayerInstruction,
            at: request.compositionTime
        )
        var result = CIImage(cvPixelBuffer: screenBuffer)
            .transformed(by: screenTransform)
            .cropped(to: bounds)

        if let cameraTrackID = instruction.cameraTrackID,
           let cameraLayerInstruction = instruction.cameraLayerInstruction,
           let cameraBuffer = request.sourceFrame(byTrackID: cameraTrackID) {
            let cameraTransform = transform(
                from: cameraLayerInstruction,
                at: request.compositionTime
            )
            let camera = CIImage(cvPixelBuffer: cameraBuffer)
                .transformed(by: cameraTransform)
                .cropped(to: instruction.cameraFrame)
            let black = CIImage(color: .black).cropped(to: bounds)
            let roundedMask = CIFilter(
                name: "CIRoundedRectangleGenerator",
                parameters: [
                    "inputExtent": CIVector(cgRect: instruction.cameraFrame),
                    "inputRadius": instruction.cameraCornerRadius,
                    "inputColor": CIColor.white
                ]
            )?.outputImage?
                .composited(over: black)
                .cropped(to: bounds)

            if let roundedMask {
                let transparent = CIImage(color: .clear).cropped(to: bounds)
                let roundedCamera = camera.applyingFilter(
                    "CIBlendWithMask",
                    parameters: [
                        kCIInputBackgroundImageKey: transparent,
                        kCIInputMaskImageKey: roundedMask
                    ]
                )
                result = roundedCamera
                    .composited(over: result)
                    .cropped(to: bounds)
            }
        }

        let timelineTime = request.compositionTime.seconds
        for redaction in instruction.privacyRedactions where
            redaction.resolvedPresentation == .redaction
                && redaction.resolvedEffect == .blur
                && timelineTime >= redaction.start
                && timelineTime <= redaction.end
        {
            result = applyPrivacyBlur(
                redaction,
                to: result,
                in: bounds
            )
        }

        context.render(
            result,
            to: destination,
            bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        request.finish(withComposedVideoFrame: destination)
    }

    private func applyPrivacyBlur(
        _ redaction: PrivacyRedaction,
        to image: CIImage,
        in bounds: CGRect
    ) -> CIImage {
        let width = bounds.width * redaction.normalizedWidth
        let height = bounds.height * redaction.normalizedHeight
        let region = CGRect(
            x: bounds.minX
                + bounds.width * redaction.normalizedX
                - width / 2,
            y: bounds.maxY
                - bounds.height * redaction.normalizedY
                - height / 2,
            width: width,
            height: height
        ).intersection(bounds)
        guard !region.isNull, region.width > 1, region.height > 1 else {
            return image
        }

        let radius = redaction.blurRadius(forRenderSize: bounds.size)
        let blurred = image
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius]
            )
            .cropped(to: bounds)
        let black = CIImage(color: .black).cropped(to: bounds)
        guard let whiteRegion = CIFilter(
            name: "CIRoundedRectangleGenerator",
            parameters: [
                "inputExtent": CIVector(cgRect: region),
                "inputRadius": min(12, min(region.width, region.height) / 2),
                "inputColor": CIColor.white
            ]
        )?.outputImage else {
            return image
        }
        let mask = whiteRegion
            .composited(over: black)
            .cropped(to: bounds)
        return blurred
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: mask
                ]
            )
            .cropped(to: bounds)
    }

    private func transform(
        from instruction: AVVideoCompositionLayerInstruction,
        at time: CMTime
    ) -> CGAffineTransform {
        var start = CGAffineTransform.identity
        var end = CGAffineTransform.identity
        var timeRange = CMTimeRange.invalid
        guard instruction.getTransformRamp(
            for: time,
            start: &start,
            end: &end,
            timeRange: &timeRange
        ) else {
            return start
        }
        guard timeRange.duration.isNumeric,
              timeRange.duration.seconds > 0 else {
            return start
        }
        let progress = (
            (time - timeRange.start).seconds / timeRange.duration.seconds
        ).clamped(to: 0...1)
        return CGAffineTransform(
            a: start.a + (end.a - start.a) * progress,
            b: start.b + (end.b - start.b) * progress,
            c: start.c + (end.c - start.c) * progress,
            d: start.d + (end.d - start.d) * progress,
            tx: start.tx + (end.tx - start.tx) * progress,
            ty: start.ty + (end.ty - start.ty) * progress
        )
    }
}
