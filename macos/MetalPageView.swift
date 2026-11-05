import AppKit
import MetalKit

// Only the intersection of the PDF and the scroll viewport owns a drawable.
final class MetalPageView: MTKView {
    var scene: MetalPage?
    private weak var presentedScene: MetalPage?
    private var presentedRect = CGRect.null
    private(set) var presentationTime: CFTimeInterval = 0
    var didPresentViewport: Bool { scene != nil && presentedScene === scene && sourceRect == presentedRect }
    var sourceRect = CGRect.zero
    var onPresentation: ((MetalPage) -> Void)?
    var onFailure: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(device: MTLDevice) {
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        colorspace = CGColorSpaceCreateDeviceRGB()
    }

    required init(coder: NSCoder) { fatalError("Unsupported initializer") }

    override func draw(_ dirtyRect: NSRect) {
        guard let scene, !sourceRect.isEmpty, let drawable = currentDrawable else { return }
        let texture = drawable.texture
        let step = SIMD2(Float(sourceRect.width) / Float(texture.width), Float(sourceRect.height) / Float(texture.height))
        guard let command = scene.renderer.queue.makeCommandBuffer(),
              scene.encode(to: texture, origin: SIMD2(Float(sourceRect.minX), Float(sourceRect.minY)),
                           step: step, command: command) else { onFailure?(); return }
        if !didPresentViewport {
            let submittedRect = sourceRect
            drawable.addPresentedHandler { [weak self, weak scene] _ in
                // A drawable can report a zero scanout timestamp. Measure the
                // callback against the same monotonic clock as the UI harness.
                let time = CACurrentMediaTime()
                DispatchQueue.main.async {
                    guard let self, let scene, self.scene === scene else { return }
                    self.presentedScene = scene
                    self.presentedRect = submittedRect
                    self.presentationTime = time
                    if self.sourceRect == submittedRect { self.onPresentation?(scene) }
                }
            }
        }
        command.present(drawable)
        command.addCompletedHandler { [weak self, weak scene] buffer in
            if buffer.status == .error {
                DispatchQueue.main.async { if let self, self.scene === scene { self.onFailure?() } }
            }
        }
        command.commit()
    }
}

// Preserve the existing AppKit drawing and mouse handling above the Metal view.
final class PageOverlayView: NSView {
    weak var canvas: PageCanvas?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let canvas else { return }
        let transform = NSAffineTransform()
        transform.translateX(by: -frame.minX, yBy: -frame.minY)
        transform.concat()
        canvas.drawOverlays()
    }
}
