const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Tile = enum {
    empty_space,
    right_angled_mirror,
    left_angled_mirror,
    vertical_splitter,
    horizontal_splitter,

    inline fn fromChar(c: u8) Tile {
        return switch (c) {
            '.' => .empty_space,
            '/' => .right_angled_mirror,
            '\\' => .left_angled_mirror,
            '|' => .vertical_splitter,
            '-' => .horizontal_splitter,
            else => unreachable,
        };
    }

    inline fn bounce(self: Tile, dir: Direction) []Direction {
        var dirs = [_]Direction{ dir, dir };
        switch (self) {
            .empty_space => return dirs[0..1],
            .right_angled_mirror => {
                dirs[1] = switch (dir) {
                    .up => .right,
                    .right => .up,
                    .down => .left,
                    .left => .down,
                };
                return dirs[1..];
            },
            .left_angled_mirror => {
                dirs[1] = switch (dir) {
                    .up => .left,
                    .right => .down,
                    .down => .right,
                    .left => .up,
                };
                return dirs[1..];
            },
            .vertical_splitter => {
                switch (dir) {
                    .left, .right => {
                        dirs[0] = .up;
                        dirs[1] = .down;
                        return dirs[0..];
                    },
                    .up, .down => return dirs[0..1],
                }
            },
            .horizontal_splitter => {
                switch (dir) {
                    .up, .down => {
                        dirs[0] = .left;
                        dirs[1] = .right;
                        return dirs[0..];
                    },
                    .left, .right => return dirs[0..1],
                }
            },
        }
    }
};

const Direction = enum {
    up,
    right,
    down,
    left,
};

fn Contraption(comptime size: u8) type {
    return struct {
        tiles: [size][size]Tile = undefined,

        const Self = @This();

        const Coord = struct {
            row: usize,
            col: usize,

            fn moveTo(self: Coord, dir: Direction) ?Coord {
                switch (dir) {
                    .up => {
                        if (self.row == 0) return null;
                        return .{ .row = self.row - 1, .col = self.col };
                    },
                    .right => {
                        if (self.col == size - 1) return null;
                        return .{ .row = self.row, .col = self.col + 1 };
                    },
                    .down => {
                        if (self.row == size - 1) return null;
                        return .{ .row = self.row + 1, .col = self.col };
                    },
                    .left => {
                        if (self.col == 0) return null;
                        return .{ .row = self.row, .col = self.col - 1 };
                    },
                }
            }
        };

        fn parse(self: *Self, buffer: []const u8) void {
            var slide: usize = 0;
            for (buffer) |c| {
                switch (c) {
                    '\n' => {},
                    else => {
                        self.tiles[slide / size][slide % size] = Tile.fromChar(c);
                        slide += 1;
                    },
                }
            }
        }

        fn bestConfiguration(self: Self, allocator: mem.Allocator) !usize {
            var max: usize = 0;
            // top heading down
            for (0..size) |i| {
                const count = try self.countEnergisedTiles(allocator, .{ .row = 0, .col = i }, .down);
                max = @max(max, count);
            }

            // right heading left
            for (0..size) |i| {
                const count = try self.countEnergisedTiles(allocator, .{ .row = i, .col = size - 1 }, .left);
                max = @max(max, count);
            }

            // down heading up
            for (0..size) |i| {
                const count = try self.countEnergisedTiles(allocator, .{ .row = size - 1, .col = i }, .up);
                max = @max(max, count);
            }

            // left heading right
            for (0..size) |i| {
                const count = try self.countEnergisedTiles(allocator, .{ .row = i, .col = 0 }, .right);
                max = @max(max, count);
            }

            return max;
        }

        fn countEnergisedTiles(self: Self, allocator: mem.Allocator, start_point: Coord, start_direction: Direction) !usize {
            const Bean = struct {
                coord: Coord,
                dir: Direction,
            };

            var queue = std.ArrayList(Bean).init(allocator);
            defer queue.deinit();

            var energised = std.HashMap(Coord, Direction, EnergisedContext, std.hash_map.default_max_load_percentage).init(allocator);
            defer energised.deinit();

            // start with a single bean in the top-left corner moving right
            try queue.append(.{ .coord = start_point, .dir = start_direction });

            // for as long as there are active beans...
            while (queue.popOrNull()) |*bean| {
                const coord = bean.coord;

                // abort bean if we've visited this tile before from the same direction...
                if (try energised.fetchPut(coord, bean.dir)) |kv| {
                    if (kv.value == bean.dir) {
                        continue;
                    }
                }

                // move to next coordinate and create a new bean state
                // each bean can split in at most two beans
                const tile = self.tiles[coord.row][coord.col];
                for (tile.bounce(bean.dir)) |next_dir| {
                    if (coord.moveTo(next_dir)) |next_coord| {
                        try queue.append(.{ .coord = next_coord, .dir = next_dir });
                    }
                }
            }

            return energised.count();
        }

        const EnergisedContext = struct {
            pub fn hash(ctx: @This(), coord: Coord) u64 {
                _ = ctx;
                return coord.row * size + coord.col;
            }

            pub fn eql(ctx: @This(), lhs: Coord, rhs: Coord) bool {
                _ = ctx;
                return lhs.row == rhs.row and lhs.col == rhs.col;
            }
        };
    };
}

const ExampleContraption = Contraption(10);
const InputContraption = Contraption(110);

test "example - part 1" {
    const allocator = testing.allocator;
    var contraption = ExampleContraption{};
    contraption.parse(example);
    const start_point = ExampleContraption.Coord{ .row = 0, .col = 0 };
    try expectEqual(46, contraption.countEnergisedTiles(allocator, start_point, .right));
}

test "input - part 1" {
    const allocator = testing.allocator;
    var contraption = InputContraption{};
    contraption.parse(input);
    const start_point = InputContraption.Coord{ .row = 0, .col = 0 };
    try expectEqual(8249, contraption.countEnergisedTiles(allocator, start_point, .right));
}

test "example - part 2" {
    const allocator = testing.allocator;
    var contraption = ExampleContraption{};
    contraption.parse(example);
    try expectEqual(51, contraption.bestConfiguration(allocator));
}

test "input - part 2" {
    const allocator = testing.allocator;
    var contraption = InputContraption{};
    contraption.parse(input);
    try expectEqual(8444, contraption.bestConfiguration(allocator));
}
