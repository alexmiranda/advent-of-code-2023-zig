const std = @import("std");
const example = @embedFile("example.txt");
const example_test = @embedFile("example_test.txt");
const input = @embedFile("input.txt");

const Mapping = struct {
    dst_start: u64,
    src_start: u64,
    rng_length: u64,
};

fn lowestLocationNumber(allocator: std.mem.Allocator, s: []const u8) !u64 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();

    var sections = std.mem.splitSequence(u8, s, "\n\n");
    var seeds = try parseSeeds(arena_allocator, sections.next().?);

    var mappings: [7][]Mapping = undefined;
    for (0..mappings.len) |i| {
        mappings[i] = try parseMap(arena_allocator, sections.next().?);
    }

    var lowestLocation: u64 = std.math.maxInt(u64);
    for (seeds) |seed| {
        const location = solve(&mappings, seed);
        lowestLocation = @min(lowestLocation, location);
    }

    return lowestLocation;
}

fn lowestLocationNumberRange(allocator: std.mem.Allocator, s: []const u8) !u64 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();

    var sections = std.mem.splitSequence(u8, s, "\n\n");

    var mappings: [8][]Mapping = undefined;
    mappings[0] = try parseSeedsRange(arena_allocator, sections.next().?);
    for (1..mappings.len) |i| {
        mappings[i] = try parseMap(arena_allocator, sections.next().?);
    }

    // printMappings(&mappings);
    return try solveRange(arena_allocator, &mappings);
}

fn parseSeeds(allocator: std.mem.Allocator, s: []const u8) ![]u64 {
    const size = std.mem.count(u8, s, " ");
    var array = try allocator.alloc(u64, size);
    errdefer allocator.free(array);

    const sep_index = std.mem.indexOfScalar(u8, s, ':').?;
    var slide: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s[sep_index + 2 ..], ' ');
    while (it.next()) |seed_as_str| : (slide += 1) {
        const seed = std.fmt.parseInt(u64, seed_as_str, 10) catch unreachable;
        array[slide] = seed;
    }
    return array;
}

fn parseSeedsRange(allocator: std.mem.Allocator, s: []const u8) ![]Mapping {
    const size = std.mem.count(u8, s, " ");
    std.debug.assert(size % 2 == 0); // make sure that we have pairs

    const pairs_count = size / 2;
    var ranges = try allocator.alloc(Mapping, pairs_count);
    errdefer allocator.free(ranges);

    const sep_index = std.mem.indexOfScalar(u8, s, ':').?;
    var slide: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s[sep_index + 2 ..], ' ');
    while (it.next()) |seed_as_str| : (slide += 1) {
        const range_start = std.fmt.parseInt(u64, seed_as_str, 10) catch unreachable;
        const range_length = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        ranges[slide] = .{ .src_start = range_start, .dst_start = range_start, .rng_length = range_length };
    }

    return ranges;
}

fn parseMap(allocator: std.mem.Allocator, s: []const u8) ![]Mapping {
    const ss = std.mem.trimRight(u8, s, "\n");
    const size = std.mem.count(u8, ss, "\n");
    var map = try allocator.alloc(Mapping, size);
    errdefer allocator.free(map);

    var slide: usize = 0;
    var it = std.mem.splitScalar(u8, std.mem.trimRight(u8, s, "\n"), '\n');
    const header = it.next();
    _ = header;

    while (it.next()) |line| : (slide += 1) {
        var values = std.mem.tokenizeScalar(u8, line, ' ');
        const dst_start = std.fmt.parseInt(u64, values.next().?, 10) catch unreachable;
        const src_start = std.fmt.parseInt(u64, values.next().?, 10) catch unreachable;
        const rng_length = std.fmt.parseInt(u64, values.next().?, 10) catch unreachable;
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

fn solve(mappings: [][]Mapping, src: u64) u64 {
    const S = struct {
        fn orderByInRange(ctx: void, v: u64, mapping: Mapping) std.math.Order {
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

fn printMappings(mappings: [][]Mapping) void {
    std.debug.print("\n\n", .{});
    for (mappings, 1..) |mapping, i| {
        std.debug.print("LEVEL {0} LEN: {1}\n", .{ i, mapping.len });
        for (mapping) |range| {
            std.debug.print("{0} {1} {2}\n", .{ range.dst_start, range.src_start, range.rng_length });
        }
    }
    std.debug.print("\n\n", .{});
}

fn solveRange(allocator: std.mem.Allocator, mappings: [][]Mapping) !u64 {
    const Queue = std.TailQueue(Mapping);
    const Node = Queue.Node;
    var unmapped = Queue{};
    var mapped = Queue{};

    // push all the seeds ranges to the queue
    for (mappings[0]) |range| {
        var node = try allocator.create(Node);
        node.* = Node{ .data = range };
        unmapped.append(node);
    }

    // going from each level down...
    for (1..mappings.len) |i| {
        while (unmapped.len > 0) {
            const node = unmapped.popFirst().?;
            const curr_start = node.data.src_start;
            const curr_end = curr_start + node.data.rng_length - 1;
            var found = false;

            for (mappings[i]) |mapping| {
                const mapping_start = mapping.src_start;
                const mapping_end = mapping_start + mapping.rng_length;

                // if the ranges are overlapping
                if ((curr_start >= mapping_start and curr_start < mapping_end) or
                    (curr_end >= mapping_start and curr_end < mapping_end))
                {
                    found = true;
                    const s1 = curr_start;
                    const s2 = @max(curr_start, mapping_start);
                    const e1 = @min(curr_end, mapping_end);
                    const e2 = curr_end;

                    var new_node = try allocator.create(Node);
                    new_node.* = blk: {
                        if (mapping.dst_start > mapping.src_start) {
                            const offset = mapping.dst_start - mapping.src_start;
                            const start = s2 + offset;
                            break :blk .{ .data = .{ .src_start = start, .dst_start = start, .rng_length = e1 - s2 + 1 } };
                        } else {
                            const offset = mapping.src_start - mapping.dst_start;
                            const start = s2 - offset;
                            break :blk .{ .data = .{ .src_start = start, .dst_start = start, .rng_length = e1 - s2 + 1 } };
                        }
                    };
                    mapped.append(new_node);

                    if (s1 < s2) {
                        new_node = try allocator.create(Node);
                        new_node.* = .{ .data = .{ .src_start = s1, .dst_start = s1, .rng_length = s2 - s1 } };
                        unmapped.append(new_node);
                    }

                    if (e2 > e1) {
                        new_node = try allocator.create(Node);
                        new_node.* = .{ .data = .{ .src_start = e1, .dst_start = e1, .rng_length = e2 - e1 } };
                        unmapped.append(new_node);
                    }
                }
            }

            // if the range of the current node doesn't match any of the mappings,
            // then we need to consider it as mapped, as all of the values in the range will
            // map directly to the same values in the next map.
            if (!found) {
                mapped.append(node);
            }
        }

        // all of the mapped ranges from the previous map will be
        // re-map in the next map
        unmapped.concatByMoving(&mapped);
    }

    var min: u64 = std.math.maxInt(u64);
    while (unmapped.len > 0) {
        const node = unmapped.popFirst().?;
        min = @min(min, node.data.src_start);
    }

    return min;
}

test "example - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, example);
    try std.testing.expectEqual(@as(u64, 35), lowest_location);
}

test "input - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, input);
    try std.testing.expectEqual(@as(u64, 403695602), lowest_location);
}

test "example - part 2" {
    const lowest_location = try lowestLocationNumberRange(std.testing.allocator, example);
    try std.testing.expectEqual(@as(u64, 46), lowest_location);
}

test "example test - part 2" {
    const lowest_location = try lowestLocationNumberRange(std.testing.allocator, example_test);
    try std.testing.expectEqual(@as(u64, 46), lowest_location);
}

test "input - part 2" {
    const lowest_location = try lowestLocationNumberRange(std.testing.allocator, input);
    try std.testing.expectEqual(@as(u64, 219529182), lowest_location);
}
