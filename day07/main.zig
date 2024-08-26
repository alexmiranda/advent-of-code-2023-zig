const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");
const print = std.debug.print;
const indexOfScalar = std.mem.indexOfScalar;

const series = "23456789TJQKA";
const wildcard = indexOfScalar(u8, series, 'J').? + 2;
const wildcard_strength = 1; // when using J as wildcard, then it's worth 1 instead of 11

const HandType = enum(u3) {
    five_of_a_kind = 7,
    four_of_a_kind = 6,
    full_house = 5,
    three_of_a_kind = 4,
    two_pair = 3,
    one_pair = 2,
    high_card = 1,
    not_specified = 0,

    const masks = blk: {
        var result: [5]u20 = undefined;
        for (&result, 0..) |*p, i| p.* = 0b1111 << 4 * (4 - i);
        break :blk result;
    };

    fn compute(h: u32, comptime use_wildcard: bool) HandType {
        var hand = h;
        var a: u8 = 0;
        var b: u8 = 0;
        var jokers: u8 = 0;
        for (masks, 0..) |m, i| {
            const padl: u5 = @intCast(4 * (4 - i));
            const lhs = (hand & m) >> padl;
            if (lhs == 0) continue;

            hand &= ~m;
            var count: u8 = 1;
            for (masks[i + 1 ..], i + 1..) |mm, j| {
                const padr: u5 = @intCast(4 * (4 - j));
                const rhs = (hand & mm) >> padr;
                if (rhs == 0) continue;
                if (lhs == rhs) {
                    count += 1;
                    hand &= ~mm;
                }
            }

            if (use_wildcard and lhs == wildcard_strength) {
                jokers = count;
            } else if (count >= a) {
                b = a;
                a = count;
            } else if (count > b) {
                b = count;
            }

            if (hand == 0) break;
        }

        if (use_wildcard) {
            a += jokers;
        }

        if (a == 5) {
            return .five_of_a_kind;
        } else if (a == 4) {
            return .four_of_a_kind;
        } else if (a == 3 and b == 2) {
            return .full_house;
        } else if (a == 3) {
            return .three_of_a_kind;
        } else if (a == 2 and b == 2) {
            return .two_pair;
        } else if (a == 2) {
            return .one_pair;
        } else {
            return .high_card;
        }
    }
};

const Round = struct {
    hand: u32,
    bid: u16,
    type: HandType = .not_specified,

    fn lessThan(ctx: void, lhs: Round, rhs: Round) bool {
        _ = ctx;
        if (@intFromEnum(lhs.type) < @intFromEnum(rhs.type)) {
            return true;
        } else if (@intFromEnum(lhs.type) == @intFromEnum(rhs.type)) {
            return lhs.hand < rhs.hand;
        }
        return false;
    }
};

fn totalWinnings(rounds: []Round) u64 {
    std.sort.block(Round, rounds, {}, Round.lessThan);
    var total_winnings: u64 = 0;
    for (rounds, 1..) |round, i| {
        total_winnings += i * round.bid;
    }
    return total_winnings;
}

fn parseInput(s: []const u8, dest: []Round, comptime use_wildcard: bool) !void {
    var slide: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s, '\n');
    while (it.next()) |line| : (slide += 1) {
        var hand: u32 = 0;
        for (line[0..5]) |c| {
            var card_strength: u4 = @intCast(indexOfScalar(u8, series, c).? + 2); // 2..13
            // when playing using a wildcard, then the J strength = 1
            if (use_wildcard and card_strength == wildcard) {
                card_strength = wildcard_strength;
            }
            hand <<= 4;
            hand |= card_strength;
            // print("card_strength: {c} ({d}) hand={b:0>20}\n", .{ series[card_strength - 2], card_strength, hand });
        }
        const bid = try std.fmt.parseUnsigned(u16, line[6..], 10);
        dest[slide] = .{ .hand = hand, .bid = bid, .type = HandType.compute(hand, use_wildcard) };
    }
}

test "example - part 1" {
    var rounds: [5]Round = undefined;
    try parseInput(example, &rounds, false);
    const total_winnings = totalWinnings(&rounds);
    try std.testing.expectEqual(@as(u64, 6440), total_winnings);
}

test "input - part 1" {
    var rounds: [1000]Round = undefined;
    try parseInput(input, &rounds, false);
    const total_winnings = totalWinnings(&rounds);
    try std.testing.expectEqual(@as(u64, 253910319), total_winnings);
}

test "example - part 2" {
    var rounds: [5]Round = undefined;
    try parseInput(example, &rounds, true);
    const total_winnings = totalWinnings(&rounds);
    try std.testing.expectEqual(@as(u64, 5905), total_winnings);
}

test "input - part 2" {
    var rounds: [1000]Round = undefined;
    try parseInput(input, &rounds, true);
    const total_winnings = totalWinnings(&rounds);
    try std.testing.expectEqual(@as(u64, 254083736), total_winnings);
}
