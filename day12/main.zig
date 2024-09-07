const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const heap = std.heap;
const testing = std.testing;
const print = std.debug.print;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Spring = enum(u2) {
    operational = 1,
    damaged = 2,
    unknown = 0,
};

const CacheKey = struct {
    springs_left: usize,
    counts_left: usize,
};

const CacheKeyContext = struct {
    pub fn hash(ctx: @This(), key: CacheKey) u64 {
        _ = ctx;
        var h = std.hash.Fnv1a_64.init();
        h.update(&std.mem.toBytes(key.springs_left));
        h.update(&std.mem.toBytes(key.counts_left));
        return h.final();
    }

    pub fn eql(ctx: @This(), lhs: CacheKey, rhs: CacheKey) bool {
        _ = ctx;
        return lhs.springs_left == rhs.springs_left and lhs.counts_left == rhs.counts_left;
    }
};

const Cache = std.HashMap(CacheKey, u64, CacheKeyContext, std.hash_map.default_max_load_percentage);

const Record = struct {
    allocator: mem.Allocator,
    springs: []Spring,
    counts: []u8,

    fn initParse(allocator: mem.Allocator, s: []const u8) !Record {
        const left_part = mem.sliceTo(s, ' ');
        var springs = try allocator.alloc(Spring, left_part.len);
        errdefer allocator.free(springs);

        for (left_part, 0..) |c, i| {
            springs[i] = switch (c) {
                '.' => .operational,
                '#' => .damaged,
                '?' => .unknown,
                else => unreachable,
            };
        }

        const right_part = s[springs.len + 1 ..];
        const commas = mem.count(u8, right_part, ",");
        var counts = try std.ArrayList(u8).initCapacity(allocator, commas + 1);
        errdefer counts.deinit();

        var it = mem.splitScalar(u8, right_part, ',');
        var slide: usize = 0;
        while (it.next()) |num| : (slide += 1) {
            try counts.append(try fmt.parseInt(u8, num, 10));
        }

        return .{
            .allocator = allocator,
            .springs = springs,
            .counts = try counts.toOwnedSlice(),
        };
    }

    fn deinit(self: *Record) void {
        self.allocator.free(self.springs);
        self.allocator.free(self.counts);
    }

    fn solve(self: *Record) !u64 {
        var cache = Cache.init(self.allocator);
        defer cache.deinit();
        return try countArrangements(self.springs, self.counts, null, &cache);
    }

    fn countArrangements(springs: []Spring, counts: []u8, assumed: ?Spring, cache: *Cache) !u64 {
        // print("springs: ", .{});
        // printSprings(springs);
        // print("counts: {d}\n", .{counts});
        // print("----------\n", .{});
        const cacheKey = CacheKey{ .springs_left = springs.len, .counts_left = counts.len };
        if (cache.get(cacheKey)) |result| {
            return result;
        }

        // if there's nothing else to match and no damaged springs left, then we are over!
        if (counts.len == 0) {
            return if (mem.containsAtLeast(Spring, springs, 1, &[_]Spring{.damaged})) 0 else 1;
        }

        // no springs left...
        if (springs.len == 0) {
            return 0;
        }

        // sum up all the remaining groups' count to be matched
        const to_be_matched = blk: {
            var sum: u8 = 0;
            for (counts) |count| {
                sum += count;
            }
            break :blk sum;
        };

        // count the remaining damaged and unknown springs, aka, unmatched springs
        const unmatched = springs.len - mem.count(Spring, springs, &[_]Spring{.operational});

        // if there insufficient unmatched springs, then we cannot proceed
        if (to_be_matched > unmatched) {
            return 0;
        }

        const spring = assumed orelse springs[0];
        const result: u64 = switch (spring) {
            .operational => blk: {
                // skip all operational springs and proceed
                const next_non_operational = mem.indexOfAny(Spring, springs, &[_]Spring{ .damaged, .unknown }) orelse springs.len - 1;
                break :blk try countArrangements(springs[next_non_operational..], counts, null, cache);
            },
            .damaged => blk: {
                // we don't have sufficient springs left to match
                if (springs.len < counts[0]) {
                    break :blk 0;
                }

                // there is not enough contiguous springs to match
                if (mem.indexOfScalar(Spring, springs[0..counts[0]], .operational)) |_| {
                    break :blk 0;
                }

                // if we have the exact amount of springs and it's the last group to match
                if (springs.len == counts[0]) {
                    break :blk if (counts.len == 1) 1 else 0;
                }

                // if we have more springs left to match
                // we cannot have a damaged spring that causes the length of contiguous damaged springs to be greater
                if (springs[counts[0]] == .damaged) {
                    break :blk 0;
                }

                break :blk try countArrangements(springs[counts[0] + 1 ..], counts[1..], null, cache);
            },
            .unknown => blk: {
                const arrangements_as_if_it_were_operational = try countArrangements(springs[1..], counts, null, cache);
                const arrangements_as_it_it_were_damaged = try countArrangements(springs, counts, .damaged, cache);
                break :blk arrangements_as_if_it_were_operational + arrangements_as_it_it_were_damaged;
            },
        };

        cache.put(cacheKey, result) catch {};
        return result;
    }

    fn unfold(self: *Record) !void {
        const old_springs = self.springs;
        const springs = blk: {
            const old_len = old_springs.len;
            const new_len = old_len * 5 + 4;
            const unfolded = try self.allocator.alloc(Spring, new_len);
            errdefer self.allocator.free(unfolded);
            @memcpy(unfolded[0..old_len], old_springs);
            var slide: usize = old_len;
            while (slide < new_len) : (slide += old_len + 1) {
                unfolded[slide] = .unknown;
                @memcpy(unfolded[slide + 1 .. slide + 1 + old_len], old_springs);
            }
            break :blk unfolded;
        };
        self.springs = springs;
        self.allocator.free(old_springs);

        const old_counts = self.counts;
        const counts = blk: {
            const old_len = self.counts.len;
            const new_len = old_len * 5;
            const unfolded = try self.allocator.alloc(u8, new_len);
            var slide: usize = 0;
            while (slide < new_len) : (slide += old_len) {
                @memcpy(unfolded[slide .. slide + old_len], old_counts);
            }
            break :blk unfolded;
        };
        self.counts = counts;
        self.allocator.free(old_counts);
    }

    fn verify(allocator: mem.Allocator, springs: []Spring, counts: []u8) !bool {
        var list = try std.ArrayList(u8).initCapacity(allocator, counts.len);
        defer list.deinit();

        var it = mem.tokenizeScalar(Spring, springs, .operational);
        var slide: usize = 0;
        while (it.next()) |segment| : (slide += 1) {
            if (slide >= counts.len) return false;
            if (mem.indexOfScalar(Spring, segment, .unknown)) |_| {
                return false;
            }
            const count: usize = @intCast(counts[slide]);
            if (segment.len != count) {
                return false;
            }
        }
        return slide == counts.len;
    }

    fn printSprings(springs: []Spring) void {
        for (springs) |spring| {
            const c: u8 = switch (spring) {
                .operational => '.',
                .damaged => '#',
                .unknown => '?',
            };
            print("{c}", .{c});
        }
        print("\n", .{});
    }
};

test "example - part 1" {
    const allocator = testing.allocator;

    var sum: u64 = 0;
    var it = mem.tokenizeScalar(u8, example, '\n');
    while (it.next()) |line| {
        var rec = try Record.initParse(allocator, line);
        defer rec.deinit();
        sum += try rec.solve();
    }

    try testing.expectEqual(21, sum);
}

test "input - part 1" {
    var logging_allocator = heap.LoggingAllocator(.debug, .debug).init(heap.page_allocator);
    const allocator = logging_allocator.allocator();

    var sum: u64 = 0;
    var it = mem.tokenizeScalar(u8, input, '\n');
    while (it.next()) |line| {
        var rec = try Record.initParse(allocator, line);
        defer rec.deinit();
        sum += try rec.solve();
    }

    try testing.expectEqual(7670, sum);
}

test "example - part 2" {
    // if (true) return error.SkipZigTest;
    var logging_allocator = heap.LoggingAllocator(.debug, .debug).init(testing.allocator);
    const allocator = logging_allocator.allocator();

    var sum: u64 = 0;
    var it = mem.tokenizeScalar(u8, example, '\n');
    while (it.next()) |line| {
        // print("{s}\n", .{line});
        var rec = try Record.initParse(allocator, line);
        defer rec.deinit();
        try rec.unfold();
        sum += try rec.solve();
    }

    try testing.expectEqual(525152, sum);
}

test "input - part 2" {
    // if (true) return error.SkipZigTest;
    var logging_allocator = heap.LoggingAllocator(.debug, .debug).init(heap.page_allocator);
    const allocator = logging_allocator.allocator();

    var sum: u64 = 0;
    var it = mem.tokenizeScalar(u8, input, '\n');
    while (it.next()) |line| {
        var rec = try Record.initParse(allocator, line);
        defer rec.deinit();
        try rec.unfold();
        sum += try rec.solve();
    }

    try testing.expectEqual(157383940585037, sum);
}
