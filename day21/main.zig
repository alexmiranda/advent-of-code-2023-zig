const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const testing = std.testing;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Tile = enum {
    starting_position,
    garden_plot,
    rocks,
};

const Pos = struct {
    row: usize,
    col: usize,
};

const Farm = struct {
    ally: mem.Allocator,
    data: []Tile,
    tiles: [][]Tile = undefined,
    start_pos: Pos,

    fn initParse(ally: mem.Allocator, comptime buffer: []const u8) !Farm {
        // determine the size of the grid (it's a square!)
        const size = comptime blk: {
            const a: i32 = 1;
            const b: i32 = 1;
            const c: i32 = @as(i16, @intCast(buffer.len)) * -1;
            const delta: u32 = @abs(b * b - (4 * a * c));
            break :blk @abs(@divFloor(-b + math.sqrt(delta), (2 * a)));
        };

        // data holds a continguous list of all tiles
        var data = try ally.alloc(Tile, size * size);
        errdefer ally.free(data);

        // for convenience tiles contains slices into the data itself
        var tiles: [][]Tile = try ally.alloc([]Tile, size);
        errdefer ally.free(tiles);

        var start_pos: Pos = undefined;
        var slide: usize = 0;
        for (buffer) |c| {
            switch (c) {
                '.' => data[slide] = .garden_plot,
                '#' => data[slide] = .rocks,
                'S' => {
                    data[slide] = .starting_position;
                    start_pos = .{ .row = slide / size, .col = slide % size };
                },
                '\n' => {
                    tiles[slide / size - 1] = data[slide - size .. slide];
                    continue;
                },
                else => unreachable,
            }
            slide += 1;
        }

        // print("start_pos: {any}\n", .{start_pos});
        return Farm{ .ally = ally, .data = data, .tiles = tiles, .start_pos = start_pos };
    }

    fn deinit(self: Farm) void {
        self.ally.free(self.tiles);
        self.ally.free(self.data);
    }

    fn reachablePlots(self: *Farm, turns: u8) !u32 {
        var arena = heap.ArenaAllocator.init(self.ally);
        defer arena.deinit();
        const ally = arena.allocator();

        var visited = std.AutoHashMap(Pos, void).init(ally);
        defer visited.deinit();

        const Q = std.TailQueue(Pos);
        var queue = Q{};
        var node = try ally.create(Q.Node);
        // this could cause a double free
        // errdefer ally.destroy(node);
        node.data = self.start_pos;

        var buf: [4]Pos = undefined;
        queue.append(node);

        // ensure we clean up the queue at the end
        defer while (queue.pop()) |item| ally.destroy(item);

        for (0..turns) |_| {
            visited.clearRetainingCapacity();
            try visited.put(self.start_pos, {});
            for (0..queue.len) |_| {
                node = queue.popFirst().?;
                defer ally.destroy(node);

                const next_positions = self.neighbours(node.data, &buf);
                for (next_positions) |pos| {
                    const gop = try visited.getOrPut(pos);
                    if (!gop.found_existing) {
                        const new_node = try ally.create(Q.Node);
                        errdefer ally.destroy(new_node);
                        new_node.data = pos;
                        queue.append(new_node);
                    }
                }
            }
        }

        // self.dumpVisited(&visited);
        return visited.count();
    }

    fn neighbours(self: *Farm, pos: Pos, buf: []Pos) []Pos {
        // print("neighbours of {any}: ", .{pos});
        var slide: usize = 0;
        if (pos.row > 0 and self.tiles[pos.row - 1][pos.col] == .garden_plot) {
            buf[slide] = .{ .row = pos.row - 1, .col = pos.col };
            slide += 1;
        }
        if (pos.col < self.tiles[pos.row].len - 1 and self.tiles[pos.row][pos.col + 1] == .garden_plot) {
            buf[slide] = .{ .row = pos.row, .col = pos.col + 1 };
            slide += 1;
        }
        if (pos.row < self.tiles.len - 1 and self.tiles[pos.row + 1][pos.col] == .garden_plot) {
            buf[slide] = .{ .row = pos.row + 1, .col = pos.col };
            slide += 1;
        }
        if (pos.col > 0 and self.tiles[pos.row][pos.col - 1] == .garden_plot) {
            buf[slide] = .{ .row = pos.row, .col = pos.col - 1 };
            slide += 1;
        }
        // print("{any} (total={d})\n", .{ buf[0..slide], slide });
        return buf[0..slide];
    }

    fn dump(self: Farm) void {
        for (0..self.tiles.len) |row| {
            for (0..self.tiles[row].len) |col| {
                const c: u8 = switch (self.tiles[row][col]) {
                    .garden_plot => '.',
                    .rocks => '#',
                    .starting_position => 'S',
                };
                print("{c}", .{c});
            }
            print("\n", .{});
        }
    }

    fn dumpVisited(self: Farm, visited: *std.AutoHashMap(Pos, void)) void {
        for (0..self.tiles.len) |row| {
            for (0..self.tiles[row].len) |col| {
                const c: u8 = switch (self.tiles[row][col]) {
                    .garden_plot => if (visited.contains(.{ .row = row, .col = col })) 'O' else '.',
                    .rocks => '#',
                    .starting_position => 'O',
                };
                print("{c}", .{c});
            }
            print("\n", .{});
        }
    }
};

test "example - part 1" {
    var farm = try Farm.initParse(testing.allocator, example);
    defer farm.deinit();
    const reachable = try farm.reachablePlots(6);
    try expectEqual(16, reachable);
}

test "input - part 1" {
    var farm = try Farm.initParse(testing.allocator, input);
    defer farm.deinit();
    const reachable = try farm.reachablePlots(64);
    try expectEqual(3737, reachable);
}
