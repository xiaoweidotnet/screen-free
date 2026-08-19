import AppKit
import ScreenFreeCore
import SwiftUI

extension AnnotationColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// Builds the stroke path for a recording-time annotation by mapping each
/// normalized point (source space, Y up) through `transform`. Shared by the
/// Core Animation export layer, the current-frame CGContext compositor, and
/// the SwiftUI preview so all three render identically.
///
/// `progress` replays the drawing gesture: 0 is the mouse-down instant, 1 the
/// completed shape. Brush strokes are revealed along their arc length; shape
/// kinds grow from the start corner toward the end corner, exactly matching
/// what the live drawing overlay showed while capturing. 1 (the default)
/// renders the finished annotation.
func annotationCGPath(
    for annotation: Annotation,
    progress: Double = 1,
    transform: (CGFloat, CGFloat) -> CGPoint
) -> CGPath {
    let clamped = progress.clamped(to: 0...1)
    let path = CGMutablePath()
    switch annotation.kind {
    case .brush:
        guard let first = annotation.points.first else { break }
        let firstPoint = transform(first.x, first.y)
        guard clamped > 0, annotation.points.count > 1 else {
            // A zero-length subpath still renders as a dot with round caps.
            path.move(to: firstPoint)
            path.addLine(to: firstPoint)
            break
        }
        let points = annotation.points.map { transform($0.x, $0.y) }
        var segmentLengths: [CGFloat] = []
        var totalLength: CGFloat = 0
        for index in 1..<points.count {
            let length = hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            )
            segmentLengths.append(length)
            totalLength += length
        }
        let targetLength = totalLength * CGFloat(clamped)
        path.move(to: points[0])
        var consumed: CGFloat = 0
        for index in 1..<points.count {
            let length = segmentLengths[index - 1]
            guard consumed + length < targetLength else {
                let fraction = length > 0
                    ? (targetLength - consumed) / length
                    : 1
                if fraction > 0 {
                    path.addLine(
                        to: interpolated(
                            points[index - 1], points[index], fraction
                        )
                    )
                }
                break
            }
            path.addLine(to: points[index])
            consumed += length
        }
    case .line, .arrow:
        let start = transform(
            annotation.normalizedStartX,
            annotation.normalizedStartY
        )
        let end = transform(
            annotation.normalizedEndX,
            annotation.normalizedEndY
        )
        let currentEnd = clamped >= 1
            ? end
            : interpolated(start, end, CGFloat(clamped))
        path.move(to: start)
        path.addLine(to: currentEnd)
        if annotation.kind == .arrow {
            addArrowHead(
                to: path,
                start: start,
                end: currentEnd,
                lineWidth: annotation.lineWidth
            )
        }
    case .rectangle:
        let start = transform(
            annotation.normalizedStartX,
            annotation.normalizedStartY
        )
        let end = transform(
            annotation.normalizedEndX,
            annotation.normalizedEndY
        )
        let currentEnd = clamped >= 1
            ? end
            : interpolated(start, end, CGFloat(clamped))
        path.addRoundedRect(
            in: CGRect(
                x: min(start.x, currentEnd.x),
                y: min(start.y, currentEnd.y),
                width: abs(currentEnd.x - start.x),
                height: abs(currentEnd.y - start.y)
            ),
            cornerWidth: 10,
            cornerHeight: 10
        )
    case .ellipse:
        let start = transform(
            annotation.normalizedStartX,
            annotation.normalizedStartY
        )
        let end = transform(
            annotation.normalizedEndX,
            annotation.normalizedEndY
        )
        let currentEnd = clamped >= 1
            ? end
            : interpolated(start, end, CGFloat(clamped))
        path.addEllipse(
            in: CGRect(
                x: min(start.x, currentEnd.x),
                y: min(start.y, currentEnd.y),
                width: abs(currentEnd.x - start.x),
                height: abs(currentEnd.y - start.y)
            )
        )
    }
    return path
}

private func interpolated(
    _ from: CGPoint,
    _ to: CGPoint,
    _ fraction: CGFloat
) -> CGPoint {
    CGPoint(
        x: from.x + (to.x - from.x) * fraction,
        y: from.y + (to.y - from.y) * fraction
    )
}

private func addArrowHead(
    to path: CGMutablePath,
    start: CGPoint,
    end: CGPoint,
    lineWidth: CGFloat
) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let headLength = max(14, lineWidth * 3.2)
    let spread = CGFloat.pi / 6
    let left = CGPoint(
        x: end.x - headLength * cos(angle - spread),
        y: end.y - headLength * sin(angle - spread)
    )
    let right = CGPoint(
        x: end.x - headLength * cos(angle + spread),
        y: end.y - headLength * sin(angle + spread)
    )
    path.move(to: end)
    path.addLine(to: left)
    path.move(to: end)
    path.addLine(to: right)
}
