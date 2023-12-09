const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

fn sumOfPartNumbers(s: []const u8) usize {
    const width = std.mem.indexOfScalar(u8, s, '\n').?;
    var sum: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (std.ascii.isDigit(s[i])) {
            const num_length = blk: {
                var len: usize = 1;
                while (std.ascii.isDigit(s[i + len])) : (len += 1) {}
                break :blk len;
            };
            if (hasAdjacentSymbol(s, width, i, num_length)) {
                const num = std.fmt.parseInt(usize, s[i .. i + num_length], 10) catch 0;
                sum += num;
            }
            i += num_length;
        }
    }
    return sum;
}

fn hasAdjacentSymbol(s: []const u8, width: usize, start: usize, len: usize) bool {
    // check left position
    if (start > 0) {
        const c = s[start - 1];
        if (c != '\n' and c != '.') {
            return true;
        }
    }
    // check right position
    if (start + len < s.len) {
        const c = s[start + len];
        if (c != '\n' and c != '.') {
            return true;
        }
    }
    // check row above
    if (start > width) {
        const begin = start -| width -| 2;
        const end = begin + len + 2;
        const symbol_found = for (begin..end) |i| {
            const c = s[i];
            if (c != '\n' and c != '.' and !std.ascii.isDigit(c)) {
                break true;
            }
        } else false;
        if (symbol_found) {
            return true;
        }
    }
    //check row below
    if (start + len + width < s.len) {
        const begin = start + width;
        const end = begin + len + 2;
        const symbol_found = for (begin..end) |i| {
            const c = s[i];
            if (c != '\n' and c != '.' and !std.ascii.isDigit(c)) {
                break true;
            }
        } else false;
        if (symbol_found) {
            return true;
        }
    }
    return false;
}

test "example - part 1" {
    const sum_of_part_numbers = sumOfPartNumbers(example);
    try std.testing.expectEqual(@as(usize, 4361), sum_of_part_numbers);
}

test "input - part 1" {
    const sum_of_part_numbers = sumOfPartNumbers(input);
    try std.testing.expectEqual(@as(usize, 543867), sum_of_part_numbers);
}
