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

fn sumOfGearRatios(s: []const u8) usize {
    var sum: usize = 0;
    const width = std.mem.indexOfScalar(u8, s, '\n').? + 1;
    const rows_count = s.len / width;
    for (0..rows_count, 1..rows_count + 1) |curr_idx, next_idx| {
        const prev: ?[]const u8 = if (curr_idx > 0) s[(curr_idx - 1) * width .. (curr_idx - 1) * width + width - 1] else null;
        const curr: []const u8 = s[curr_idx * width .. curr_idx * width + width - 1];
        const next: ?[]const u8 = if (next_idx < rows_count) s[next_idx * width .. next_idx * width + width - 1] else null;
        for (0..width - 1) |i| {
            if (curr[i] != '*') continue;
            if (searchGearPartNumbers(curr, prev, next, i)) |parts| {
                const gear_ratio = parts.@"0" * parts.@"1";
                // std.debug.print("{d}:{d} => {d} * {d} = {d}\n", .{ curr_idx + 1, i + 1, parts.@"0", parts.@"1", gear_ratio });
                sum += gear_ratio;
            }
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

fn searchGearPartNumbers(curr: []const u8, prev: ?[]const u8, next: ?[]const u8, index: usize) ?struct { usize, usize } {
    var a: usize = undefined;
    var b: usize = undefined;
    var parts_count: usize = 0;
    // check if there is a part connected to the left
    if (index > 0 and std.ascii.isDigit(curr[index - 1])) {
        a = expand(curr, index - 1, index);
        parts_count += 1;
    }

    // check if there is a part connected to the right
    if (index + 1 < curr.len and std.ascii.isDigit(curr[index + 1])) {
        const num = expand(curr, index + 1, index + 2);
        if (parts_count == 0) a = num else b = num;
        parts_count += 1;
    }

    const begin = index -| 1;
    const end = if (index + 1 == curr.len) curr.len else index + 2;
    inline for (.{ prev, next }) |l| {
        if (l) |line| {
            // std.debug.print("searching for parts in: {s}\n", .{line[begin..end]});
            var prev_char_was_digit = false;
            for (begin..end) |i| {
                if (std.ascii.isDigit(line[i])) {
                    if (!prev_char_was_digit) {
                        if (parts_count == 2) return null; // two many connected parts
                        const num = expand(line, i, i + 1);
                        if (parts_count == 0) a = num else b = num;
                        parts_count += 1;
                        // std.debug.print("part {d} is connected!\n", .{num});
                    }
                    prev_char_was_digit = true;
                } else {
                    prev_char_was_digit = false;
                }
            }
        }
    }

    if (parts_count == 2) {
        return .{ a, b };
    }

    return null;
}

fn expand(line: []const u8, begin: usize, end: usize) usize {
    const slide_start: usize = blk: {
        var slide: usize = begin;
        break :blk while (slide > 0) : (slide -= 1) {
            if (!std.ascii.isDigit(line[slide - 1])) {
                break slide;
            }
        } else slide;
    };
    const slide_end: usize = blk: {
        var slide: usize = end;
        break :blk while (slide < line.len) : (slide += 1) {
            if (!std.ascii.isDigit(line[slide])) {
                break slide;
            }
        } else slide;
    };
    return std.fmt.parseInt(usize, line[slide_start..slide_end], 10) catch unreachable;
}

test "example - part 1" {
    const sum_of_part_numbers = sumOfPartNumbers(example);
    try std.testing.expectEqual(@as(usize, 4361), sum_of_part_numbers);
}

test "input - part 1" {
    const sum_of_part_numbers = sumOfPartNumbers(input);
    try std.testing.expectEqual(@as(usize, 543867), sum_of_part_numbers);
}

test "example - part 2" {
    const sum_gear_ratios = sumOfGearRatios(example);
    try std.testing.expectEqual(@as(usize, 467835), sum_gear_ratios);
}

test "input - part 2" {
    const sum_gear_ratios = sumOfGearRatios(input);
    try std.testing.expectEqual(@as(usize, 79613331), sum_gear_ratios);
}
