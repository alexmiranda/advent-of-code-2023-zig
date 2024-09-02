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
        // print("=== new search ===\n", .{});
        // print("springs: ", .{});
        // printSprings(self.springs);
        // print("counts: {d}\n", .{self.counts});

        const State = struct {
            springs: []Spring,
            pos: usize = 0,
        };

        var mutations = std.ArrayList(State).init(self.allocator);
        defer mutations.deinit();

        {
            const springs = try self.clone(self.springs);
            errdefer self.allocator.free(springs);
            @memcpy(springs, self.springs);
            try mutations.append(.{ .springs = springs, .pos = 0 });
        }

        var counter: u64 = 0;
        while (mutations.items.len > 0) {
            const state = mutations.pop();
            defer self.allocator.free(state.springs);

            if (mem.indexOfScalarPos(Spring, state.springs, state.pos, .unknown)) |index| {
                {
                    var springs = try self.clone(state.springs);
                    errdefer self.allocator.free(springs);
                    springs[index] = .operational;
                    try mutations.append(.{ .springs = springs, .pos = index + 1 });
                }

                {
                    var springs = try self.clone(state.springs);
                    errdefer self.allocator.free(springs);
                    springs[index] = .damaged;
                    try mutations.append(.{ .springs = springs, .pos = index + 1 });
                }
            } else if (try self.verify(state.springs)) {
                // print("solution: ", .{});
                // printSprings(state.springs);
                counter += 1;
            }
        }

        return counter;
    }

    fn clone(self: *Record, springs: []Spring) ![]Spring {
        const copy = try self.allocator.alloc(Spring, springs.len);
        errdefer self.allocator.free(copy);
        @memcpy(copy, springs);
        return copy;
    }

    fn verify(self: *Record, springs: []Spring) !bool {
        var list = try std.ArrayList(u8).initCapacity(self.allocator, self.counts.len);
        defer list.deinit();

        var it = mem.tokenizeScalar(Spring, springs, .operational);
        var slide: usize = 0;
        while (it.next()) |segment| : (slide += 1) {
            if (slide >= self.counts.len) return false;
            if (mem.indexOfScalar(Spring, segment, .unknown)) |_| {
                return false;
            }
            const count: usize = @intCast(self.counts[slide]);
            if (segment.len != count) {
                return false;
            }
        }
        return slide == self.counts.len;
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
    var logging_allocator = heap.loggingAllocator(testing.allocator);
    const allocator = logging_allocator.allocator();

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
    if (true) return error.SkipZigTest;
    const allocator = testing.allocator;

    var sum: u64 = 0;
    var it = mem.tokenizeScalar(u8, input, '\n');
    while (it.next()) |line| {
        var rec = try Record.initParse(allocator, line);
        defer rec.deinit();
        sum += try rec.solve();
    }

    try testing.expectEqual(7670, sum);
}
