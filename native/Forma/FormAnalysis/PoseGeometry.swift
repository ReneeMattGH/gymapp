import CoreGraphics
import Foundation

enum PoseGeometry {
    /// Vision normalises x and y independently, so a raw normalised angle is
    /// skewed by the frame aspect ratio. Scaling x by width/height restores the
    /// true planar angle without needing pixel dimensions.
    static func corrected(_ point: CGPoint, aspectRatio: CGFloat) -> CGPoint {
        CGPoint(x: point.x * aspectRatio, y: point.y)
    }

    /// Interior angle at `b` in degrees (0...180), or nil for a degenerate triangle.
    static func angle(a: CGPoint, b: CGPoint, c: CGPoint, aspectRatio: CGFloat) -> Double? {
        let pa = corrected(a, aspectRatio: aspectRatio)
        let pb = corrected(b, aspectRatio: aspectRatio)
        let pc = corrected(c, aspectRatio: aspectRatio)

        let first = CGVector(dx: pa.x - pb.x, dy: pa.y - pb.y)
        let second = CGVector(dx: pc.x - pb.x, dy: pc.y - pb.y)
        let firstLength = Double(hypot(first.dx, first.dy))
        let secondLength = Double(hypot(second.dx, second.dy))
        guard firstLength > 1e-6, secondLength > 1e-6 else { return nil }

        let dot = Double(first.dx * second.dx + first.dy * second.dy)
        let cosine = dot / (firstLength * secondLength)
        return acos(min(1, max(-1, cosine))) * 180 / Double.pi
    }

    /// Angle between the vector `lower → upper` and the vertical axis in degrees.
    /// 0 means the segment is upright, 90 means horizontal. Note Vision's y axis
    /// points upward, so this is computed in Vision space, not screen space.
    static func verticalAngle(from lower: CGPoint, to upper: CGPoint, aspectRatio: CGFloat) -> Double? {
        let lo = corrected(lower, aspectRatio: aspectRatio)
        let hi = corrected(upper, aspectRatio: aspectRatio)
        let dx = hi.x - lo.x
        let dy = hi.y - lo.y
        guard hypot(dx, dy) > 1e-6 else { return nil }
        return Double(abs(atan2(dx, dy))) * 180 / Double.pi
    }

    static func distance(_ a: CGPoint, _ b: CGPoint, aspectRatio: CGFloat) -> Double {
        let pa = corrected(a, aspectRatio: aspectRatio)
        let pb = corrected(b, aspectRatio: aspectRatio)
        return hypot(pa.x - pb.x, pa.y - pb.y)
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Maps a measured value onto 0...1 between `start` and `end`.
    /// Works for descending ranges (start > end) as used by joint-angle signals.
    static func progress(value: Double, start: Double, end: Double) -> Double {
        guard abs(start - end) > 0.0001 else { return 0 }
        let raw = (value - start) / (end - start)
        return min(1, max(0, raw))
    }

    /// Ratio of `numerator` to `reference`, clamped to a sane range so an
    /// implausible detector reading cannot produce a wild signal.
    static func ratio(_ numerator: Double, to reference: Double, maximum: Double = 4) -> Double {
        guard reference > 1e-6 else { return 0 }
        return min(maximum, max(0, numerator / reference))
    }
}
