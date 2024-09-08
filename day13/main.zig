const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const fmt = std.fmt;
const print = std.debug.print;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const TerrainIterator = mem.WindowIterator(u8);

const Pattern = struct {
    allocator: mem.Allocator,
    rows: []u32,
    cols: []u32,
    width: u5,
    height: u5,

    fn initParse(allocator: mem.Allocator, it: *TerrainIterator) !Pattern {
        var rows = std.ArrayList(u32).init(allocator);
        errdefer rows.deinit();

        var cols = std.ArrayList(u32).init(allocator);
        errdefer cols.deinit();

        var width: u5 = 0;
        var n: u32 = 0;
        var last: u8 = undefined;
        var slide: usize = 0;
        while (it.next()) |s| {
            // print("{c}", .{s[0]});
            switch (s[0]) {
                '.' => {
                    n <<= 1;
                    if (width > 0) cols.items[slide % width] <<= 1;
                    slide += 1;
                },
                '#' => {
                    n = (n << 1) | 1;
                    if (width > 0) {
                        const v = cols.items[slide % width];
                        cols.items[slide % width] = (v << 1) | 1;
                    }
                    slide += 1;
                },
                '\n' => {
                    if (last == '\n') break;
                    try rows.append(n);
                    if (width == 0) {
                        width = @truncate(slide);
                        try cols.ensureTotalCapacityPrecise(width);
                        for (0..width) |i| {
                            const shift: u5 = @truncate(width - i - 1);
                            const mask = @as(u32, 1) << shift;
                            const bit = (n & mask) >> shift;
                            cols.appendAssumeCapacity(bit);
                        }
                    }
                    n = 0;
                },
                else => unreachable,
            }
            last = s[0];
        }

        const height: u5 = @truncate(slide / width);
        return .{
            .allocator = allocator,
            .rows = try rows.toOwnedSlice(),
            .cols = try cols.toOwnedSlice(),
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: *Pattern) void {
        self.allocator.free(self.rows);
        self.allocator.free(self.cols);
    }

    fn summarise(self: *Pattern, smudges: u5) usize {
        var count_smudges = smudges;
        // horizontal
        if (findReflection(self.rows, self.width, &count_smudges)) |i| {
            return i * 100;
        }
        // vertical
        if (findReflection(self.cols, self.height, &count_smudges)) |i| {
            return i;
        }
        return 0;
    }

    fn findReflection(grid: []u32, size: u5, smudges: *u5) ?usize {
        var max: usize = 0;
        outer: for (1..grid.len) |i| {
            var smudges_left = smudges.*;
            var it = mem.reverseIterator(grid[0..i]);
            const right_part = grid[i..];
            var slide: usize = 0;
            while (it.next()) |lhs| : (slide += 1) {
                if (slide >= right_part.len) break;
                const rhs = right_part[slide];
                if (countBitsDiffAtMost(lhs, rhs, size, smudges_left)) {
                    // if we found a smudge, we decrement the smudges left
                    // if the numbers of smudges left were already 0, then we continue searching for another
                    // possible reflection line
                    if (lhs != rhs) {
                        smudges_left = std.math.sub(u5, smudges_left, 1) catch |err| switch (err) {
                            error.Overflow => continue :outer,
                            else => unreachable,
                        };
                    }
                    continue;
                }
                continue :outer;
            }

            // if there are no smudges left, then we found a reflection line
            if (smudges_left == 0) {
                max = @max(max, i);
            }
        }

        return if (max == 0) null else blk: {
            // if we found a reflection, it's guaranteed that the numbers of smudges left was 0
            smudges.* = 0;
            break :blk max;
        };
    }

    // unused
    fn printRows(self: *Pattern) !void {
        return printGrid(self.allocator, self.rows, self.width);
    }

    // unused
    fn printCols(self: *Pattern) !void {
        return printGrid(self.allocator, self.cols, self.height);
    }

    fn printGrid(allocator: mem.Allocator, nums: []u32, len: u5) !void {
        const buf = try allocator.alloc(u8, len);
        defer allocator.free(buf);
        for (nums) |n| {
            const slice = try fmt.bufPrint(buf, "{b}", .{n});
            mem.replaceScalar(u8, slice, '0', '.');
            mem.replaceScalar(u8, slice, '1', '#');
            if (slice.len < buf.len) {
                mem.rotate(u8, buf, slice.len);
                for (0..(buf.len - slice.len)) |i| buf[i] = '.';
            }
            print("{s}\n", .{buf});
        }
    }
};

fn countBitsDiffAtMost(a: u32, b: u32, size: u5, expected_count: u5) bool {
    std.debug.assert(expected_count <= 1);

    // numbers are equal
    if (a == b) return true;
    if (expected_count == 0) return a == b;

    // diff (xor) considering only the least significant digits up to `size`
    const shift: u5 = size +| 1;
    const diff = (a ^ b) % (@as(u32, 1) << shift);

    // if we know we expect only 1 bit diff, we only need to know if diff is a power of two
    if (expected_count == 1) {
        if (diff == 0) return false;
        return std.math.isPowerOfTwo(diff);
    }

    // not implemented...
    unreachable;
}

fn solve(allocator: mem.Allocator, s: []const u8, smudges: u5) !usize {
    var it = mem.window(u8, s, 1, 1);
    var sum: usize = 0;
    while (it.index != null) {
        var pattern = try Pattern.initParse(allocator, &it);
        defer pattern.deinit();
        sum += pattern.summarise(smudges);
    }
    return sum;
}

test "example - part 1" {
    const answer = try solve(testing.allocator, example, 0);
    try testing.expectEqual(405, answer);
}

test "input - part 1" {
    const answer = try solve(testing.allocator, input, 0);
    try testing.expectEqual(32723, answer);
}

test "example - part 2" {
    const answer = try solve(testing.allocator, example, 1);
    try testing.expectEqual(400, answer);
}

test "input - part 2" {
    const answer = try solve(testing.allocator, input, 1);
    try testing.expectEqual(34536, answer);
}

test "countBitsDiffAtMost" {
    try testing.expect(countBitsDiffAtMost(0, 0, 31, 0));
    try testing.expect(countBitsDiffAtMost(0, 0, 31, 1));
    try testing.expect(countBitsDiffAtMost(1, 1, 31, 0));
    try testing.expect(countBitsDiffAtMost(1, 1, 31, 1));
    try testing.expect(countBitsDiffAtMost(std.math.maxInt(u32), std.math.maxInt(u32), 31, 0));
    try testing.expect(countBitsDiffAtMost(0b1000, 0b1001, 4, 1));
    try testing.expect(countBitsDiffAtMost(0b1000, 0b1010, 4, 1));
    try testing.expect(countBitsDiffAtMost(0b1000, 0b0000, 4, 1));
    try testing.expect(countBitsDiffAtMost(0b1001, 0b0001, 4, 1));
    try testing.expect(!countBitsDiffAtMost(0b1000, 0b1101, 4, 1));
    try testing.expect(!countBitsDiffAtMost(0b10000, 0b01000, 5, 1));
}
