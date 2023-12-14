const std = @import("std");
const example = @embedFile("example.txt");
const example_test = @embedFile("example_test.txt");
const input = @embedFile("input.txt");

const Mapping = struct {
    dst_start: u32,
    src_start: u32,
    rng_length: u32,
};

const MappingSortOrder = enum {
    bySrcStart,
    byDstStart,
};

fn lowestLocationNumber(allocator: std.mem.Allocator, s: []const u8) !u32 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();

    var sections = std.mem.splitSequence(u8, s, "\n\n");
    var seeds = try parseSeeds(arena_allocator, sections.next().?);

    var mappings: [7][]Mapping = undefined;
    for (0..mappings.len) |i| {
        mappings[i] = try parseMap(arena_allocator, sections.next().?, .bySrcStart);
    }

    var lowestLocation: u32 = std.math.maxInt(u32);
    for (seeds) |seed| {
        const location = solve(&mappings, seed, .bySrcStart);
        lowestLocation = @min(lowestLocation, location);
    }

    return lowestLocation;
}

fn lowestLocationNumberRange(allocator: std.mem.Allocator, s: []const u8) !u32 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();

    var sections = std.mem.splitSequence(u8, s, "\n\n");
    var seeds = try parseSeeds(arena_allocator, sections.next().?);

    // create the list of mappings in reverse order and each mapping is sorted by dst_start
    var mappings: [7][]Mapping = undefined;
    for (1..mappings.len + 1) |i| {
        mappings[mappings.len - i] = try parseMap(arena_allocator, sections.next().?, .byDstStart);
    }

    // create a mapping using the ranges from the seeds list
    var seedsRange = try createMappingFromSeeds(arena_allocator, seeds);
    defer arena_allocator.free(seedsRange);

    // brute force search for the smallest location that maps to a seed
    return for (0..std.math.maxInt(u32)) |loc| {
        const location: u32 = @truncate(loc);
        const seed = solve(&mappings, location, .byDstStart);
        if (contains(seedsRange, seed)) {
            break location;
        }
    } else unreachable;
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

fn parseMap(allocator: std.mem.Allocator, s: []const u8, comptime order: MappingSortOrder) ![]Mapping {
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
    switch (order) {
        .bySrcStart => std.sort.block(Mapping, map, {}, cmpBySrcStartAndRngLength),
        .byDstStart => std.sort.block(Mapping, map, {}, cmpByDstStartAndRngLength),
    }

    return map;
}

fn createMappingFromSeeds(allocator: std.mem.Allocator, seeds: []u32) ![]Mapping {
    const count = seeds.len / 2;
    var map = try allocator.alloc(Mapping, count);
    errdefer allocator.free(map);

    var i: usize = 0;
    while (i < seeds.len) : (i += 2) {
        const index = std.math.divFloor(usize, i, 2) catch unreachable;
        map[index] = .{ .src_start = seeds[i], .dst_start = seeds[i], .rng_length = seeds[i + 1] };
    }

    // sort the map to make search more efficient
    std.sort.block(Mapping, map, {}, cmpBySrcStartAndRngLength);

    return map;
}

fn contains(mapping: []Mapping, seed: u32) bool {
    if (std.sort.binarySearch(Mapping, seed, mapping, {}, orderBySrcStartInRange)) |ignored| {
        _ = ignored;
        return true;
    }
    return false;
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

fn cmpByDstStartAndRngLength(ctx: void, lhs: Mapping, rhs: Mapping) bool {
    _ = ctx;
    if (lhs.dst_start < rhs.dst_start) {
        return true;
    } else if (lhs.dst_start == rhs.dst_start) {
        // the bigger the range, the earlier it will appear in the map
        return lhs.rng_length > rhs.rng_length;
    }
    return false;
}

fn solve(mappings: [][]Mapping, src: u32, comptime order: MappingSortOrder) u32 {
    const compareFn = switch (order) {
        .bySrcStart => orderBySrcStartInRange,
        .byDstStart => orderByDstStartInRange,
    };

    var value = src;
    for (mappings) |mapping| {
        // const value_before = value;
        if (std.sort.binarySearch(Mapping, value, mapping, {}, compareFn)) |index| {
            value = switch (order) {
                .bySrcStart => mapping[index].dst_start + (value - mapping[index].src_start),
                .byDstStart => mapping[index].src_start + (value - mapping[index].dst_start),
            };
        }
        // std.debug.print("before={d} after={d}\n", .{ value_before, value });
    }

    return value;
}

fn orderBySrcStartInRange(ctx: void, v: u32, mapping: Mapping) std.math.Order {
    _ = ctx;
    if (v >= mapping.src_start) {
        if (v - mapping.src_start < mapping.rng_length) {
            return .eq;
        }
        return .gt;
    }
    return .lt;
}

fn orderByDstStartInRange(ctx: void, v: u32, mapping: Mapping) std.math.Order {
    _ = ctx;
    if (v >= mapping.dst_start) {
        if (v - mapping.dst_start < mapping.rng_length) {
            return .eq;
        }
        return .gt;
    }
    return .lt;
}

test "example - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, example);
    try std.testing.expectEqual(@as(u32, 35), lowest_location);
}

test "input - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, input);
    try std.testing.expectEqual(@as(u32, 403695602), lowest_location);
}

test "example - part 2" {
    const lowest_location = try lowestLocationNumberRange(std.testing.allocator, example);
    try std.testing.expectEqual(@as(u32, 46), lowest_location);
}

test "example test - part 2" {
    const lowest_location = try lowestLocationNumberRange(std.testing.allocator, example_test);
    try std.testing.expectEqual(@as(u32, 46), lowest_location);
}

test "input - part 2" {
    const lowest_location = try lowestLocationNumberRange(std.testing.allocator, input);
    try std.testing.expectEqual(@as(u32, 219529182), lowest_location);
}
