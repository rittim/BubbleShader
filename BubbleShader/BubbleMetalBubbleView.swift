import MetalKit
import SwiftUI

struct BubbleMetalBubbleView: UIViewRepresentable {
    let preset: BubblePreset
    let materialStyle: BubbleMaterialStyle
    let controls: BubbleControls

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(
            preset: preset,
            materialStyle: materialStyle,
            controls: controls
        )
    }

    func makeUIView(context: Context) -> MTKView {
        // Keep the MTKView transparent so SwiftUI owns the page/background composition.
        let device = MTLCreateSystemDefaultDevice()
        let view = MTKView(frame: .zero, device: device)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = true

        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.attach(to: uiView)
        context.coordinator.update(
            preset: preset,
            materialStyle: materialStyle,
            controls: controls,
            size: uiView.drawableSize
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        private var renderer: BubbleRenderer?
        private var preset: BubblePreset
        private var materialStyle: BubbleMaterialStyle
        private var controls: BubbleControls

        init(preset: BubblePreset, materialStyle: BubbleMaterialStyle, controls: BubbleControls) {
            self.preset = preset
            self.materialStyle = materialStyle
            self.controls = controls
            super.init()
        }

        func attach(to view: MTKView) {
            guard renderer == nil else {
                view.delegate = renderer
                return
            }

            guard let newRenderer = BubbleRenderer(
                view: view,
                preset: preset,
                materialStyle: materialStyle,
                controls: controls
            ) else {
                return
            }

            renderer = newRenderer
            view.delegate = newRenderer
        }

        func update(preset: BubblePreset, materialStyle: BubbleMaterialStyle, controls: BubbleControls, size: CGSize) {
            self.preset = preset
            self.materialStyle = materialStyle
            self.controls = controls
            renderer?.update(
                preset: preset,
                materialStyle: materialStyle,
                controls: controls,
                size: size
            )
        }
    }
}
