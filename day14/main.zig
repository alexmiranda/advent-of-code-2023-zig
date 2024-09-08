const std = @import("std");
const swap = std.mem.swap;
const expectEqual = std.testing.expectEqual;
const print = std.debug.print;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Tile = enum {
    empty_space,
    rounded_rock,
    cube_shaped_rock,

    inline fn fromChar(c: u8) Tile {
        return switch (c) {
            '.' => .empty_space,
            'O' => .rounded_rock,
            '#' => .cube_shaped_rock,
            else => unreachable,
        };
    }

    fn toChar(self: Tile) u8 {
        return switch (self) {
            .empty_space => '.',
            .rounded_rock => 'O',
            .cube_shaped_rock => '#',
        };
    }
};

fn Grid(comptime size: usize) type {
    return struct {
        tiles: [size][size]Tile = undefined,

        const Self = @This();
        fn fill(self: *Self, s: []const u8) void {
            var slide: usize = 0;
            for (s) |c| switch (c) {
                '.', 'O', '#' => {
                    self.tiles[slide / size][slide % size] = Tile.fromChar(c);
                    slide += 1;
                },
                '\n' => {},
                else => unreachable,
            };
        }

        fn slideNorth(self: *Self) void {
            for (0..size) |col| {
                var first_empty: usize = 0;
                for (0..size) |current| {
                    switch (self.tiles[current][col]) {
                        .empty_space => {},
                        .cube_shaped_rock => first_empty = current + 1,
                        .rounded_rock => {
                            // print("col: {d} current: {d} first_empty: {d} swap: {any}\n", .{ col, current, first_empty, first_empty < current });
                            if (first_empty < current) {
                                swap(Tile, &self.tiles[first_empty][col], &self.tiles[current][col]);
                                std.debug.assert(self.tiles[first_empty][col] == .rounded_rock);
                                std.debug.assert(self.tiles[current][col] == .empty_space);
                                first_empty = first_empty + 1;
                            } else {
                                first_empty = current + 1;
                            }
                        },
                    }
                }
            }
        }

        fn totalLoad(self: *Self) usize {
            const tiles = self.tiles;
            var load: usize = 0;
            for (0..size) |col| {
                for (0..size) |current| {
                    load += switch (tiles[current][col]) {
                        .rounded_rock => size - current,
                        else => 0,
                    };
                }
            }
            return load;
        }

        // unused
        fn printTiles(self: *Self) void {
            for (0..size) |row| {
                for (0..size) |col| {
                    print("{c}", .{self.tiles[row][col].toChar()});
                }
                print("\n", .{});
            }
        }
    };
}

test "example - part 1" {
    var grid = Grid(10){};
    grid.fill(example);
    grid.slideNorth();
    const total_load = grid.totalLoad();
    try expectEqual(136, total_load);
}

test "input - part 1" {
    var grid = Grid(100){};
    grid.fill(input);
    grid.slideNorth();
    const total_load = grid.totalLoad();
    try expectEqual(105003, total_load);
}
