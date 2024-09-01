const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const print = std.debug.print;
// const absCast = std.math.absCast;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Location = struct {
    x: isize,
    y: isize,
};

const Tile = union(enum) {
    galaxy: struct { index: usize },
    empty_space: struct { weight_x: usize = 1, weight_y: usize = 1 },
};

fn Universe(comptime observable_size: usize) type {
    return struct {
        grid: [observable_size][observable_size]Tile,
        count_galaxies: usize = 0,

        const Self = @This();

        fn init(s: []const u8) !Self {
            var universe = Self{ .grid = undefined };
            var slide: usize = 0;

            // parse the input
            for (s) |c| {
                if (c == '\n') continue;
                const row = slide / observable_size;
                const col = slide % observable_size;
                universe.grid[row][col] = switch (c) {
                    '.' => .{ .empty_space = .{} },
                    '#' => .{ .galaxy = .{ .index = universe.count_galaxies } },
                    else => unreachable,
                };
                if (c == '#') universe.count_galaxies += 1;
                slide += 1;
            }
            return universe;
        }

        // sum up the total distances between all galaxy combinations
        fn totalDistanceBetweenGalaxies(self: *Self, allocator: mem.Allocator) !u64 {
            const galaxies = try self.findGalaxies(allocator);
            defer allocator.free(galaxies);

            // for each combination, add the distance between them
            var total_distance: u64 = 0;
            for (0..galaxies.len - 1) |i| {
                for (i..galaxies.len) |j| {
                    const a = galaxies[i];
                    const b = galaxies[j];
                    total_distance += manhattanDistance(a, b);
                }
            }
            return total_distance;
        }

        fn manhattanDistance(a: Location, b: Location) u64 {
            const delta_x: u64 = absCast(a.x - b.x);
            const delta_y: u64 = absCast(a.y - b.y);
            return delta_x + delta_y;
        }

        // determines the actual location of each galaxy
        fn findGalaxies(self: *Self, allocator: mem.Allocator) ![]Location {
            const galaxies = try allocator.alloc(Location, self.count_galaxies);
            errdefer allocator.free(galaxies);

            // iterate from left to right in each row and compute
            // the actual x location of each galaxy
            for (0..observable_size) |row| {
                var actual_col: isize = 0;
                for (0..observable_size) |col| {
                    switch (self.grid[row][col]) {
                        .empty_space => |tile| {
                            actual_col += @intCast(tile.weight_x);
                        },
                        .galaxy => |tile| {
                            actual_col += 1;
                            galaxies[tile.index].x = actual_col;
                        },
                    }
                }
            }

            // iterate from top to bottom in each column and compute
            // the actual y location of each galaxy
            for (0..observable_size) |col| {
                var actual_row: isize = 0;
                for (0..observable_size) |row| {
                    switch (self.grid[row][col]) {
                        .empty_space => |tile| {
                            actual_row += @intCast(tile.weight_y);
                        },
                        .galaxy => |tile| {
                            actual_row += 1;
                            galaxies[tile.index].y = actual_row;
                        },
                    }
                }
            }

            return galaxies;
        }

        // expand will update each empty space tile with its corresponding
        // weight x and y.
        fn expand(self: *Self) void {
            // find empty space tiles in empty columns and update them
            for (0..observable_size) |col| {
                if (!self.isColEmpty(col)) continue;
                // print("> col {0} is empty\n", .{col});
                for (0..observable_size) |row| {
                    switch (self.grid[row][col]) {
                        .empty_space => |*tile| {
                            tile.weight_x += 1;
                        },
                        else => {},
                    }
                }
            }

            // find empty space tiles in empty rows and update them
            for (0..observable_size) |row| {
                if (!self.isRowEmpty(row)) continue;
                // print("> row {0} is empty\n", .{row});
                for (0..observable_size) |col| {
                    switch (self.grid[row][col]) {
                        .empty_space => |*tile| {
                            tile.weight_y += 1;
                        },
                        else => {},
                    }
                }
            }
        }

        // check if the column contains only empty space
        fn isColEmpty(self: *Self, col: usize) bool {
            for (0..observable_size) |row| {
                switch (self.grid[row][col]) {
                    .galaxy => return false,
                    else => continue,
                }
            }
            return true;
        }

        // check if the row contains only empty space
        fn isRowEmpty(self: *Self, row: usize) bool {
            for (0..observable_size) |col| {
                switch (self.grid[row][col]) {
                    .galaxy => return false,
                    else => continue,
                }
            }
            return true;
        }

        // unused
        fn display(self: *Self) void {
            for (0..observable_size) |row| {
                for (0..observable_size) |col| {
                    const tile = self.grid[row][col];
                    const c: u8 = switch (tile) {
                        .empty_space => '.',
                        .galaxy => '#',
                    };
                    print("{c}", .{c});
                }
                print("\n", .{});
            }
        }
    };
}

// HACK: I've literally had to copy this over from std lib because of the error:
// error: root struct of file 'math' has no member named 'absCast'
pub fn absCast(x: anytype) switch (@typeInfo(@TypeOf(x))) {
    .ComptimeInt => comptime_int,
    .Int => |int_info| std.meta.Int(.unsigned, int_info.bits),
    else => @compileError("absCast only accepts integers"),
} {
    switch (@typeInfo(@TypeOf(x))) {
        .ComptimeInt => {
            if (x < 0) {
                return -x;
            } else {
                return x;
            }
        },
        .Int => |int_info| {
            if (int_info.signedness == .unsigned) return x;
            const Uint = std.meta.Int(.unsigned, int_info.bits);
            if (x < 0) {
                return ~@as(Uint, @bitCast(x +% -1));
            } else {
                return @as(Uint, @intCast(x));
            }
        },
        else => unreachable,
    }
}

const ExampleUniverse = Universe(10);
const PuzzleUniverse = Universe(140);

test "example - part 1" {
    var logging_allocator = heap.loggingAllocator(testing.allocator);
    const allocator = logging_allocator.allocator();
    var universe = try ExampleUniverse.init(example);
    universe.expand();
    const result = try universe.totalDistanceBetweenGalaxies(allocator);
    try testing.expectEqual(374, result);
}

test "input - part 1" {
    var universe = try PuzzleUniverse.init(input);
    universe.expand();
    const result = try universe.totalDistanceBetweenGalaxies(testing.allocator);
    try testing.expectEqual(9795148, result);
}
