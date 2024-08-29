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

fn solvePart1(allocator: std.mem.Allocator, s: []const u8) !i32 {
    var it = StepsIterator{
        .allocator = allocator,
        .lineIterator = std.mem.tokenizeScalar(u8, s, '\n'),
    };

    var sum: i32 = 0;
    while (try it.next()) |step| {
        defer allocator.free(step);
        sum += try predictNext(allocator, step);
    }

    return sum;
}

fn solvePart2(allocator: std.mem.Allocator, s: []const u8) !i32 {
    var it = StepsIterator{
        .allocator = allocator,
        .lineIterator = std.mem.tokenizeScalar(u8, s, '\n'),
    };

    var sum: i32 = 0;
    while (try it.next()) |step| {
        defer allocator.free(step);
        sum += try predictBackwards(allocator, step);
    }

    return sum;
}

fn predictNext(allocator: std.mem.Allocator, step: []i32) !i32 {
    if (step.len == 1 or std.mem.allEqual(i32, step, 0)) {
        return 0;
    }
    const nextStep = try allocator.alloc(i32, step.len - 1);
    defer allocator.free(nextStep);

    var slide: usize = 0;
    for (step[0 .. step.len - 1], step[1..]) |a, b| {
        nextStep[slide] = b - a;
        slide += 1;
    }

    const predicted = try predictNext(allocator, nextStep);
    // print("predicted: {d}\n", .{predicted});
    return step[step.len - 1] + predicted;
}

fn predictBackwards(allocator: std.mem.Allocator, step: []i32) !i32 {
    if (step.len == 1 or std.mem.allEqual(i32, step, 0)) {
        return 0;
    }
    const nextStep = try allocator.alloc(i32, step.len - 1);
    defer allocator.free(nextStep);

    var slide: usize = 0;
    for (step[0 .. step.len - 1], step[1..]) |a, b| {
        nextStep[slide] = b - a;
        slide += 1;
    }

    const predicted = try predictBackwards(allocator, nextStep);
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
    const solution = try solvePart1(std.testing.allocator, example);
    try std.testing.expectEqual(@as(i32, 114), solution);
}

test "input - part 1" {
    const solution = try solvePart1(std.testing.allocator, input);
    try std.testing.expectEqual(@as(i32, 1696140818), solution);
}

test "example - part 2" {
    const solution = try solvePart2(std.testing.allocator, example);
    try std.testing.expectEqual(@as(i32, 2), solution);
}

test "input - part 2" {
    const solution = try solvePart2(std.testing.allocator, input);
    try std.testing.expectEqual(@as(i32, 1152), solution);
}
