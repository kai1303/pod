//! Sequential and progressive Huffman JPEG decoding (ITU-T T.81, annexes B, E, F and G).
const std = @import("std");
const A = std.mem.Allocator;
pub const Result = struct { width: usize, height: usize, channels: usize, pixels: []u8, consumed: usize = 0 };
const zigzag = [64]u8{ 0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63 };
const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,
    fn take(self: *Reader, n: usize) ![]const u8 {
        if (n > self.bytes.len - self.pos) return error.TruncatedJPEG;
        const bytes = self.bytes[self.pos..][0..n];
        self.pos += n;
        return bytes;
    }
    fn byte(self: *Reader) !u8 {
        return (try self.take(1))[0];
    }
    fn word(self: *Reader) !usize {
        return std.mem.readInt(u16, (try self.take(2))[0..2], .big);
    }
    fn marker(self: *Reader) !u8 {
        if (try self.byte() != 0xff) return error.InvalidJPEGMarker;
        var value = try self.byte();
        while (value == 0xff) value = try self.byte();
        if (value == 0) return error.InvalidJPEGMarker;
        return value;
    }
    fn segment(self: *Reader) !Reader {
        const length = try self.word();
        if (length < 2) return error.InvalidJPEGSegment;
        return .{ .bytes = try self.take(length - 2) };
    }
};
const Bits = struct {
    input: *Reader,
    value: u8 = 0,
    remaining: u4 = 0,
    fn read(self: *Bits, n: u5) !u32 {
        var result: u32 = 0;
        for (0..n) |_| {
            if (self.remaining == 0) {
                self.value = try self.input.byte();
                if (self.value == 0xff and try self.input.byte() != 0) return error.InvalidJPEGEntropy;
                self.remaining = 8;
            }
            self.remaining -= 1;
            result = (result << 1) | ((self.value >> @as(u3, @intCast(self.remaining))) & 1);
        }
        return result;
    }
    fn signed(self: *Bits, count: u5) !i32 {
        if (count == 0) return 0;
        const value: i32 = @intCast(try self.read(count));
        return if (value < @as(i32, 1) << (count - 1)) value - ((@as(i32, 1) << count) - 1) else value;
    }
    fn byteAlign(self: *Bits) !void {
        if (self.remaining != 0) {
            const mask = (@as(u16, 1) << self.remaining) - 1;
            if (self.value & mask != mask) return error.InvalidJPEGPadding;
        }
        self.remaining = 0;
    }
};
const Huffman = struct {
    first: [16]u32,
    count: [16]u32,
    offset: [16]usize,
    values: [256]u8,
    fn read(input: *Reader) !Huffman {
        var table: Huffman = undefined;
        const counts = try input.take(16);
        var total: usize = 0;
        var code: u32 = 0;
        for (counts, 0..) |count, i| {
            table.first[i] = code;
            table.count[i] = count;
            table.offset[i] = total;
            total += count;
            // All-one codes are reserved for entropy padding.
            if (total > 256 or code + count >= @as(u32, 1) << @as(u5, @intCast(i + 1))) return error.InvalidJPEGHuffman;
            code = (code + count) << 1;
        }
        if (total == 0) return error.InvalidJPEGHuffman;
        @memcpy(table.values[0..total], try input.take(total));
        return table;
    }
    fn symbol(self: *const Huffman, bits: *Bits) !u8 {
        var code: u32 = 0;
        for (0..16) |i| {
            code = (code << 1) | try bits.read(1);
            if (code >= self.first[i] and code - self.first[i] < self.count[i]) return self.values[self.offset[i] + code - self.first[i]];
        }
        return error.InvalidJPEGHuffman;
    }
};
const Quant = struct { values: [64]u16, wide: bool };
const Component = struct {
    id: u8 = 0,
    h: usize = 0,
    v: usize = 0,
    quant: u8 = 0,
    width: usize = 0,
    height: usize = 0,
    stride: usize = 0,
    pixels: []u8 = &.{},
    coefficients: [][64]i32 = &.{},
    approximation: [64]i8 = @splat(-1),
    saved_quant: ?Quant = null,
    done: bool = false,
    dc: i32 = 0,
    fn sample(self: Component, x: f64, y: f64) f64 {
        const left = @floor(x);
        const top = @floor(y);
        const fx = x - left;
        const fy = y - top;
        var value: f64 = 0;
        for (0..2) |row| for (0..2) |col| {
            const sx: usize = @intFromFloat(std.math.clamp(left + @as(f64, @floatFromInt(col)), 0, @as(f64, @floatFromInt(self.width - 1))));
            const sy: usize = @intFromFloat(std.math.clamp(top + @as(f64, @floatFromInt(row)), 0, @as(f64, @floatFromInt(self.height - 1))));
            value += @as(f64, @floatFromInt(self.pixels[sy * self.stride + sx])) * (if (col == 0) 1 - fx else fx) * (if (row == 0) 1 - fy else fy);
        };
        return @round(value);
    }
};
const basis = blk: {
    @setEvalBranchQuota(10000);
    var matrix: [8][8]f64 = undefined;
    for (0..8) |x| for (0..8) |u| {
        matrix[x][u] = (if (u == 0) 1 / @sqrt(@as(f64, 2)) else @as(f64, 1)) * @cos(@as(f64, @floatFromInt((2 * x + 1) * u)) * std.math.pi / 16);
    };
    break :blk matrix;
};
fn inverseDCT(coefficients: [64]i32, quant: Quant, target: *Component, bx: usize, by: usize) void {
    var ac = false;
    for (coefficients[1..]) |value| if (value != 0) {
        ac = true;
        break;
    };
    if (!ac) {
        const value: u8 = @intFromFloat(std.math.clamp(@round(@as(f64, @floatFromInt(coefficients[0])) * @as(f64, @floatFromInt(quant.values[0])) / 8 + 128), 0, 255));
        for (0..8) |y| @memset(target.pixels[(by * 8 + y) * target.stride + bx * 8 ..][0..8], value);
        return;
    }
    var rows: [64]f64 = undefined;
    for (0..8) |v| for (0..8) |x| {
        var sum: f64 = 0;
        for (0..8) |u| sum += @as(f64, @floatFromInt(coefficients[v * 8 + u])) * @as(f64, @floatFromInt(quant.values[v * 8 + u])) * basis[x][u];
        rows[v * 8 + x] = sum;
    };
    for (0..8) |y| for (0..8) |x| {
        var sum: f64 = 0;
        for (0..8) |v| sum += rows[v * 8 + x] * basis[y][v];
        target.pixels[(by * 8 + y) * target.stride + bx * 8 + x] = @intFromFloat(std.math.clamp(@round(sum / 4 + 128), 0, 255));
    };
}
const Band = struct { first: usize, last: usize, high: u8, low: u8 };
const Decoder = struct {
    allocator: A,
    input: Reader,
    limit: usize,
    width: usize = 0,
    height: usize = 0,
    count: usize = 0,
    max_h: usize = 0,
    max_v: usize = 0,
    columns: usize = 0,
    rows: usize = 0,
    baseline: bool = true,
    progressive: bool = false,
    work: usize = 0,
    scans: usize = 0,
    restart: usize = 0,
    adobe: ?u8 = null,
    components: [3]Component = @splat(.{}),
    quant: [4]?Quant = @splat(null),
    huffman: [2][4]?Huffman = @splat(@splat(null)),
    fn frame(self: *Decoder, segment: *Reader, marker: u8) !void {
        if (self.count != 0) return error.InvalidJPEGFrame;
        if (try segment.byte() != 8) return error.UnsupportedJPEGPrecision;
        self.height = try segment.word();
        self.width = try segment.word();
        self.count = try segment.byte();
        self.baseline = marker == 0xc0;
        self.progressive = marker == 0xc2;
        if (self.height == 0) return error.UnsupportedJPEGDimensions;
        if (self.width == 0) return error.InvalidJPEGFrame;
        if (self.count != 1 and self.count != 3) return error.UnsupportedJPEGComponents;
        if (self.width * self.height > 16 * 1024 * 1024 or self.width * self.height * self.count > self.limit) return error.DecodedStreamLimit;
        var blocks: usize = 0;
        for (self.components[0..self.count], 0..) |*component, i| {
            component.id = try segment.byte();
            for (self.components[0..i]) |previous| if (previous.id == component.id) return error.InvalidJPEGFrame;
            const sampling = try segment.byte();
            component.h = sampling >> 4;
            component.v = sampling & 15;
            component.quant = try segment.byte();
            if (component.h == 0 or component.v == 0 or component.h > 4 or component.v > 4 or component.quant > 3) return error.InvalidJPEGFrame;
            self.max_h = @max(self.max_h, component.h);
            self.max_v = @max(self.max_v, component.v);
            blocks += component.h * component.v;
        }
        if (self.count > 1 and blocks > 10) return error.InvalidJPEGFrame;
        if (segment.pos != segment.bytes.len) return error.InvalidJPEGSegment;
        self.columns = (self.width + 8 * self.max_h - 1) / (8 * self.max_h);
        self.rows = (self.height + 8 * self.max_v - 1) / (8 * self.max_v);
        var bytes: usize = 0;
        for (self.components[0..self.count]) |*component| {
            component.width = (self.width * component.h + self.max_h - 1) / self.max_h;
            component.height = (self.height * component.v + self.max_v - 1) / self.max_v;
            component.stride = self.columns * component.h * 8;
            const size = component.stride * self.rows * component.v * 8;
            if (size > 64 * 1024 * 1024 -| bytes) return error.DecodedStreamLimit;
            bytes += size;
            component.pixels = try self.allocator.alloc(u8, size);
            if (self.progressive) {
                // The 64 MiB plane budget also bounds coefficient storage to 256 MiB.
                component.coefficients = try self.allocator.alloc([64]i32, size / 64);
                @memset(component.coefficients, @splat(0));
            }
        }
    }
    fn block(self: *Decoder, bits: *Bits, component: *Component, dc: u8, ac: u8, bx: usize, by: usize) !void {
        const quant = self.quant[component.quant] orelse return error.MissingJPEGTable;
        if (self.baseline and quant.wide) return error.InvalidJPEGQuantization;
        const dc_table = &(self.huffman[0][dc] orelse return error.MissingJPEGTable);
        const ac_table = &(self.huffman[1][ac] orelse return error.MissingJPEGTable);
        var coefficients: [64]i32 = @splat(0);
        const category = try dc_table.symbol(bits);
        if (category > 11) return error.InvalidJPEGCoefficient;
        component.dc += try bits.signed(@intCast(category));
        if (@abs(component.dc) > 1048576) return error.InvalidJPEGCoefficient;
        coefficients[0] = component.dc;
        var k: usize = 1;
        while (k < 64) {
            const symbol = try ac_table.symbol(bits);
            const run = symbol >> 4;
            const size = symbol & 15;
            if (size == 0) {
                if (run == 0) break;
                if (run != 15 or k + 16 > 64) return error.InvalidJPEGCoefficient;
                k += 16;
            } else {
                if (size > 10 or k + run >= 64) return error.InvalidJPEGCoefficient;
                k += run;
                coefficients[zigzag[k]] = try bits.signed(@intCast(size));
                k += 1;
            }
        }
        inverseDCT(coefficients, quant, component, bx, by);
    }
    fn refineAC(bits: *Bits, value: *i32, step: i32) !void {
        if (try bits.read(1) != 0) value.* += if (value.* > 0) step else -step;
    }
    fn progressiveBlock(self: *Decoder, bits: *Bits, component: *Component, coefficients: *[64]i32, dc: u8, ac: u8, band: Band, eob: *usize) !void {
        const step = @as(i32, 1) << @as(u5, @intCast(band.low));
        if (band.first == 0) {
            if (band.high == 0) {
                const table = self.huffman[0][dc] orelse return error.MissingJPEGTable;
                const category = try table.symbol(bits);
                if (category > 11) return error.InvalidJPEGCoefficient;
                component.dc += try bits.signed(@intCast(category));
                if (@abs(component.dc) > @as(u32, @intCast(@divTrunc(1048576, step)))) return error.InvalidJPEGCoefficient;
                coefficients[0] = component.dc * step;
            } else {
                // DC refinement appends a two's-complement bit; AC uses sign magnitude.
                coefficients[0] |= @as(i32, @intCast(try bits.read(1))) * step;
            }
            return;
        }
        const table = self.huffman[1][ac] orelse return error.MissingJPEGTable;
        var k = band.first;
        if (band.high == 0) {
            if (eob.* != 0) {
                eob.* -= 1;
                return;
            }
            while (k <= band.last) {
                const symbol = try table.symbol(bits);
                const run = symbol >> 4;
                const size = symbol & 15;
                if (size != 0) {
                    k += run;
                    if (size > 10 or k > band.last) return error.InvalidJPEGCoefficient;
                    coefficients[zigzag[k]] = (try bits.signed(@intCast(size))) * step;
                    k += 1;
                } else if (run == 15) {
                    k += 16;
                    if (k > band.last + 1) return error.InvalidJPEGCoefficient;
                } else {
                    eob.* = (@as(usize, 1) << @as(u6, @intCast(run))) + try bits.read(@intCast(run)) - 1;
                    return;
                }
            }
            return;
        }
        if (eob.* == 0) {
            while (k <= band.last) {
                const symbol = try table.symbol(bits);
                const run = symbol >> 4;
                const size = symbol & 15;
                if (size > 1) return error.InvalidJPEGCoefficient;
                if (size == 0 and run != 15) {
                    eob.* = (@as(usize, 1) << @as(u6, @intCast(run))) + try bits.read(@intCast(run));
                    break;
                }
                const value: i32 = if (size == 0) 0 else if (try bits.read(1) == 0) -step else step;
                var zeros: usize = if (size == 0) 16 else run;
                while (k <= band.last) {
                    const previous = &coefficients[zigzag[k]];
                    if (previous.* != 0) {
                        try refineAC(bits, previous, step);
                    } else {
                        if (zeros == 0) break;
                        zeros -= 1;
                    }
                    k += 1;
                    if (size == 0 and zeros == 0) break;
                }
                if (zeros != 0) return error.InvalidJPEGCoefficient;
                if (size != 0) {
                    if (k > band.last) return error.InvalidJPEGCoefficient;
                    coefficients[zigzag[k]] = value;
                    k += 1;
                }
            }
        }
        if (eob.* != 0) {
            while (k <= band.last) : (k += 1) {
                const previous = &coefficients[zigzag[k]];
                if (previous.* != 0) try refineAC(bits, previous, step);
            }
            eob.* -= 1;
        }
    }
    fn scan(self: *Decoder, segment: *Reader) !void {
        if (self.count == 0 or (!self.progressive and self.scans >= self.count)) return error.InvalidJPEGScan;
        const n = try segment.byte();
        if (n == 0 or n > self.count) return error.InvalidJPEGScan;
        const Selector = struct { component: usize, dc: u8, ac: u8 };
        var selectors: [3]Selector = undefined;
        var seen: [3]bool = @splat(false);
        for (selectors[0..n]) |*selector| {
            const id = try segment.byte();
            const tables = try segment.byte();
            var found: ?usize = null;
            for (self.components[0..self.count], 0..) |component, i| if (component.id == id) {
                found = i;
                break;
            };
            const i = found orelse return error.InvalidJPEGScan;
            if (seen[i] or (!self.progressive and self.components[i].done)) return error.InvalidJPEGScan;
            seen[i] = true;
            self.components[i].dc = 0;
            selector.* = .{ .component = i, .dc = tables >> 4, .ac = tables & 15 };
            const max: u8 = if (self.baseline) 1 else 3;
            if (selector.dc > max or selector.ac > max) return error.InvalidJPEGScan;
        }
        const first = try segment.byte();
        const last = try segment.byte();
        const approximation = try segment.byte();
        const band = Band{ .first = first, .last = last, .high = approximation >> 4, .low = approximation & 15 };
        if (self.progressive) {
            if (first > last or last > 63 or (first == 0 and last != 0) or (first != 0 and n != 1) or
                band.high > 13 or band.low > 13 or (band.high != 0 and band.high != band.low + 1)) return error.InvalidJPEGScan;
            for (selectors[0..n]) |selector| {
                const component = &self.components[selector.component];
                if ((first == 0 and selector.ac != 0) or (first != 0 and selector.dc != 0)) return error.InvalidJPEGScan;
                if (first != 0 and component.approximation[0] < 0) return error.InvalidJPEGScan;
                for (component.approximation[first .. last + 1]) |previous| {
                    if ((band.high == 0 and previous != -1) or (band.high != 0 and previous != band.high)) return error.InvalidJPEGScan;
                }
                if (component.saved_quant == null) component.saved_quant = self.quant[component.quant] orelse return error.MissingJPEGTable;
            }
        } else if (first != 0 or last != 63 or approximation != 0) return error.InvalidJPEGScan;
        if (segment.pos != segment.bytes.len) return error.InvalidJPEGSegment;
        const single = self.components[selectors[0].component];
        const columns = if (n == 1) (single.width + 7) / 8 else self.columns;
        const rows = if (n == 1) (single.height + 7) / 8 else self.rows;
        var blocks: usize = 0;
        for (selectors[0..n]) |selector| {
            const component = self.components[selector.component];
            blocks += if (n == 1) 1 else component.h * component.v;
        }
        const work = rows * columns * blocks * (band.last - band.first + 1);
        if (work > 256 * 1024 * 1024 -| self.work) return error.JPEGWorkLimit;
        self.work += work;
        var bits = Bits{ .input = &self.input };
        var eob: usize = 0;
        var rst: u8 = 0;
        for (0..rows * columns) |mcu| {
            if (mcu != 0 and self.restart != 0 and mcu % self.restart == 0) {
                if (eob != 0) return error.InvalidJPEGRun;
                try bits.byteAlign();
                if (try self.input.marker() != 0xd0 + rst) return error.InvalidJPEGRestart;
                rst = (rst + 1) % 8;
                for (self.components[0..self.count]) |*component| component.dc = 0;
            }
            for (selectors[0..n]) |selector| {
                const component = &self.components[selector.component];
                const h = if (n == 1) 1 else component.h;
                const v = if (n == 1) 1 else component.v;
                for (0..v) |by| for (0..h) |bx| {
                    const x = (mcu % columns) * h + bx;
                    const y = (mcu / columns) * v + by;
                    if (self.progressive) {
                        const coefficients = &component.coefficients[y * (component.stride / 8) + x];
                        try self.progressiveBlock(&bits, component, coefficients, selector.dc, selector.ac, band, &eob);
                    } else try self.block(&bits, component, selector.dc, selector.ac, x, y);
                };
            }
        }
        if (eob != 0) return error.InvalidJPEGRun;
        try bits.byteAlign();
        for (selectors[0..n]) |selector| {
            const component = &self.components[selector.component];
            component.done = true;
            if (self.progressive) @memset(component.approximation[first .. last + 1], @intCast(band.low));
        }
        self.scans += 1;
    }
    fn finish(self: *Decoder, transform: ?bool) !Result {
        if (self.count == 0) return error.InvalidJPEGFrame;
        for (self.components[0..self.count]) |*component| {
            if (!component.done) return error.InvalidJPEGScan;
            if (self.progressive) {
                if (component.approximation[0] < 0) return error.InvalidJPEGScan;
                const quant = component.saved_quant orelse return error.MissingJPEGTable;
                for (0..(component.height + 7) / 8) |y| for (0..(component.width + 7) / 8) |x| {
                    inverseDCT(component.coefficients[y * (component.stride / 8) + x], quant, component, x, y);
                };
            }
        }
        const convert = if (self.adobe) |adobe| adobe == 1 else transform orelse (self.count == 3);
        const pixels = try self.allocator.alloc(u8, self.width * self.height * self.count);
        errdefer self.allocator.free(pixels);
        for (0..self.height) |y| for (0..self.width) |x| {
            var values: [3]f64 = undefined;
            for (self.components[0..self.count], 0..) |component, i| values[i] = component.sample((@as(f64, @floatFromInt(x)) + 0.5) * @as(f64, @floatFromInt(component.h)) / @as(f64, @floatFromInt(self.max_h)) - 0.5, (@as(f64, @floatFromInt(y)) + 0.5) * @as(f64, @floatFromInt(component.v)) / @as(f64, @floatFromInt(self.max_v)) - 0.5);
            if (self.count == 3 and convert) {
                const luma = values[0];
                const cb = values[1] - 128;
                const cr = values[2] - 128;
                values = .{ luma + 1.402 * cr, luma - 0.344136 * cb - 0.714136 * cr, luma + 1.772 * cb };
            }
            for (values[0..self.count], 0..) |value, i| pixels[(y * self.width + x) * self.count + i] = @intFromFloat(std.math.clamp(@round(value), 0, 255));
        };
        return .{ .width = self.width, .height = self.height, .channels = self.count, .pixels = pixels };
    }
};
pub fn decode(a: A, bytes: []const u8, transform: ?bool, limit: usize) !Result {
    var decoder = Decoder{ .allocator = a, .input = .{ .bytes = bytes }, .limit = limit };
    defer for (decoder.components) |component| {
        a.free(component.pixels);
        a.free(component.coefficients);
    };
    if (try decoder.input.marker() != 0xd8) return error.InvalidJPEGMarker;
    var markers: usize = 0;
    while (true) {
        markers += 1;
        if (markers > 10000) return error.JPEGWorkLimit;
        const marker = try decoder.input.marker();
        if (marker == 0xd9) {
            var result = try decoder.finish(transform);
            result.consumed = decoder.input.pos;
            return result;
        }
        var segment = try decoder.input.segment();
        switch (marker) {
            0xc0...0xc2 => try decoder.frame(&segment, marker),
            0xda => try decoder.scan(&segment),
            0xdb => while (segment.pos < segment.bytes.len) {
                const table = try segment.byte();
                const precision = table >> 4;
                const id = table & 15;
                if (precision > 1 or id > 3) return error.InvalidJPEGQuantization;
                var quant = Quant{ .values = undefined, .wide = precision == 1 };
                for (zigzag) |index| {
                    const value = if (precision == 0) try segment.byte() else try segment.word();
                    if (value == 0) return error.InvalidJPEGQuantization;
                    quant.values[index] = @intCast(value);
                }
                decoder.quant[id] = quant;
            },
            0xc4 => while (segment.pos < segment.bytes.len) {
                const table = try segment.byte();
                if (table >> 4 > 1 or table & 15 > 3) return error.InvalidJPEGHuffman;
                decoder.huffman[table >> 4][table & 15] = try Huffman.read(&segment);
            },
            0xdd => {
                decoder.restart = try segment.word();
                if (segment.pos != segment.bytes.len) return error.InvalidJPEGSegment;
            },
            0xee => {
                if (std.mem.startsWith(u8, segment.bytes, "Adobe")) {
                    if (segment.bytes.len < 12) return error.InvalidJPEGSegment;
                    const adobe = segment.bytes[11];
                    if (adobe > 1) return error.UnsupportedJPEGColorTransform;
                    if (decoder.adobe != null and decoder.adobe.? != adobe) return error.InvalidJPEGSegment;
                    decoder.adobe = adobe;
                }
            },
            0xe0...0xed, 0xef, 0xfe => {},
            0xc3, 0xc5...0xcf => return error.UnsupportedJPEGProcess,
            else => return error.UnsupportedJPEGMarker,
        }
    }
}
