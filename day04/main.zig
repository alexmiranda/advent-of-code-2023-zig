const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");
const IntSet = std.bit_set.IntegerBitSet(100);

fn calculatePoints(s: []const u8) usize {
    var total_points: usize = 0;
    var winning_numbers = IntSet.initEmpty();
    var numbers_you_have = IntSet.initEmpty();
    var it = std.mem.tokenizeAny(u8, s, ":|\n");
    while (it.next()) |_| {
        const scratchcard_points = calculateScore(&winning_numbers, it.next().?, &numbers_you_have, it.next().?);
        total_points += scratchcard_points;
    }
    return total_points;
}

fn calculateScore(winning_numbers: *IntSet, lhs: []const u8, numbers_you_have: *IntSet, rhs: []const u8) usize {
    readNumbersInto(lhs, winning_numbers);
    readNumbersInto(rhs, numbers_you_have);
    numbers_you_have.setIntersection(winning_numbers.*);
    const count = numbers_you_have.count();
    return if (count == 0) 0 else std.math.pow(usize, 2, count - 1);
}

fn readNumbersInto(s: []const u8, set: *IntSet) void {
    set.mask = 0;
    var it = std.mem.tokenizeScalar(u8, s, ' ');
    while (it.next()) |num| {
        set.set(std.fmt.parseInt(usize, num, 10) catch unreachable);
    }
}

test "example - part 1" {
    const points = calculatePoints(example);
    try std.testing.expectEqual(@as(usize, 13), points);
}

test "inpur - part 1" {
    const points = calculatePoints(input);
    try std.testing.expectEqual(@as(usize, 26346), points);
}
