const std = @import("std");
const print = std.debug.print;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const StepsIterator = struct {
    allocator: std.mem.Allocator,
    lineIterator: std.mem.TokenIterator(u8, .scalar),

    fn next(self: *@This()) !?[]i32 {
        if (self.lineIterator.next()) |line| {
            const size = std.mem.count(u8, line, " ") + 1;
            const step = try self.allocator.alloc(i32, size);

            // parse all the numbers in the next step
            var it = std.mem.splitScalar(u8, line, ' ');
            var slide: usize = 0;
            while (it.next()) |s| : (slide += 1) {
                step[slide] = try std.fmt.parseInt(i32, s, 10);
            }
            return step;
        }
        return null;
    }
};

fn solve(s: []const u8, predictFn: *const fn (std.mem.Allocator, []i32) i32, comptime max_items_per_step: usize) !i32 {
    // by knowing the maximum number of items per line, we can calculate the amount of bytes that we need
    // by calculating the triangular number and multiplying it by the number of bytes for each item
    const max_capacity = @sizeOf(i32) / @sizeOf(u8) * (max_items_per_step * (max_items_per_step + 1) / 2);
    var buf: [max_capacity]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var childAllocator = fba.allocator();

    var it = StepsIterator{
        .allocator = childAllocator,
        .lineIterator = std.mem.tokenizeScalar(u8, s, '\n'),
    };

    var sum: i32 = 0;
    while (try it.next()) |step| {
        defer childAllocator.free(step);
        sum += predictFn(childAllocator, step);
    }

    return sum;
}

fn predictNext(allocator: std.mem.Allocator, step: []i32) i32 {
    if (step.len == 1 or std.mem.allEqual(i32, step, 0)) {
        return 0;
    }

    // ok because we always pass down a fixed buffer allocator with sufficient memory
    const nextStep = allocator.alloc(i32, step.len - 1) catch unreachable;
    defer allocator.free(nextStep);

    var slide: usize = 0;
    for (step[0 .. step.len - 1], step[1..]) |a, b| {
        nextStep[slide] = b - a;
        slide += 1;
    }

    const predicted = predictNext(allocator, nextStep);
    // print("predicted: {d}\n", .{predicted});
    return step[step.len - 1] + predicted;
}

fn predictBackwards(allocator: std.mem.Allocator, step: []i32) i32 {
    if (step.len == 1 or std.mem.allEqual(i32, step, 0)) {
        return 0;
    }

    // ok because we always pass down a fixed buffer allocator with sufficient memory
    const nextStep = allocator.alloc(i32, step.len - 1) catch unreachable;
    defer allocator.free(nextStep);

    var slide: usize = 0;
    for (step[0 .. step.len - 1], step[1..]) |a, b| {
        nextStep[slide] = b - a;
        slide += 1;
    }

    const predicted = predictBackwards(allocator, nextStep);
    // print("predicted: {d}\n", .{predicted});
    return step[0] - predicted;
}

fn printStep(step: []i32) void {
    print("{d}", .{step[0]});
    for (step[1..]) |value| {
        print(" {d}", .{value});
    }
    print("\n", .{});
}

test "example - part 1" {
    const solution = try solve(example, predictNext, 6);
    try std.testing.expectEqual(@as(i32, 114), solution);
}

test "input - part 1" {
    const solution = try solve(input, predictNext, 21);
    try std.testing.expectEqual(@as(i32, 1696140818), solution);
}

test "example - part 2" {
    const solution = try solve(example, predictBackwards, 6);
    try std.testing.expectEqual(@as(i32, 2), solution);
}

test "input - part 2" {
    const solution = try solve(input, predictBackwards, 21);
    try std.testing.expectEqual(@as(i32, 1152), solution);
}
