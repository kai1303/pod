// The PDF interpreter emits ordered fills. Each fill already includes stroke
// expansion, glyph contours, page rotation and crop from the Zig renderer.
import Foundation
import Metal

private let tileSide = 32
private struct PaintCommand {
    var bounds: SIMD4<Float>
    var firstEdge: UInt32
    var edgeCount: UInt32
    var rgb: UInt32
    var opacity: Float
    var evenOdd: UInt32
    var multiply: UInt32
    var padding: (UInt32, UInt32) = (0, 0)
}

private final class PaintList {
    var edges: [SIMD4<Float>] = []
    var commands: [PaintCommand] = []

    func append(_ path: UnsafeBufferPointer<PodEdge>, rgb: UInt32, opacity: Double, evenOdd: Bool, multiply: Bool) -> Bool {
        // Very large or distant paths use the double-precision CPU fallback.
        guard path.count <= 2048, edges.count + path.count <= 1_000_000, commands.count < 100_000 else { return false }
        let start = UInt32(edges.count)
        var bounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for edge in path {
            let e = SIMD4(Float(edge.ax), Float(edge.ay), Float(edge.bx), Float(edge.by))
            guard max(abs(e.x), abs(e.y), abs(e.z), abs(e.w)) <= 65536 else { return false }
            bounds.x = min(bounds.x, e.x, e.z)
            bounds.y = min(bounds.y, e.y, e.w)
            bounds.z = max(bounds.z, e.x, e.z)
            bounds.w = max(bounds.w, e.y, e.w)
            edges.append(e)
        }
        commands.append(PaintCommand(bounds: bounds, firstEdge: start, edgeCount: UInt32(path.count),
                                     rgb: rgb, opacity: Float(opacity), evenOdd: evenOdd ? 1 : 0, multiply: multiply ? 1 : 0))
        return true
    }
}

final class MetalPageRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil),
              let kernel = library.makeFunction(name: "paintPage"),
              let pipeline = try? device.makeComputePipelineState(function: kernel) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func scene(document: OpaquePointer, page: Int, font: Data, width: Int) -> MetalPage? {
        let paints = PaintList()
        var height: UInt32 = 0
        var hairlines = false
        let ok = font.withUnsafeBytes { bytes in
            pod_collect_paints_with_blend(document, page, bytes.bindMemory(to: UInt8.self).baseAddress, font.count,
                               UInt32(width), Unmanaged.passUnretained(paints).toOpaque(), { context, edges, count, rgb, opacity, even, multiply in
                Unmanaged<PaintList>.fromOpaque(context!).takeUnretainedValue()
                    .append(UnsafeBufferPointer(start: edges, count: count), rgb: rgb, opacity: opacity, evenOdd: even, multiply: multiply)
            }, &height, &hairlines)
        }
        guard ok != 0 else { return nil }
        return MetalPage(renderer: self, paints: paints, width: width, height: Int(height), hairlines: hairlines)
    }

    fileprivate func encode(_ page: MetalPage, to texture: MTLTexture, origin: SIMD2<Float>,
                            step: SIMD2<Float>, command: MTLCommandBuffer) -> Bool {
        guard let encoder = command.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in page.buffers.enumerated() { encoder.setBuffer(buffer, offset: 0, index: index) }
        var transform = SIMD4<Float>(origin.x, origin.y, step.x, step.y)
        var size = SIMD2<UInt32>(UInt32(page.width), UInt32(page.height))
        encoder.setBytes(&transform, length: 16, index: 4)
        encoder.setBytes(&size, length: 8, index: 5)
        encoder.setTexture(texture, index: 0)
        encoder.dispatchThreads(MTLSize(width: texture.width, height: texture.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        return true
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Paint {
        float4 bounds;
        uint firstEdge, edgeCount, rgb;
        float opacity;
        uint evenOdd;
        uint multiply, pad0, pad1;
    };
    kernel void paintPage(device const float4 *edges [[buffer(0)]], device const Paint *paints [[buffer(1)]],
                          device const uint *offsets [[buffer(2)]], device const uint *indices [[buffer(3)]],
                          constant float4 &transform [[buffer(4)]], constant uint2 &size [[buffer(5)]],
                          texture2d<float, access::write> output [[texture(0)]], uint2 pixel [[thread_position_in_grid]]) {
        float2 step = transform.zw;
        float2 p = transform.xy + float2(pixel) * step;
        float3 color = 255.0;
        // Downsampled preview pixels may cross a tile boundary. Bins include
        // a one-tile halo, and callers limit the sample footprint to 32 pixels.
        uint2 tile = min(uint2(max(p, 0.0)), size - 1) / 32;
        uint bin = tile.y * ((size.x + 31) / 32) + tile.x;
        for (uint k = offsets[bin]; k < offsets[bin + 1]; ++k) {
            Paint paint = paints[indices[k]];
            if (any(p >= paint.bounds.zw) || any(p + step <= paint.bounds.xy)) continue;
            float4 xs = p.x + float4(0.125, 0.375, 0.625, 0.875) * step.x;
            int coverage = 0;
            for (uint row = 0; row < 4; ++row) {
                float y = p.y + (float(row) + 0.5) * 0.25 * step.y;
                int4 winding = 0;
                for (uint i = 0; i < paint.edgeCount; ++i) {
                    float4 e = edges[paint.firstEdge+i];
                    if (y < min(e.y,e.w) || y >= max(e.y,e.w)) continue;
                    float x = e.x + (y-e.y)*(e.z-e.x)/(e.w-e.y);
                    winding += select(int4(0), int4(e.w > e.y ? 1 : -1), xs >= x);
                }
                int4 inside = select(int4(0), int4(1), (paint.evenOdd ? (winding & 1) : winding) != 0);
                coverage += inside.x + inside.y + inside.z + inside.w;
            }
            float3 rgb = float3((paint.rgb >> 16) & 255, (paint.rgb >> 8) & 255, paint.rgb & 255);
            if (paint.multiply) rgb *= color / 255.0;
            color = floor(mix(color, rgb, float(coverage) * paint.opacity / 16.0) + 0.5);
        }
        output.write(float4(color / 255.0, 1.0), pixel);
    }
    """
}

final class MetalPage {
    let renderer: MetalPageRenderer
    let width: Int
    let height: Int
    let hairlines: Bool
    fileprivate let buffers: [MTLBuffer]

    fileprivate init?(renderer: MetalPageRenderer, paints: PaintList, width: Int, height: Int, hairlines: Bool) {
        self.hairlines = hairlines
        self.renderer = renderer
        self.width = width
        self.height = height
        let columns = (width + tileSide - 1) / tileSide
        let rows = (height + tileSide - 1) / tileSide
        var bins = Array(repeating: [UInt32](), count: columns * rows)
        var entries = 0
        var edgePixels = 0
        for (index, paint) in paints.commands.enumerated() {
            let b = paint.bounds
            let left = max(0, Int(floor(b.x / Float(tileSide))) - 1)
            let top = max(0, Int(floor(b.y / Float(tileSide))) - 1)
            let right = min(columns, Int(ceil(b.z / Float(tileSide))) + 1)
            let bottom = min(rows, Int(ceil(b.w / Float(tileSide))) + 1)
            guard top < bottom, left < right else { continue }
            let pixelWidth = max(0, min(width, Int(ceil(b.z))) - max(0, Int(floor(b.x))))
            let pixelHeight = max(0, min(height, Int(ceil(b.w))) - max(0, Int(floor(b.y))))
            edgePixels += pixelWidth * pixelHeight * Int(paint.edgeCount)
            guard edgePixels <= 300_000_000 else { return nil }
            entries += (bottom - top) * (right - left)
            guard entries <= 2_000_000 else { return nil }
            for y in top..<bottom {
                for x in left..<right { bins[y * columns + x].append(UInt32(index)) }
            }
        }
        var offsets: [UInt32] = [0]
        var indices = [UInt32]()
        indices.reserveCapacity(entries)
        for bin in bins {
            indices.append(contentsOf: bin)
            offsets.append(UInt32(indices.count))
        }
        func upload<T>(_ array: [T]) -> MTLBuffer? {
            if array.isEmpty { return renderer.device.makeBuffer(length: 16, options: .storageModeShared) }
            return array.withUnsafeBytes { renderer.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
        guard let edges = upload(paints.edges), let commands = upload(paints.commands),
              let ranges = upload(offsets), let members = upload(indices) else { return nil }
        buffers = [edges, commands, ranges, members]
    }

    func encode(to texture: MTLTexture, origin: SIMD2<Float>, step: SIMD2<Float>, command: MTLCommandBuffer) -> Bool {
        guard max(step.x, step.y) <= Float(tileSide) else { return false }
        return renderer.encode(self, to: texture, origin: origin, step: step, command: command)
    }

    // The document rail and React modal previews still need a small bitmap.
    func bitmap(width outputWidth: Int) -> PagePixels? {
        let outputHeight = max(1, Int(ceil(Double(height) * Double(outputWidth) / Double(width))))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: outputWidth, height: outputHeight, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderWrite
        guard let texture = renderer.device.makeTexture(descriptor: descriptor),
              let command = renderer.queue.makeCommandBuffer(),
              encode(to: texture, origin: .zero, step: SIMD2(Float(width)/Float(outputWidth), Float(height)/Float(outputHeight)), command: command) else { return nil }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let stride = outputWidth * 4
        var data = Data(count: stride * outputHeight)
        data.withUnsafeMutableBytes { bytes in texture.getBytes(bytes.baseAddress!, bytesPerRow: stride, from: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0) }
        return PagePixels(data: data, width: outputWidth, height: outputHeight)
    }
}
