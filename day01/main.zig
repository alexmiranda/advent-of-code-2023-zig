const std = @import("std");
const example1 = @embedFile("example1.txt");
const example2 = @embedFile("example2.txt");
const input = @embedFile("input.txt");
const nums = .{ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" };

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

fn addCalibrationValuesRevised(s: []const u8) usize {
    var sum: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s, '\n');
    while (it.next()) |line| {
        var firstDigitPos: usize = 0;
        var firstDigit: ?usize = null;
        var secondDigit: ?usize = null;
        outer: for (0..line.len) |slide| {
            if (std.ascii.isDigit(line[slide])) {
                firstDigit = line[slide] - '0';
                firstDigitPos = slide;
                break;
            }
            inline for (nums, 1..) |name, digit| {
                if (std.mem.startsWith(u8, line[slide..], name)) {
                    firstDigit = digit;
                    firstDigitPos = slide;
                    break :outer;
                }
            }
        }
        var slide: usize = line.len - 1;
        outer: while (slide >= firstDigitPos) : (slide -= 1) {
            if (std.ascii.isDigit(line[slide])) {
                secondDigit = line[slide] - '0';
                break;
            }
            inline for (nums, 1..) |name, digit| {
                if (std.mem.startsWith(u8, line[slide..], name)) {
                    secondDigit = digit;
                    break :outer;
                }
            }
        }
        const calibrationValue = firstDigit.? * 10 + secondDigit.?;
        sum += calibrationValue;
    }
    return sum;
}

test "example - part 1" {
    try std.testing.expectEqual(142, addCalibrationValues(example1));
}

test "input - part 1" {
    try std.testing.expectEqual(56397, addCalibrationValues(input));
}

test "example - part 2" {
    try std.testing.expectEqual(281, addCalibrationValuesRevised(example2));
}

test "input - part 2" {
    try std.testing.expectEqual(55701, addCalibrationValuesRevised(input));
}
