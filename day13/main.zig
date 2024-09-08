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

    fn summarise(self: *Pattern) usize {
        var answer: usize = 0;
        if (findReflection(self.rows)) |i| {
            answer += i * 100;
        }
        if (findReflection(self.cols)) |i| {
            answer += i;
        }
        return answer;
    }

    fn findReflection(grid: []u32) ?usize {
        var max: usize = 0;
        outer: for (1..grid.len) |i| {
            var it = mem.reverseIterator(grid[0..i]);
            const right_part = grid[i..];
            var slide: usize = 0;
            while (it.next()) |lhs| : (slide += 1) {
                if (slide >= right_part.len) break;
                const rhs = right_part[slide];
                if (lhs != rhs) {
                    continue :outer;
                }
            }
            max = @max(max, i);
        }

        return if (max == 0) null else max;
    }

    fn printRows(self: *Pattern) !void {
        const buf = try self.allocator.alloc(u8, self.width);
        defer self.allocator.free(buf);
        for (self.rows) |n| {
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

    fn printCols(self: *Pattern) !void {
        const buf = try self.allocator.alloc(u8, self.height);
        defer self.allocator.free(buf);
        for (self.cols) |n| {
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

fn solve(allocator: mem.Allocator, s: []const u8) !usize {
    var it = mem.window(u8, s, 1, 1);
    var sum: usize = 0;
    while (it.index != null) {
        var pattern = try Pattern.initParse(allocator, &it);
        defer pattern.deinit();
        sum += pattern.summarise();
    }
    return sum;
}

test "example - part 1" {
    const answer = try solve(testing.allocator, example);
    try testing.expectEqual(405, answer);
}

test "input - part 1" {
    const answer = try solve(testing.allocator, input);
    try testing.expectEqual(32723, answer);
}
