const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");
const IntSet = std.bit_set.IntegerBitSet(100);

const Scratchcard = struct {
    copies: usize = 1,
    matches: usize,
};

fn calculatePoints(s: []const u8) usize {
    var total_points: usize = 0;
    var winning_numbers = IntSet.initEmpty();
    var numbers_you_have = IntSet.initEmpty();
    var it = std.mem.tokenizeAny(u8, s, ":|\n");
    while (it.next()) |_| {
        const matching_pairs = countMatchingPairs(&winning_numbers, it.next().?, &numbers_you_have, it.next().?);
        total_points += if (matching_pairs == 0) 0 else std.math.pow(usize, 2, matching_pairs - 1);
    }
    return total_points;
}

fn calculateTotalScratchcards(allocator: std.mem.Allocator, s: []const u8) !usize {
    const line_count = std.mem.count(u8, s, "\n");
    var scratchcards = try allocator.alloc(Scratchcard, line_count);
    defer allocator.free(scratchcards);

    var winning_numbers = IntSet.initEmpty();
    var numbers_you_have = IntSet.initEmpty();
    var it = std.mem.tokenizeAny(u8, s, ":|\n");
    var slide: usize = 0;
    while (it.next()) |_| : (slide += 1) {
        const lhs = it.next().?;
        const rhs = it.next().?;
        const matches = countMatchingPairs(&winning_numbers, lhs, &numbers_you_have, rhs);
        scratchcards[slide] = .{ .copies = 1, .matches = matches };
    }

    var sum: usize = 0;
    for (scratchcards, 0..) |c, i| {
        sum += c.copies;
        for (i + 1..i + c.matches + 1) |j| {
            scratchcards[j].copies += c.copies;
        }
    }

    return sum;
}

fn countMatchingPairs(winning_numbers: *IntSet, lhs: []const u8, numbers_you_have: *IntSet, rhs: []const u8) usize {
    readNumbersInto(lhs, winning_numbers);
    readNumbersInto(rhs, numbers_you_have);
    numbers_you_have.setIntersection(winning_numbers.*);
    return numbers_you_have.count();
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

test "input - part 1" {
    const points = calculatePoints(input);
    try std.testing.expectEqual(@as(usize, 26346), points);
}

test "example - part 2" {
    const total_scratchcards = try calculateTotalScratchcards(std.testing.allocator, example);
    try std.testing.expectEqual(@as(usize, 30), total_scratchcards);
}

test "input - part 2" {
    const total_scratchcards = try calculateTotalScratchcards(std.testing.allocator, input);
    try std.testing.expectEqual(@as(usize, 8467762), total_scratchcards);
}
