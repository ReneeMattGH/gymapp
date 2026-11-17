import SwiftUI
import AVFoundation

/// Maps Vision's normalised bottom-left coordinates onto an aspect-fill preview.
struct PosePreviewMapper {
    let videoSize: CGSize
    let viewSize: CGSize

    var scale: CGFloat {
        guard videoSize.width > 0, videoSize.height > 0 else { return 1 }
        return max(viewSize.width / videoSize.width, viewSize.height / videoSize.height)
    }

    var scaledSize: CGSize {
        CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
    }

    var origin: CGPoint {
        CGPoint(
            x: (viewSize.width - scaledSize.width) / 2,
            y: (viewSize.height - scaledSize.height) / 2
        )
    }

    func point(_ normalized: CGPoint) -> CGPoint {
        let scaled = scaledSize
        let offset = origin
        return CGPoint(
            x: offset.x + normalized.x * scaled.width,
            y: offset.y + (1 - normalized.y) * scaled.height
        )
    }
}

struct CameraPreviewView: View {
    @Environment(\.formaPalette) private var palette
    let previewLayer: AVCaptureVideoPreviewLayer
    var poseFrame: PoseFrame?
    var isLimited = false

    private var skeletonTint: Color {
        isLimited ? palette.warning : palette.accent
    }

    var body: some View {
        ZStack {
            PreviewLayerHost(cameraLayer: previewLayer)
            if let poseFrame, poseFrame.videoSize.width > 0 {
                PoseSkeletonOverlay(poseFrame: poseFrame, tint: skeletonTint)
                    .opacity(isLimited ? 0.65 : 1)
            }
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [9, 9]))
                .padding(18)
                .allowsHitTesting(false)
        }
        .background(Color.black)
        .clipped()
    }
}

private struct PreviewLayerHost: UIViewRepresentable {
    let cameraLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewLayerContainerView {
        PreviewLayerContainerView(cameraLayer: cameraLayer)
    }

    func updateUIView(_ uiView: PreviewLayerContainerView, context: Context) {}
}

private final class PreviewLayerContainerView: UIView {
    private let cameraLayer: AVCaptureVideoPreviewLayer

    init(cameraLayer: AVCaptureVideoPreviewLayer) {
        self.cameraLayer = cameraLayer
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(cameraLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cameraLayer.frame = bounds
    }
}

struct PoseSkeletonOverlay: View {
    let poseFrame: PoseFrame
    var tint: Color

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let mapper = PosePreviewMapper(videoSize: poseFrame.videoSize, viewSize: size)

            for (first, second) in BodySkeleton.connections {
                guard let a = poseFrame.sample(first), let b = poseFrame.sample(second) else { continue }
                var path = Path()
                path.move(to: mapper.point(a.position))
                path.addLine(to: mapper.point(b.position))
                let confidence = Double(min(a.confidence, b.confidence))
                context.stroke(
                    path,
                    with: .color(tint.opacity(0.35 + 0.6 * confidence)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }

            for sample in poseFrame.joints.values where sample.isUsable() {
                let point = mapper.point(sample.position)
                let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(tint.opacity(0.5 + 0.5 * sample.confidence))
                )
            }
        }
    }
}
