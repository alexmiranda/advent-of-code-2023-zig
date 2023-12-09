const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");
const delimiters = " :,;\n";
const red_limit: usize = 12;
const green_limit: usize = 13;
const blue_limit: usize = 14;

fn countPossibleGames(s: []const u8) !usize {
    var possible_games: usize = 0;
    var game_id: usize = 0;
    var n: usize = 0;

    var it = std.mem.tokenizeAny(u8, s, delimiters);
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "Game")) {
            possible_games += game_id;
            game_id = try std.fmt.parseInt(usize, it.next().?, 10);
        } else if ((std.mem.eql(u8, token, "red") and n > red_limit) or
            (std.mem.eql(u8, token, "green") and n > green_limit) or
            (std.mem.eql(u8, token, "blue") and n > blue_limit))
        {
            it.delimiter = "\n";
            const rest_of_the_line = it.next();
            _ = rest_of_the_line;
            it.delimiter = delimiters;
            game_id = 0;
        } else if (std.ascii.isDigit(token[0])) {
            n = try std.fmt.parseInt(usize, token, 10);
        }
    }

    // the last game_id is not added up because \n is a delimiter
    possible_games += game_id;

    return possible_games;
}

test "example - part 1" {
    const possible_games = try countPossibleGames(example);
    try std.testing.expectEqual(@as(usize, 8), possible_games);
}

test "input - part 1" {
    const possible_games = try countPossibleGames(input);
    try std.testing.expectEqual(@as(usize, 2256), possible_games);
}
