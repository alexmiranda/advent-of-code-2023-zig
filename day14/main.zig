const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
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

        // slide northwards all the rounded rocks to the first empty tile possible
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

        // rotate clockwise 90 degrees
        fn rotate(self: *Self) void {
            var rotated: [size][size]Tile = undefined;
            for (0..size) |row| {
                for (0..size) |col| {
                    rotated[col][size - 1 - row] = self.tiles[row][col];
                }
            }
            self.tiles = rotated;
        }

        fn spinCycle(self: *Self, allocator: mem.Allocator, n: usize) !void {
            var arena = heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const keys_allocator = arena.allocator();

            const buf_len: usize = size * size;
            var buf = try keys_allocator.alloc(u8, buf_len);
            var seen = std.StringHashMap(usize).init(allocator);
            defer seen.deinit();

            // add the initial state
            try seen.put(self.fingerprint(buf), 0);

            // detect cycle
            var slide: usize = 1;
            const cycle_length = while (slide < n) : (slide += 1) {
                self.doCycle();
                buf = try keys_allocator.alloc(u8, buf_len);
                if (try seen.fetchPut(self.fingerprint(buf), slide)) |kv| {
                    break slide - kv.value;
                }
            } else unreachable;

            // execute the remaining cycles
            const remaining = (n - slide) % cycle_length;
            for (0..remaining) |_| {
                self.doCycle();
            }
        }

        // rotate 4 times: north, west, south and east and slide the rolling rocks
        fn doCycle(self: *Self) void {
            for (0..4) |_| {
                self.slideNorth();
                self.rotate();
            }
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

        // create a string representing the grid state
        fn fingerprint(self: *Self, buf: []u8) []u8 {
            var slide: usize = 0;
            for (0..size) |row| {
                for (0..size) |col| {
                    const c = self.tiles[row][col].toChar();
                    buf[slide] = c;
                    slide += 1;
                }
            }
            return buf[0..slide];
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

test "example - part 2" {
    var grid = Grid(10){};
    grid.fill(example);
    try grid.spinCycle(testing.allocator, 1_000_000_000);
    const total_load = grid.totalLoad();
    try expectEqual(64, total_load);
}

test "input - part 2" {
    var grid = Grid(100){};
    grid.fill(input);
    try grid.spinCycle(testing.allocator, 1_000_000_000);
    const total_load = grid.totalLoad();
    try expectEqual(93742, total_load);
}
