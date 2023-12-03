const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

fn addCalibrationValues(s: []const u8) usize {
    var sum: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s, '\n');
    while (it.next()) |line| {
        const firstDigit = line[std.mem.indexOfAny(u8, line, "0123456789").?] - '0';
        const secondDigit = line[std.mem.lastIndexOfAny(u8, line, "0123456789").?] - '0';
        const calibrationValue: usize = firstDigit * 10 + secondDigit;
        sum += calibrationValue;
    }
    return sum;
}

test "example - part 1" {
    try std.testing.expectEqual(@as(usize, 142), addCalibrationValues(example));
}

test "input - part 1" {
    try std.testing.expectEqual(@as(usize, 56397), addCalibrationValues(input));
}
