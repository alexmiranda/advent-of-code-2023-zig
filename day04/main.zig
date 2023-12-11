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
        winning_numbers.mask = 0;
        var winning_numbers_it = std.mem.tokenizeScalar(u8, it.next().?, ' ');
        while (winning_numbers_it.next()) |num| {
            winning_numbers.set(std.fmt.parseInt(usize, num, 10) catch unreachable);
        }

        numbers_you_have.mask = 0;
        var numbers_you_have_it = std.mem.tokenizeScalar(u8, it.next().?, ' ');
        while (numbers_you_have_it.next()) |num| {
            numbers_you_have.set(std.fmt.parseInt(usize, num, 10) catch unreachable);
        }

        numbers_you_have.setIntersection(winning_numbers);
        const count = numbers_you_have.count();
        const scratchcard_points = if (count == 0) 0 else std.math.pow(usize, 2, count - 1);
        total_points += scratchcard_points;
    }
    return total_points;
}

test "example - part 1" {
    const points = calculatePoints(example);
    try std.testing.expectEqual(@as(usize, 13), points);
}

test "inpur - part 1" {
    const points = calculatePoints(input);
    try std.testing.expectEqual(@as(usize, 26346), points);
}
