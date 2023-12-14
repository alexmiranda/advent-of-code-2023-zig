const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Mapping = struct {
    dst_start: u32,
    src_start: u32,
    rng_length: u32,
};

fn lowestLocationNumber(allocator: std.mem.Allocator, s: []const u8) !u32 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();

    var sections = std.mem.splitSequence(u8, s, "\n\n");
    var seeds = try parseSeeds(arena_allocator, sections.next().?);

    var mappings: [7][]Mapping = undefined;
    for (0..mappings.len) |i| {
        mappings[i] = try parseMap(arena_allocator, sections.next().?);
    }

    var lowestLocation: u32 = std.math.maxInt(u32);
    for (seeds) |seed| {
        const location = solve(&mappings, seed);
        lowestLocation = @min(lowestLocation, location);
    }

    return lowestLocation;
}

fn parseSeeds(allocator: std.mem.Allocator, s: []const u8) ![]u32 {
    const size = std.mem.count(u8, s, " ");
    var array = try allocator.alloc(u32, size);
    errdefer allocator.free(array);

    const sep_index = std.mem.indexOfScalar(u8, s, ':').?;
    var slide: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s[sep_index + 2 ..], ' ');
    while (it.next()) |seed_as_str| : (slide += 1) {
        const seed = std.fmt.parseInt(u32, seed_as_str, 10) catch unreachable;
        array[slide] = seed;
    }
    return array;
}

fn parseMap(allocator: std.mem.Allocator, s: []const u8) ![]Mapping {
    const size = std.mem.count(u8, s, "\n");
    var map = try allocator.alloc(Mapping, size);
    errdefer allocator.free(map);

    var slide: usize = 0;
    var it = std.mem.splitScalar(u8, std.mem.trimRight(u8, s, "\n"), '\n');
    const header = it.next();
    _ = header;

    while (it.next()) |line| : (slide += 1) {
        var values = std.mem.tokenizeScalar(u8, line, ' ');
        const dst_start = std.fmt.parseInt(u32, values.next().?, 10) catch unreachable;
        const src_start = std.fmt.parseInt(u32, values.next().?, 10) catch unreachable;
        const rng_length = std.fmt.parseInt(u32, values.next().?, 10) catch unreachable;
        map[slide] = .{ .dst_start = dst_start, .src_start = src_start, .rng_length = rng_length };
    }

    // sort the map to make search more efficient
    std.sort.block(Mapping, map, {}, cmpBySrcStartAndRngLength);

    return map;
}

fn cmpBySrcStartAndRngLength(ctx: void, lhs: Mapping, rhs: Mapping) bool {
    _ = ctx;
    if (lhs.src_start < rhs.src_start) {
        return true;
    } else if (lhs.src_start == rhs.src_start) {
        // the bigger the range, the earlier it will appear in the map
        return lhs.rng_length > rhs.rng_length;
    }
    return false;
}

fn solve(mappings: [][]Mapping, src: u32) u32 {
    const S = struct {
        fn orderByInRange(ctx: void, v: u32, mapping: Mapping) std.math.Order {
            _ = ctx;
            if (v >= mapping.src_start) {
                if (v - mapping.src_start <= mapping.rng_length) {
                    return .eq;
                }
                return .gt;
            }
            return .lt;
        }
    };

    var value = src;
    for (mappings) |mapping| {
        if (std.sort.binarySearch(Mapping, value, mapping, {}, S.orderByInRange)) |index| {
            value = mapping[index].dst_start + (value - mapping[index].src_start);
        }
    }

    return value;
}

test "example - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, example);
    try std.testing.expectEqual(@as(u32, 35), lowest_location);
}

test "input - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, input);
    try std.testing.expectEqual(@as(u32, 403695602), lowest_location);
}
