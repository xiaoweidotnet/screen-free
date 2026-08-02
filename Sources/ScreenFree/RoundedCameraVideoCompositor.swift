import AVFoundation
import CoreImage

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
    let cameraTrackID: CMPersistentTrackID
    let screenLayerInstruction: AVVideoCompositionLayerInstruction
    let cameraLayerInstruction: AVVideoCompositionLayerInstruction
    let cameraFrame: CGRect
    let cameraCornerRadius: CGFloat

    init(
        timeRange: CMTimeRange,
        screenTrackID: CMPersistentTrackID,
        cameraTrackID: CMPersistentTrackID,
        screenLayerInstruction: AVVideoCompositionLayerInstruction,
        cameraLayerInstruction: AVVideoCompositionLayerInstruction,
        cameraFrame: CGRect,
        cameraCornerRadius: CGFloat
    ) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
        self.screenLayerInstruction = screenLayerInstruction
        self.cameraLayerInstruction = cameraLayerInstruction
        self.cameraFrame = cameraFrame
        self.cameraCornerRadius = cameraCornerRadius
        requiredSourceTrackIDs = [
            NSNumber(value: screenTrackID),
            NSNumber(value: cameraTrackID)
        ]
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

        if let cameraBuffer = request.sourceFrame(
            byTrackID: instruction.cameraTrackID
        ) {
            let cameraTransform = transform(
                from: instruction.cameraLayerInstruction,
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

        context.render(
            result,
            to: destination,
            bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        request.finish(withComposedVideoFrame: destination)
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
