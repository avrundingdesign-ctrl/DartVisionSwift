import SwiftUI
import AVFoundation
import UIKit

/// Live-Vorschau der Kamera.
struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraController
    var fill = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = camera.engine.session
        view.previewLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        camera.attachPreview(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass garantiert den Typ.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
