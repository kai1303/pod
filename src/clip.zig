const std = @import("std");
const A = std.mem.Allocator;
pub const Point = extern struct { x: f64, y: f64 };
pub const Edge = extern struct { a: Point, b: Point };
pub const Region = struct { edges: []const Edge, even: bool = false };
const max_edges = 65536;
const max_events = 65536;
const max_work = 8 * 1024 * 1024;
const Segment = struct { edge: Edge, shape: u1 };
const Hit = struct { x: f64, segment: Segment, index: usize };

fn xAt(e: Edge, y: f64) f64 {
    return e.a.x + (y - e.a.y) / (e.b.y - e.a.y) * (e.b.x - e.a.x);
}
fn inside(w: i32, even: bool) bool {
    return if (even) @mod(w, 2) != 0 else w != 0;
}
fn event(a: A, ys: *std.ArrayList(f64), y: f64) !void {
    if (ys.items.len >= max_events) return error.ClippingLimit;
    try ys.append(a, y);
}
fn spend(work: *usize, n: usize) !void {
    if (n > max_work -| work.*) return error.ClippingLimit;
    work.* += n;
}

// Split at every vertex and edge crossing. Within each horizontal slab the edge
// order is fixed, so their shared interior can be represented by trapezoids.
// Output uses nonzero winding and omits horizontal edges, like the rasterizers.
pub fn intersect(allocator: A, first: Region, second: Region) ![]Edge {
    if (first.edges.len +| second.edges.len > max_edges) return error.ClippingLimit;
    if (first.edges.len == 0 or second.edges.len == 0) return allocator.alloc(Edge, 0);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var segments: std.ArrayList(Segment) = .empty;
    var ys: std.ArrayList(f64) = .empty;
    for ([_]Region{ first, second }, 0..) |region, shape| for (region.edges) |edge| {
        for ([_]Point{ edge.a, edge.b }) |p| {
            if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y) or @abs(p.x) > 1e9 or @abs(p.y) > 1e9) return error.InvalidTransform;
        }
        if (edge.a.y == edge.b.y) continue;
        try segments.append(a, .{ .edge = edge, .shape = @intCast(shape) });
        try event(a, &ys, edge.a.y);
        try event(a, &ys, edge.b.y);
    };
    std.mem.sort(Segment, segments.items, {}, struct {
        fn less(_: void, x: Segment, y: Segment) bool {
            return @min(x.edge.a.y, x.edge.b.y) < @min(y.edge.a.y, y.edge.b.y);
        }
    }.less);
    var work: usize = 0;
    for (segments.items, 0..) |s, i| {
        const e = s.edge;
        for (segments.items[i + 1 ..]) |t| {
            const f = t.edge;
            if (@min(f.a.y, f.b.y) >= @max(e.a.y, e.b.y)) break;
            try spend(&work, 1);
            if (@max(e.a.x, e.b.x) < @min(f.a.x, f.b.x) or @max(f.a.x, f.b.x) < @min(e.a.x, e.b.x)) continue;
            const dx = e.b.x - e.a.x;
            const dy = e.b.y - e.a.y;
            const fx = f.b.x - f.a.x;
            const fy = f.b.y - f.a.y;
            const cross = dx * fy - dy * fx;
            if (cross == 0) continue;
            const qx = f.a.x - e.a.x;
            const qy = f.a.y - e.a.y;
            const u = (qx * fy - qy * fx) / cross;
            const v = (qx * dy - qy * dx) / cross;
            if (u > 0 and u < 1 and v > 0 and v < 1) try event(a, &ys, e.a.y + u * dy);
        }
    }
    std.mem.sort(f64, ys.items, {}, std.sort.asc(f64));
    const hits = try a.alloc(Hit, segments.items.len);
    var output: std.ArrayList(Edge) = .empty;
    const last = try a.alloc(?usize, segments.items.len);
    @memset(last, null);
    if (ys.items.len == 0) return allocator.alloc(Edge, 0);
    var y0 = ys.items[0];
    for (ys.items[1..]) |y1| {
        if (y1 <= y0) continue;
        const middle = y0 + (y1 - y0) / 2;
        try spend(&work, segments.items.len);
        var count: usize = 0;
        for (segments.items, 0..) |seg, index| {
            const e = seg.edge;
            if (middle < @min(e.a.y, e.b.y) or middle >= @max(e.a.y, e.b.y)) continue;
            hits[count] = .{ .x = xAt(e, middle), .segment = seg, .index = index };
            count += 1;
        }
        std.mem.sort(Hit, hits[0..count], {}, struct {
            fn less(_: void, x: Hit, y: Hit) bool {
                return x.x < y.x;
            }
        }.less);
        var winding = [2]i32{ 0, 0 };
        var left: ?Hit = null;
        for (hits[0..count]) |hit| {
            const was_inside = inside(winding[0], first.even) and inside(winding[1], second.even);
            const e = hit.segment.edge;
            winding[hit.segment.shape] += if (e.b.y > e.a.y) @as(i32, 1) else -1;
            const is_inside = inside(winding[0], first.even) and inside(winding[1], second.even);
            if (!was_inside and is_inside) left = hit;
            if (was_inside and !is_inside) {
                const start = left.?;
                if (hit.x > start.x) {
                    try boundary(a, &output, &last[start.index], .{ .a = .{ .x = xAt(start.segment.edge, y0), .y = y0 }, .b = .{ .x = xAt(start.segment.edge, y1), .y = y1 } });
                    try boundary(a, &output, &last[hit.index], .{ .a = .{ .x = xAt(hit.segment.edge, y1), .y = y1 }, .b = .{ .x = xAt(hit.segment.edge, y0), .y = y0 } });
                }
                left = null;
            }
        }
        y0 = y1;
    }
    return allocator.dupe(Edge, output.items);
}

// Only join pieces of the same original straight edge, with exact shared endpoints.
fn boundary(a: A, output: *std.ArrayList(Edge), last: *?usize, edge: Edge) !void {
    if (last.*) |index| {
        const previous = &output.items[index];
        if (edge.b.y > edge.a.y and previous.b.y > previous.a.y and previous.b.x == edge.a.x and previous.b.y == edge.a.y) {
            previous.b = edge.b;
            return;
        }
        if (edge.b.y < edge.a.y and previous.b.y < previous.a.y and previous.a.x == edge.b.x and previous.a.y == edge.b.y) {
            previous.a = edge.a;
            return;
        }
    }
    if (output.items.len >= max_edges) return error.ClippingLimit;
    last.* = output.items.len;
    try output.append(a, edge);
}

fn contains(region: Region, p: Point) bool {
    var winding: i32 = 0;
    for (region.edges) |e| {
        if ((e.a.y <= p.y and e.b.y > p.y) or (e.b.y <= p.y and e.a.y > p.y)) {
            // A separate ray test avoids depending on the scan conversion ordering.
            const cross = (e.b.x - e.a.x) * (p.y - e.a.y) - (p.x - e.a.x) * (e.b.y - e.a.y);
            if (e.b.y > e.a.y and cross > 0) winding += 1;
            if (e.b.y < e.a.y and cross < 0) winding -= 1;
        }
    }
    return inside(winding, region.even);
}

test "intersections agree with independent winding tests for crossing and concave polygons" {
    const a = std.testing.allocator;
    var random = std.Random.DefaultPrng.init(0x706f64636c6970);
    for (0..128) |iteration| {
        const scale: f64 = switch (iteration % 3) {
            0 => 1e-6,
            1 => 1,
            else => 1e6,
        };
        const offset: f64 = if (iteration % 5 == 0) 1e8 else 0;
        var sets: [2][12]Edge = undefined;
        for (&sets) |*edges| {
            var points: [12]Point = undefined;
            for (&points) |*p| p.* = .{ .x = random.random().float(f64) * 100 * scale + offset, .y = random.random().float(f64) * 100 * scale + offset };
            for (edges, 0..) |*edge, i| edge.* = .{ .a = points[i], .b = points[(i + 1) % points.len] };
        }
        const first = Region{ .edges = &sets[0], .even = iteration % 2 == 0 };
        const second = Region{ .edges = &sets[1], .even = iteration % 4 < 2 };
        const clipped = try intersect(a, first, second);
        defer a.free(clipped);
        for (0..1024) |_| {
            const p = Point{ .x = random.random().float(f64) * 100 * scale + offset, .y = random.random().float(f64) * 100 * scale + offset };
            const expected = contains(first, p) and contains(second, p);
            const actual = contains(.{ .edges = clipped }, p);
            if (expected != actual) {
                // Intersections stored back at a large origin round to f64 grid
                // points. Only samples within coordinate roundoff may disagree.
                var distance: f64 = std.math.inf(f64);
                for ([_]Region{ first, second }) |region| for (region.edges) |e| {
                    const dx = e.b.x - e.a.x;
                    const dy = e.b.y - e.a.y;
                    const t = std.math.clamp(((p.x - e.a.x) * dx + (p.y - e.a.y) * dy) / (dx * dx + dy * dy), 0, 1);
                    const x = p.x - e.a.x - t * dx;
                    const y = p.y - e.a.y - t * dy;
                    distance = @min(distance, @sqrt(x * x + y * y));
                };
                try std.testing.expect(distance <= std.math.floatEps(f64) * (offset + 100 * scale) * 2);
            }
        }
    }
}

test "clipping rejects invalid coordinates and bounds adversarial edge work" {
    const a = std.testing.allocator;
    const bad = [_]Edge{.{ .a = .{ .x = std.math.nan(f64), .y = 0 }, .b = .{ .x = 1, .y = 1 } }};
    try std.testing.expectError(error.InvalidTransform, intersect(a, .{ .edges = &bad }, .{ .edges = &bad }));
    const repeated = try a.alloc(Edge, 5000);
    defer a.free(repeated);
    @memset(repeated, .{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 1, .y = 1 } });
    try std.testing.expectError(error.ClippingLimit, intersect(a, .{ .edges = repeated }, .{ .edges = repeated }));
}
test "intersection removes internal edges of overlapping nonzero contours" {
    const source = [_]Edge{
        .{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 0, .y = 10 } },
        .{ .a = .{ .x = 10, .y = 10 }, .b = .{ .x = 10, .y = 0 } },
        .{ .a = .{ .x = 5, .y = 0 }, .b = .{ .x = 5, .y = 10 } },
        .{ .a = .{ .x = 15, .y = 10 }, .b = .{ .x = 15, .y = 0 } },
    };
    const box = [_]Edge{
        .{ .a = .{ .x = -10, .y = -10 }, .b = .{ .x = -10, .y = 20 } },
        .{ .a = .{ .x = 20, .y = 20 }, .b = .{ .x = 20, .y = -10 } },
    };
    const clipped = try intersect(std.testing.allocator, .{ .edges = &source }, .{ .edges = &box });
    defer std.testing.allocator.free(clipped);
    try std.testing.expectEqual(@as(usize, 2), clipped.len);
    try std.testing.expect(contains(.{ .edges = clipped }, .{ .x = 7, .y = 5 }));
    try std.testing.expect(!contains(.{ .edges = clipped }, .{ .x = 17, .y = 5 }));
}
test "unrelated clip vertices do not split continuous boundary edges" {
    const source = [_]Edge{
        .{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 0, .y = 10 } },
        .{ .a = .{ .x = 10, .y = 10 }, .b = .{ .x = 10, .y = 0 } },
    };
    const box = [_]Edge{
        .{ .a = .{ .x = -10, .y = -10 }, .b = .{ .x = -10, .y = 20 } },
        .{ .a = .{ .x = 20, .y = 20 }, .b = .{ .x = 20, .y = -10 } },
        .{ .a = .{ .x = 30, .y = 3 }, .b = .{ .x = 30, .y = 7 } },
        .{ .a = .{ .x = 40, .y = 7 }, .b = .{ .x = 40, .y = 3 } },
    };
    const clipped = try intersect(std.testing.allocator, .{ .edges = &source }, .{ .edges = &box });
    defer std.testing.allocator.free(clipped);
    try std.testing.expectEqual(@as(usize, 2), clipped.len);
    try std.testing.expect(contains(.{ .edges = clipped }, .{ .x = 7, .y = 5 }));
}
