const std = @import("std");
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

fn hash(s: []const u8) u32 {
    var sum: u32 = 0;
    var h: u32 = 0;
    return for (s) |c| switch (c) {
        '\n' => {
            sum += h;
            break sum;
        },
        ',' => {
            sum += h;
            h = 0;
        },
        else => h = (h + c) * 17 % 256,
    } else sum;
}

test "example HASH - part 1" {
    try expectEqual(52, hash("HASH\n"));
}

test "example - part 1" {
    try expectEqual(1320, hash(example));
}

test "input - part 1" {
    try expectEqual(507769, hash(input));
}
