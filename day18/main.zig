const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;
const print = std.debug.print;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Point = struct {
    x: i32,
    y: i32,
};

const Direction = enum {
    up,
    right,
    down,
    left,

    fn fromChar(c: u8) Direction {
        return switch (c) {
            'U' => .up,
            'R' => .right,
            'D' => .down,
            'L' => .left,
            else => unreachable,
        };
    }
};

const DigPlan = struct {
    allocator: mem.Allocator,
    points: []Point,

    fn initParse(allocator: mem.Allocator, buffer: []const u8) !DigPlan {
        // extract a set of all points based on the instructions
        const points = blk: {
            var points = std.ArrayList(Point).init(allocator);
            errdefer points.deinit();

            var point = Point{ .x = 0, .y = 0 };
            try points.append(point);

            var it = mem.tokenizeAny(u8, buffer, " \n");
            while (true) {
                const c = (it.next() orelse break)[0];
                const dir = Direction.fromChar(c);
                const len = try fmt.parseInt(u8, it.next().?, 10);
                _ = try parseHexColour(it.next().?[2..8]); // whatever...
                point = switch (dir) {
                    .up => .{ .x = point.x, .y = point.y + len },
                    .right => .{ .x = point.x + len, .y = point.y },
                    .down => .{ .x = point.x, .y = point.y - len },
                    .left => .{ .x = point.x - len, .y = point.y },
                };
                try points.append(point);
            }
            break :blk try points.toOwnedSlice();
        };
        errdefer allocator.free(points); // just in case :)

        // ensure we've got a polygon
        const first_point = points[0];
        const last_point = points[points.len - 1];
        assert(first_point.x == last_point.x and first_point.y == last_point.y);

        return .{
            .allocator = allocator,
            .points = points,
        };
    }

    fn deinit(self: *DigPlan) void {
        self.allocator.free(self.points);
    }

    fn area(self: *DigPlan) u32 {
        var total: i32 = 0;
        var perimeter: u32 = 0;
        for (0..self.points.len - 1) |i| {
            const a = self.points[i];
            const b = self.points[i + 1];
            perimeter += @abs(a.x - b.x) + @abs(a.y - b.y);
            total += (a.x * b.y) - (a.y * b.x);
        }

        return (@abs(total) / 2) + (perimeter / 2) + 1;
    }

    // maybe for part two...
    fn parseHexColour(buffer: []const u8) !u24 {
        var number: u24 = try fmt.parseInt(u8, buffer[0..2], 16);
        number <<= 8;
        number |= try fmt.parseInt(u8, buffer[2..4], 16);
        number <<= 8;
        number |= try fmt.parseInt(u8, buffer[4..], 16);
        return number;
    }
};

test "example - part 1" {
    const allocator = testing.allocator;
    var plan = try DigPlan.initParse(allocator, example);
    defer plan.deinit();
    const result = plan.area();
    try expectEqual(62, result);
}

test "input - part 1" {
    const allocator = testing.allocator;
    var plan = try DigPlan.initParse(allocator, input);
    defer plan.deinit();
    const result = plan.area();
    try expectEqual(0, result);
}
