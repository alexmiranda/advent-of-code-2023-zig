const std = @import("std");
const print = std.debug.print;
const example1 = @embedFile("example1.txt");
const example2 = @embedFile("example2.txt");
const example3 = @embedFile("example3.txt");
const example_two_loops = @embedFile("example_two_loops.txt");
const example4 = @embedFile("example4.txt");
const example5 = @embedFile("example5.txt");
const example6 = @embedFile("example6.txt");
const example_squeeze = @embedFile("example_squeeze.txt");
const input = @embedFile("input.txt");

const MazeError = error{
    tileDirectionMismatch,
};

const Direction = enum {
    north,
    south,
    west,
    east,

    inline fn opposingDirection(self: Direction) Direction {
        return switch (self) {
            .north => .south,
            .south => .north,
            .east => .west,
            .west => .east,
        };
    }
};

// using a tuple type because why not? :)
const TileDirections = std.meta.Tuple(&[_]type{ Direction, Direction });

const Tile = enum {
    northSouth,
    eastWest,
    northEast,
    northWest,
    southWest,
    southEast,
    ground,
    start,

    // NOTE: needs to be consistent with the enum order!
    const tile_directions = [_]TileDirections{
        .{ .north, .south },
        .{ .east, .west },
        .{ .north, .east },
        .{ .north, .west },
        .{ .south, .west },
        .{ .south, .east },
    };

    inline fn fromChar(char: u8) Tile {
        return switch (char) {
            '|' => .northSouth,
            '-' => .eastWest,
            'L' => .northEast,
            'J' => .northWest,
            '7' => .southWest,
            'F' => .southEast,
            '.', 'O', 'I' => .ground,
            'S' => .start,
            else => unreachable,
        };
    }

    inline fn toChar(self: Tile) u8 {
        return switch (self) {
            .northSouth => '|',
            .eastWest => '-',
            .northEast => 'L',
            .northWest => 'J',
            .southWest => '7',
            .southEast => 'F',
            .ground => '.',
            .start => 'S',
        };
    }

    // returns the two exit direction of a given tile if it's a navigable tile
    fn directions(self: Tile) ?TileDirections {
        const i = @intFromEnum(self);
        if (i >= tile_directions.len) {
            return null;
        }
        return tile_directions[i];
    }

    // checks if the tile contains the direction
    fn hasDirection(self: Tile, dir: Direction) bool {
        if (self.directions()) |dirs| {
            return dir == dirs.@"0" or dir == dirs.@"1";
        }
        return false;
    }

    // checks which tile shapes match with one another
    fn matches(self: Tile, other: Tile) bool {
        if (other == .start) return self != .ground;
        return switch (self) {
            .northSouth => other.hasDirection(.north) or other.hasDirection(.south),
            .eastWest => other.hasDirection(.east) or other.hasDirection(.west),
            .northEast => other.hasDirection(.south) or other.hasDirection(.west),
            .northWest => other.hasDirection(.south) or other.hasDirection(.east),
            .southWest => other.hasDirection(.north) or other.hasDirection(.east),
            .southEast => other.hasDirection(.north) or other.hasDirection(.west),
            .start => other != .ground,
            else => false,
        };
    }

    // returns the exit direction that doesn't match the direction used to enter the tile
    fn exitDirection(self: Tile, from: Direction) !?Direction {
        if (self.directions()) |dirs| {
            return if (from == dirs[0]) dirs[1] else if (from == dirs[1]) dirs[0] else MazeError.tileDirectionMismatch;
        }
        return null;
    }
};

const Coord = struct {
    x: usize,
    y: usize,

    inline fn eql(lhs: Coord, rhs: Coord) bool {
        return lhs.x == rhs.x and lhs.y == rhs.y;
    }
};

const CoordContext = struct {
    width: usize,
    const Self = @This();

    pub fn hash(ctx: Self, key: Coord) u64 {
        // using a simple hash based on the coordinate indexes
        // so that we have a nice distributivity and cheap hash
        const h: u64 = @bitCast(key.y * ctx.width + key.x);
        return h;
    }

    pub fn eql(ctx: Self, lhs: Coord, rhs: Coord) bool {
        _ = ctx;
        return lhs.eql(rhs);
    }
};

const CoordSet = std.HashMap(Coord, void, CoordContext, std.hash_map.default_max_load_percentage);

const Loop = struct {
    len: usize = 0,
    coords: ?CoordSet = null,
    start_tile: Tile = Tile.start,

    fn deinit(self: *Loop) void {
        if (self.coords) |*coords| {
            coords.deinit();
        }
        self.* = undefined;
    }
};

const Maze = struct {
    allocator: std.mem.Allocator,
    data: []Tile,
    tiles: [][]Tile,
    start: Coord,
    width: usize,
    height: usize,

    const Self = @This();
    const navigable_tiles = [_]Tile{ .northSouth, .eastWest, .northEast, .northWest, .southWest, .southEast };

    const Target = struct {
        coord: Coord,
        tile: Tile,
        exitDirection: Direction,
    };

    fn init(allocator: std.mem.Allocator, s: []const u8) !Self {
        const w = std.mem.indexOfScalar(u8, s, '\n').?;
        const h = s.len / (w + 1);
        // print("w: {d} h: {d}\n", .{ w, h });

        var data = try allocator.alloc(Tile, w * h);
        var tiles = try allocator.alloc([]Tile, h);
        var start: Coord = undefined;

        var slide: usize = 0;
        for (s) |c| {
            if (c == '\n') {
                tiles[slide / w - 1] = data[slide - w .. slide];
                continue;
            }
            if (c == 'S') {
                start = .{ .x = slide % w, .y = slide / w };
            }
            data[slide] = Tile.fromChar(c);
            slide += 1;
        }

        return .{
            .allocator = allocator,
            .data = data,
            .tiles = tiles,
            .start = start,
            .width = w,
            .height = h,
        };
    }

    fn deinit(self: *@This()) void {
        self.allocator.free(self.tiles);
        self.allocator.free(self.data);
    }

    fn farthestPointDistance(self: *Self) usize {
        var main_loop = self.findLongestLoop() catch return 0;
        defer main_loop.deinit();
        return std.math.divCeil(usize, main_loop.len, 2) catch 0;
    }

    fn countEnclosedTiles(self: *Self) !usize {
        var main_loop = try self.findLongestLoop();
        defer main_loop.deinit();
        self.cleanUpOtherPipes(main_loop);

        // breaking down the problem:
        // we visit every tile, top to bottom, left to right
        // at the beginning or end of each row we assume that any tile is not enclosed
        // because the animal cannot squeeze between these tiles and the borders of the maze...
        // so we need to look for tiles that are blocking from the north, in that row...
        // if the tile has an exit to the north, we know that it's connected to another tile
        // in the row counted before. Every time we see one, we flip the enclosed flag
        // and if we find a ground tile while the it's supposed to be enclosed,
        // then we count that ground tile as an enclosed one...
        var count: usize = 0;
        var enclosed = false;
        for (self.data, 0..) |tile, i| {
            const mod = i % self.width;
            if (mod == 0 or mod == self.width - 1) enclosed = false;
            switch (tile) {
                .ground => {
                    if (enclosed) count += 1;
                },
                .northSouth, .northEast, .northWest => {
                    enclosed = !enclosed;
                },
                else => {},
            }
        }
        return count;
    }

    fn cleanUpOtherPipes(self: *Self, main_loop: Loop) void {
        // change the start title to its correct tile shape
        self.tiles[self.start.y][self.start.x] = main_loop.start_tile;
        const coords = main_loop.coords.?;

        // all tiles that don't belong to the main loop are changed to ground tiles
        for (self.data, 0..) |*tile, i| {
            const x = i % self.width;
            const y = i / self.width;
            if (tile.* == .ground or coords.contains(.{ .x = x, .y = y })) continue;
            tile.* = .ground;
        }
    }

    fn findLongestLoop(self: *Self) !Loop {
        var main_loop = Loop{};
        errdefer main_loop.deinit();

        // we need to assume any navigable tile shape of the starting tile
        // to make sure there actually is a loop
        inline for (navigable_tiles) |assumed_start_tile| {
            // print("==== {} ====\n", .{assumed_start_tile});
            var set = CoordSet.initContext(self.allocator, .{ .width = self.width });
            errdefer set.deinit();

            try set.put(self.start, {});
            var count: usize = 0;
            var target = Target{
                .coord = self.start,
                .tile = assumed_start_tile,
                .exitDirection = assumed_start_tile.directions().?.@"0",
            };

            const found = while (self.tryMove(target, assumed_start_tile)) |next| : (count += 1) {
                // if we've reached the start tile, we check if this loop is the longest
                if (next.coord.eql(self.start)) {
                    if (count > main_loop.len) {
                        // another loop was found before and needs to be cleaned up
                        if (main_loop.coords) |*coords| {
                            coords.deinit();
                        }
                        main_loop.len = count;
                        main_loop.coords = set;
                        main_loop.start_tile = assumed_start_tile;
                        break true;
                    }
                    break false; // we found a loop, but it's not the longest
                }
                try set.put(next.coord, {});
                target = next;
            } else false;

            // ensure that the set of coordinates is freed
            // this only happens if it's not the longest loop found so far
            if (!found) {
                // print("> cleaning up...\n", .{});
                set.deinit();
            }
        }
        return main_loop;
    }

    fn tryMove(self: *Self, target: Target, startTile: Tile) ?Target {
        // check if it's possible to move east or west
        const x = switch (target.exitDirection) {
            .west => if (target.coord.x > 0) target.coord.x - 1 else return null,
            .east => if (target.coord.x < self.width - 1) target.coord.x + 1 else return null,
            else => target.coord.x,
        };

        // check if it's possible to move north or south
        const y = switch (target.exitDirection) {
            .north => if (target.coord.y > 0) target.coord.y - 1 else return null,
            .south => if (target.coord.y < self.height - 1) target.coord.y + 1 else return null,
            else => target.coord.y,
        };

        // if it's moving to the starting tile, then we need to use the same shape that we started with
        const tile = if (x == self.start.x and y == self.start.y) startTile else self.tiles[y][x];

        // if the tiles don't match, it hit a dead end
        if (!target.tile.matches(tile)) return null;

        const opposingDirection = target.exitDirection.opposingDirection();
        const nextExitDirection = tile.exitDirection(opposingDirection) catch {
            // hit a dead end
            return null;
        };

        // returns the coordinate and the tile it has moved to and also
        // the next exit direction to continue searching
        return .{
            .coord = .{ .x = x, .y = y },
            .tile = tile,
            .exitDirection = nextExitDirection.?,
        };
    }
};

// unused
fn printRow(tiles: []Tile) void {
    for (tiles) |tile| {
        print("{c}", .{tile.toChar()});
    }
    print("\n", .{});
}

test "example1 - part 1" {
    var logging_allocator = std.heap.loggingAllocator(std.testing.allocator);
    const allocator = logging_allocator.allocator();
    var maze = try Maze.init(allocator, example1);
    defer maze.deinit();

    const result = maze.farthestPointDistance();
    try std.testing.expectEqual(4, result);
}

test "example2 - part 1" {
    var maze = try Maze.init(std.testing.allocator, example2);
    defer maze.deinit();

    const result = maze.farthestPointDistance();
    try std.testing.expectEqual(4, result);
}

test "example3 - part 1" {
    var maze = try Maze.init(std.testing.allocator, example3);
    defer maze.deinit();

    const result = maze.farthestPointDistance();
    try std.testing.expectEqual(8, result);
}

test "example with two loops - part 1" {
    var maze = try Maze.init(std.testing.allocator, example_two_loops);
    defer maze.deinit();

    const result = maze.farthestPointDistance();
    try std.testing.expectEqual(9, result);
}

test "input - part 1" {
    var maze = try Maze.init(std.testing.allocator, input);
    defer maze.deinit();

    const result = maze.farthestPointDistance();
    try std.testing.expectEqual(6890, result);
}

test "example4 - part 2" {
    var maze = try Maze.init(std.testing.allocator, example4);
    defer maze.deinit();

    const result = try maze.countEnclosedTiles();
    try std.testing.expectEqual(4, result);
}

test "example squeeze - part 2" {
    var maze = try Maze.init(std.testing.allocator, example_squeeze);
    defer maze.deinit();

    const result = try maze.countEnclosedTiles();
    try std.testing.expectEqual(4, result);
}

test "example5 - part 2" {
    var maze = try Maze.init(std.testing.allocator, example5);
    defer maze.deinit();

    const result = try maze.countEnclosedTiles();
    try std.testing.expectEqual(8, result);
}

test "example6 - part 2" {
    var maze = try Maze.init(std.testing.allocator, example6);
    defer maze.deinit();

    const result = try maze.countEnclosedTiles();
    try std.testing.expectEqual(10, result);
}

test "input - part 2" {
    var maze = try Maze.init(std.testing.allocator, input);
    defer maze.deinit();

    const result = try maze.countEnclosedTiles();
    try std.testing.expectEqual(453, result);
}
