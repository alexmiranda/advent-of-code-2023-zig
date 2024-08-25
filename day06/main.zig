const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Race = struct {
    time: usize,
    distance: usize,

    fn computeNumberOfWins(self: Race) i32 {
        const a: f32 = 1.0;
        const b: f32 = @floatFromInt(self.time);
        const c: f32 = @floatFromInt(self.distance);
        const bb = std.math.pow(f32, b, 2.0);
        const delta = bb - (4.0 * a * c);
        const x1 = (-b - std.math.sqrt(delta)) / 2.0 * a;
        const x2 = std.math.ceil((-b + std.math.sqrt(delta)) / 2.0 * a) - 1.0;
        // std.debug.print("x1={d:.2} x2={d:.2}\n", .{ x1, x2 });

        return @intFromFloat(std.math.ceil(x2 - x1));
    }
};

const List = std.BoundedArray(Race, 4);

fn parseRaces(s: []const u8) !List {
    var it = std.mem.splitScalar(u8, s, '\n');
    var times = readLine(it.next().?);
    var distances = readLine(it.next().?);
    var list = try std.BoundedArray(Race, 4).init(0);
    while (times.next()) |time| {
        const distance = distances.next().?;
        // std.debug.print("time = {s} distance = {s}\n", .{ time, distance });
        const t = try std.fmt.parseInt(usize, time, 10);
        const d = try std.fmt.parseInt(usize, distance, 10);
        try list.append(.{ .time = t, .distance = d });
    }
    return list;
}

fn parseSingleRace(allocator: std.mem.Allocator, s: []const u8) !Race {
    var it = std.mem.splitScalar(u8, s, '\n');
    const time = try readNum(allocator, it.next().?);
    const distance = try readNum(allocator, it.next().?);
    return .{ .time = time, .distance = distance };
}

fn readLine(s: []const u8) std.mem.TokenIterator(u8, .scalar) {
    const idx = std.mem.indexOfScalar(u8, s, ':').?;
    return std.mem.tokenizeScalar(u8, s[idx + 1 ..], ' ');
}

fn readNum(allocator: std.mem.Allocator, s: []const u8) !usize {
    const idx = std.mem.indexOfScalar(u8, s, ':').?;
    var buf = try allocator.alloc(u8, s[idx + 1 ..].len);
    defer allocator.free(buf);

    const replacements = std.mem.replace(u8, s[idx + 1 ..], " ", "", buf);
    return try std.fmt.parseInt(usize, buf[0..(buf.len - replacements)], 10);
}

test "example - part 1" {
    const races = try parseRaces(example);
    var result: i32 = 1;
    for (races.slice()) |race| {
        result *= race.computeNumberOfWins();
    }
    try std.testing.expectEqual(@as(i32, 288), result);
}

test "input - part 1" {
    const races = try parseRaces(input);
    var result: i32 = 1;
    for (races.slice()) |race| {
        result *= race.computeNumberOfWins();
    }
    try std.testing.expectEqual(@as(i32, 393120), result);
}

test "example - part 2" {
    const race = try parseSingleRace(std.testing.allocator, example);
    try std.testing.expectEqual(@as(i32, 71503), race.computeNumberOfWins());
}

test "input - part 2" {
    const race = try parseSingleRace(std.testing.allocator, input);
    try std.testing.expectEqual(@as(i32, 36872656), race.computeNumberOfWins());
}
