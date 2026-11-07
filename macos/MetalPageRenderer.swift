// The Zig renderer emits ordered vector fills and sampled images. Vector paths
// include stroke expansion, glyph contours, page rotation and clipping.
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
    var blendMode: UInt32
    var group: UInt32
    var padding: UInt32 = 0
    var image: SIMD4<UInt32> = .zero
    var inverseX: SIMD4<Float> = .zero
    var inverseY: SIMD4<Float> = .zero
    var mask: SIMD4<UInt32> = .zero
}

private final class PaintList {
    var edges: [SIMD4<Float>] = []
    var commands: [PaintCommand] = []
    var pixels: [UInt8] = []

    func appendImage(_ path: UnsafeBufferPointer<PodEdge>, image: PodImagePaint, opacity: Double, blendMode: UInt32, group: UInt32) -> Bool {
        let count = Int(image.width) * Int(image.height) * 4
        let maskCount = Int(image.mask_width) * Int(image.mask_height)
        guard count <= 64 * 1024 * 1024, maskCount <= 16 * 1024 * 1024,
              pixels.count + count + maskCount * 4 <= 256 * 1024 * 1024,
              append(path, rgb:0, opacity:opacity, evenOdd:false, blendMode:blendMode, group:group) else { return false }
        let m = image.inverse
        let x = SIMD4(Float(m.0),Float(m.2),Float(m.4),0)
        let y = SIMD4(Float(m.1),Float(m.3),Float(m.5),0)
        guard (0..<3).allSatisfy({ abs(x[$0]) <= 65536 && abs(y[$0]) <= 65536 }) else { return false }
        let last = commands.count-1
        commands[last].image = SIMD4(UInt32(pixels.count/4),image.width,image.height,image.interpolate ? 1:0)
        commands[last].inverseX = x
        commands[last].inverseY = y
        pixels.append(contentsOf:UnsafeBufferPointer(start:image.pixels,count:count))
        if let alpha = image.mask_alpha {
            commands[last].mask = SIMD4(UInt32(pixels.count/4),image.mask_width,image.mask_height,image.mask_interpolate ? 1:0)
            pixels.append(contentsOf:UnsafeRawBufferPointer(start:alpha,count:maskCount*4))
        }
        return true
    }

    func append(_ path: UnsafeBufferPointer<PodEdge>, rgb: UInt32, opacity: Double, evenOdd: Bool, blendMode: UInt32, group: UInt32) -> Bool {
        // Very large or distant paths use the double-precision CPU fallback.
        guard blendMode <= 15, path.count <= 65536, edges.count + path.count <= 1_000_000, commands.count < 100_000 else { return false }
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
                                     rgb: rgb, opacity: Float(opacity), evenOdd: evenOdd ? 1 : 0, blendMode: blendMode, group: group))
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
        font.withUnsafeBytes { bytes in
            scene(document:document,page:page,fonts:[PodFontSource(face:0,data:bytes.bindMemory(to:UInt8.self).baseAddress,length:font.count)],width:width)
        }
    }

    func scene(document: OpaquePointer, page: Int, fonts: [PodFontSource], width: Int) -> MetalPage? {
        collectedScene(document:document,page:page,annotation:nil,fonts:fonts,width:width)
    }

    func annotationAppearance(document: OpaquePointer, page: Int, annotation: UInt32, fonts: [PodFontSource], width: Int) -> MetalPage? {
        collectedScene(document:document,page:page,annotation:annotation,fonts:fonts,width:width)
    }

    func pageView(document: OpaquePointer, page: Int, fonts: [PodFontSource], width: Int, zoom: Double, rotation: Int) -> MetalPage? {
        guard [0,90,180,270].contains(rotation) else { return nil }
        return collectedScene(document:document,page:page,annotation:nil,fonts:fonts,width:width,view:(zoom,Int32(rotation)))
    }

    private func collectedScene(document: OpaquePointer, page: Int, annotation: UInt32?, fonts: [PodFontSource], width: Int, view: (zoom: Double, rotation: Int32)? = nil) -> MetalPage? {
        guard (1...4096).contains(width) else { return nil }
        let paints = PaintList()
        var height: UInt32 = 0
        var hairlines = false
        let callback: PodCompositePaintCallback = { context, edges, count, rgb, opacity, even, blendMode, group in
            Unmanaged<PaintList>.fromOpaque(context!).takeUnretainedValue()
                .append(UnsafeBufferPointer(start: edges, count: count), rgb: rgb, opacity: opacity, evenOdd: even, blendMode: blendMode, group: group)
        }
        let context = Unmanaged.passUnretained(paints).toOpaque()
        let imageCallback: PodImagePaintCallback = { context, edges, count, image, opacity, blendMode, group in
            Unmanaged<PaintList>.fromOpaque(context!).takeUnretainedValue()
                .appendImage(UnsafeBufferPointer(start:edges,count:count),image:image!.pointee,opacity:opacity,blendMode:blendMode,group:group)
        }
        let ok = pod_collect_image_scene(document,page,annotation ?? 0,fonts,fonts.count,UInt32(width),view?.zoom ?? 1,view?.rotation ?? 0,context,callback,imageCallback,&height,&hairlines)
        guard ok != 0 else { return nil }
        return MetalPage(renderer: self, paints: paints, width: width, height: Int(height), hairlines: hairlines)
    }

    fileprivate func encode(_ page: MetalPage, to texture: MTLTexture, origin: SIMD2<Float>,
                            step: SIMD2<Float>, command: MTLCommandBuffer) -> Bool {
        guard let encoder = command.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in page.buffers.enumerated() { encoder.setBuffer(buffer, offset: 0, index: index == 4 ? 6:index) }
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
        uint blendMode, group, pad;
        uint4 image;
        float4 inverseX, inverseY;
        uint4 mask;
    };
    float luminance(float3 c) { return dot(c, float3(0.3, 0.59, 0.11)); }
    float saturation(float3 c) { return max(c.r,max(c.g,c.b)) - min(c.r,min(c.g,c.b)); }
    float3 setLum(float3 c, float value) {
        c += value - luminance(c);
        float low = min(c.r,min(c.g,c.b)), high = max(c.r,max(c.g,c.b));
        if (low < 0.0) c = value + (c-value)*value/(value-low);
        if (high > 1.0) c = value + (c-value)*(1.0-value)/(high-value);
        return c;
    }
    float3 setSat(float3 c, float value) {
        float low = min(c.r,min(c.g,c.b));
        float range = max(c.r,max(c.g,c.b)) - low;
        return range == 0.0 ? float3(0.0) : (c-low)*value/range;
    }
    float hardLight(float b, float s) { return s <= 0.5 ? 2.0*b*s : 1.0-2.0*(1.0-b)*(1.0-s); }
    float blendChannel(uint mode, float b, float s) {
        switch (mode) {
            case 0: return s;
            case 1: return b*s;
            case 2: return b+s-b*s;
            case 3: return hardLight(s,b);
            case 4: return min(b,s);
            case 5: return max(b,s);
            case 6: return b == 0.0 ? 0.0 : s == 1.0 ? 1.0 : min(1.0,b/(1.0-s));
            case 7: return b == 1.0 ? 1.0 : s == 0.0 ? 0.0 : 1.0-min(1.0,(1.0-b)/s);
            case 8: return hardLight(b,s);
            case 9: return s <= 0.5 ? b-(1.0-2.0*s)*b*(1.0-b) : b+(2.0*s-1.0)*((b <= 0.25 ? ((16.0*b-12.0)*b+4.0)*b : sqrt(b))-b);
            case 10: return abs(b-s);
            case 11: return b+s-2.0*b*s;
        }
        return s;
    }
    float3 blendRGB(uint mode, float3 b, float3 s) {
        float3 result;
        switch (mode) {
            case 12: result = setLum(setSat(s,saturation(b)),luminance(b)); break;
            case 13: result = setLum(setSat(b,saturation(s)),luminance(b)); break;
            case 14: result = setLum(s,luminance(b)); break;
            case 15: result = setLum(b,luminance(s)); break;
            default: result = float3(blendChannel(mode,b.r,s.r),blendChannel(mode,b.g,s.g),blendChannel(mode,b.b,s.b));
        }
        return clamp(result,0.0,1.0);
    }
    float4 imageTexel(device const uchar4 *pixels, Paint paint, int2 pos) {
        pos = clamp(pos, int2(0), int2(paint.image.yz)-1);
        float4 value = float4(pixels[paint.image.x + uint(pos.y)*paint.image.y + uint(pos.x)]);
        value.a /= 255.0;
        return value;
    }
    float4 imagePlaneSample(device const uchar4 *pixels, Paint paint, float2 uv) {
        float2 size = float2(paint.image.yz);
        float2 position = clamp(float2(uv.x,1.0-uv.y)*size,0.0,size);
        if (!paint.image.w) return imageTexel(pixels,paint,int2(floor(position)));
        float2 corner = floor(position-0.5);
        float2 part = position-0.5-corner;
        float4 value = 0.0;
        for (int y=0;y<2;++y) for (int x=0;x<2;++x) {
            float4 sample = imageTexel(pixels,paint,int2(corner)+int2(x,y));
            float weight = (x ? part.x:1.0-part.x)*(y ? part.y:1.0-part.y)*sample.a;
            value.rgb += sample.rgb*weight;
            value.a += weight;
        }
        if (value.a>0.0) value.rgb /= value.a;
        value.rgb = floor(value.rgb+0.5);
        return value;
    }
    float maskTexel(device const float *samples, uint4 mask, int2 pos) {
        pos = clamp(pos,int2(0),int2(mask.yz)-1);
        return samples[mask.x+uint(pos.y)*mask.y+uint(pos.x)];
    }
    float maskSample(device const float *samples, uint4 mask, float2 uv) {
        float2 size = float2(mask.yz);
        float2 position = clamp(float2(uv.x,1.0-uv.y)*size,0.0,size);
        if (!mask.w) return maskTexel(samples,mask,int2(floor(position)));
        float2 corner = floor(position-0.5), part = position-0.5-corner;
        float value = 0.0;
        for (int y=0;y<2;++y) for (int x=0;x<2;++x)
            value += maskTexel(samples,mask,int2(corner)+int2(x,y))*(x ? part.x:1.0-part.x)*(y ? part.y:1.0-part.y);
        return value;
    }
    float4 imageSample(device const uchar4 *pixels, Paint paint, float2 p) {
        float3 point = float3(p,1.0);
        float2 uv = float2(dot(paint.inverseX.xyz,point),dot(paint.inverseY.xyz,point));
        float4 value = imagePlaneSample(pixels,paint,uv);
        if (paint.mask.y) value.a = maskSample((device const float *)pixels,paint.mask,uv);
        return value;
    }
    kernel void paintPage(device const float4 *edges [[buffer(0)]], device const Paint *paints [[buffer(1)]],
                          device const uint *offsets [[buffer(2)]], device const uint *indices [[buffer(3)]],
                          constant float4 &transform [[buffer(4)]], constant uint2 &size [[buffer(5)]],
                          device const uchar4 *pixels [[buffer(6)]],
                          texture2d<float, access::write> output [[texture(0)]], uint2 pixel [[thread_position_in_grid]]) {
        float2 step = transform.zw;
        float2 p = transform.xy + float2(pixel) * step;
        float3 color = 255.0;
        float3 backdrop = 255.0;
        uint group = 0;
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
            if (!coverage) continue;
            float opacity = paint.opacity;
            if (paint.image.y) {
                float4 sample = imageSample(pixels,paint,p+step*0.5);
                rgb = sample.rgb;
                opacity *= sample.a;
            }
            if (paint.group && paint.group != group) { backdrop = color; group = paint.group; }
            float3 background = paint.group ? backdrop : color;
            rgb = blendRGB(paint.blendMode,background/255.0,rgb/255.0)*255.0;
            float3 composite = mix(background, rgb, opacity);
            color = floor(mix(color, composite, float(coverage) / 16.0) + 0.5);
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
        var edges = paints.edges
        var commands = paints.commands
        for (index, paint) in paints.commands.enumerated() {
            let b = paint.bounds
            let left = max(0, Int(floor(b.x / Float(tileSide))) - 1)
            let top = max(0, Int(floor(b.y / Float(tileSide))) - 1)
            let right = min(columns, Int(ceil(b.z / Float(tileSide))) + 1)
            let bottom = min(rows, Int(ceil(b.w / Float(tileSide))) + 1)
            guard top < bottom, left < right else { continue }
            let pixelWidth = max(0, min(width, Int(ceil(b.z))) - max(0, Int(floor(b.x))))
            let pixelHeight = max(0, min(height, Int(ceil(b.w))) - max(0, Int(floor(b.y))))
            let work = pixelWidth * pixelHeight * Int(paint.edgeCount)
            entries += (bottom - top) * (right - left)
            guard entries <= 2_000_000 else { return nil }
            if paint.edgeCount <= 2048 && work <= 8_000_000 {
                edgePixels += work
                guard edgePixels <= 300_000_000 else { return nil }
                for y in top..<bottom {
                    for x in left..<right { bins[y * columns + x].append(UInt32(index)) }
                }
            } else {
                // Winding uses only edges crossing the sample's y. Keep the next
                // tile for preview footprints, and one paint per original draw
                // in each bin, preserving opacity and knockout exactly.
                let source=paints.edges[Int(paint.firstEdge)..<Int(paint.firstEdge+paint.edgeCount)]
                for y in top..<bottom {
                    let low=Float(y == 0 ? -tileSide:y*tileSide), high=Float((y+2)*tileSide)
                    let start=edges.count
                    for edge in source where min(edge.y,edge.w)<high && max(edge.y,edge.w)>=low {
                        guard edges.count<2_000_000 else { return nil }
                        edges.append(edge)
                    }
                    let count=edges.count-start
                    if count==0 { continue }
                    let bandTop=max(0,y*tileSide,Int(floor(b.y)))
                    let bandBottom=min(height,(y+1)*tileSide,Int(ceil(b.w)))
                    edgePixels += pixelWidth * max(0,bandBottom-bandTop) * count
                    guard edgePixels<=300_000_000, commands.count<100_000 else { return nil }
                    var band=paint
                    band.firstEdge=UInt32(start);band.edgeCount=UInt32(count)
                    let command=UInt32(commands.count)
                    commands.append(band)
                    for x in left..<right { bins[y*columns+x].append(command) }
                }
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
        guard let edges = upload(edges), let commands = upload(commands),
              let ranges = upload(offsets), let members = upload(indices), let pixels = upload(paints.pixels) else { return nil }
        buffers = [edges, commands, ranges, members, pixels]
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
              encode(to: texture, origin: .zero, step: SIMD2(repeating:Float(width)/Float(outputWidth)), command: command) else { return nil }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let stride = outputWidth * 4
        var data = Data(count: stride * outputHeight)
        data.withUnsafeMutableBytes { bytes in texture.getBytes(bytes.baseAddress!, bytesPerRow: stride, from: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0) }
        return PagePixels(data: data, width: outputWidth, height: outputHeight)
    }
}
