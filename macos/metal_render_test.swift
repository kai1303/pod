import Foundation
import Metal

@main struct MetalRenderChecks {
    static func main() throws {
        guard let renderer = MetalPageRenderer() else {
            if MTLCreateSystemDefaultDevice() != nil { fatalError("Metal pipeline did not compile") }
            print("Metal comparison skipped: no Metal device")
            return
        }
        let cpu = try Engine()
        let gpu = try Engine(metal: renderer)
        let pdf = try Engine.read(URL(fileURLWithPath: CommandLine.arguments[1]))
        let cropped = try cpu.crop(pdf, page: 0, box: CGRect(x: 20, y: 30, width: 480, height: 670))
        var style = MarkupStyle.initial(for: .highlight)
        style.opacity = 0.5
        let a = Markup(kind: .highlight, points: [CGPoint(x: 80, y: 590), CGPoint(x: 280, y: 620)], rect: .zero, style: style)
        let marked = try cpu.annotate(pdf, page: 0, marks: [a, a.translated(x: 40, y: 8)])
        let markedFile = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("annotations.pdf")
        var cases = [(pdf, 612), (pdf, 1224), (pdf, 2400), (marked, 612)]
        for degrees in [90,180,270] { cases.append((try cpu.rotate(cropped, page: 0, degrees: Int32(degrees)), 615)) }
        if FileManager.default.fileExists(atPath: markedFile.path) { cases.append((try Engine.read(markedFile), 612)) }
        let groupedInk = markedFile.deletingLastPathComponent().appendingPathComponent("grouped-ink.pdf")
        if FileManager.default.fileExists(atPath: groupedInk.path) { cases.append((try Engine.read(groupedInk), 612)) }
        let rules = try Engine.read(URL(fileURLWithPath: CommandLine.arguments[2]))
        let hairline = try gpu.load(rules, page: 0, width: 612)
        precondition(hairline.metalPage?.hairlines == true)
        cases.append((rules, 612))
        let large = try Engine.read(URL(fileURLWithPath: CommandLine.arguments[3]))
        let fallback = try gpu.load(large, page: 0, width: 612)
        let cpuLarge = try cpu.load(large, page: 0, width: 612)
        precondition(fallback.metalPage == nil && fallback.pixels.data == cpuLarge.pixels.data)
        for (bytes, width) in cases {
            let reference = try cpu.load(bytes, page: 0, width: width)
            let loaded = try gpu.load(bytes, page: 0, width: width)
            guard let page = loaded.metalPage else { fatalError("Expected the Metal path") }
            let start = ProcessInfo.processInfo.systemUptime
            guard let pixels = page.bitmap(width: width) else { fatalError("GPU submission failed") }
            let paintMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
            precondition(reference.pixels.width == pixels.width && reference.pixels.height == pixels.height)
            compare(pixels.data, reference.pixels.data)
            // A scrolled viewport starts inside a tile and cuts through glyphs.
            let x = 37, y = 59, w = 227, h = 171
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = .shaderWrite
            desc.storageMode = .shared
            let texture = renderer.device.makeTexture(descriptor: desc)!
            let command = renderer.queue.makeCommandBuffer()!
            precondition(page.encode(to: texture, origin: SIMD2(Float(x),Float(y)), step: SIMD2(repeating: 1), command: command))
            command.commit(); command.waitUntilCompleted()
            precondition(command.status == .completed)
            var region = Data(count: w*h*4)
            region.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: w*4, from: MTLRegionMake2D(0,0,w,h), mipmapLevel: 0) }
            for row in 0..<h {
                let source = ((y+row)*width+x)*4
                precondition(region[(row*w*4)..<((row+1)*w*4)] == pixels.data[source..<(source+w*4)])
            }
            print(String(format: "%d px: CPU %.2f ms, metadata %.2f ms, Metal scene + preview %.2f ms, full Metal paint + readback %.2f ms",
                         width, reference.elapsedMS - reference.metadataMS, loaded.metadataMS, loaded.elapsedMS-loaded.metadataMS, paintMS))
        }
        print("Metal/CPU and viewport comparisons passed on " + renderer.device.name)
    }

    static func compare(_ actual: Data, _ expected: Data) {
        precondition(actual.count == expected.count)
        var different = 0, worst = 0
        for (a, b) in zip(actual, expected) {
            let delta = abs(Int(a)-Int(b))
            if delta > 1 { different += 1 }
            worst = max(worst, delta)
        }
        // Float versus double can move a subsample exactly on a contour.
        precondition(worst <= 32 && different <= max(8, actual.count / 2000),
                     "CPU/Metal mismatch: \(different) channels, worst \(worst)")
    }
}
