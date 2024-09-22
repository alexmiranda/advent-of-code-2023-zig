const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const testing = std.testing;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Tile = enum {
    garden_plot,
    rocks,
};

const Pos = struct {
    row: i64,
    col: i64,
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
                    data[slide] = .garden_plot;
                    const row: i64 = @intCast(slide / size);
                    const col: i64 = @intCast(slide % size);
                    start_pos = .{ .row = row, .col = col };
                },
                '\n' => {
                    tiles[slide / size - 1] = data[slide - size .. slide];
                    continue;
                },
                else => unreachable,
            }
            slide += 1;
        }

        return Farm{ .ally = ally, .data = data, .tiles = tiles, .start_pos = start_pos };
    }

    fn deinit(self: Farm) void {
        self.ally.free(self.tiles);
        self.ally.free(self.data);
    }

    fn reachablePlots(self: *Farm, turns: u8) !u32 {
        const ally = self.ally;

        // keep track of the visited tiles
        var visited = std.AutoHashMap(Pos, void).init(ally);
        defer visited.deinit();

        // ensure we have enough capacity for at least one node
        // so we don't cause a double free if it fails inside of the loop
        try visited.ensureUnusedCapacity(1);

        const Q = std.TailQueue(Pos);
        var queue = Q{};
        // ensure we clean up the queue at the end
        defer while (queue.pop()) |item| ally.destroy(item);

        var node = try ally.create(Q.Node);
        // we already ensure that every node will be destroyed before exiting
        // errdefer ally.destroy(node);
        node.data = self.start_pos;

        var buf: [4]Pos = undefined;
        queue.append(node);
        for (0..turns) |_| {
            visited.clearRetainingCapacity();
            visited.putAssumeCapacity(self.start_pos, {});
            // we pop the first items that are already in the queue
            // leaving the ones being added by each iteration untouched
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

        return visited.count();
    }

    fn reachablePlotsInfinite(self: *Farm, turns: u32) !u64 {
        // HACK: brute force if working with the example data
        const brute_force = self.data.len <= example.len;

        // validate assumptions
        if (!brute_force) self.checkAssumptions(turns);

        const size: u32 = @intCast(self.tiles.len);
        const Set = std.AutoHashMap(Pos, void);
        var visited = Set.init(self.ally);
        defer visited.deinit();
        try visited.put(self.start_pos, {});

        var next_visited = Set.init(self.ally);
        defer next_visited.deinit();

        var counts: [3]i64 = undefined;
        var deltas = [_]i64{0} ** counts.len;
        var buf: [4]Pos = undefined;
        var slide: usize = 0;
        const rem = turns % size;
        for (1..turns + 1) |i| {
            if (slide == counts.len) break;
            next_visited.clearRetainingCapacity();
            var it = visited.keyIterator();
            while (it.next()) |pos| {
                const adjacent_positions = self.neighboursInfinite(pos.*, &buf);
                for (adjacent_positions) |next_pos| try next_visited.put(next_pos, {});
            }

            if (!brute_force and i >= rem and (i - rem) % size == 0) {
                const count: i64 = @intCast(next_visited.count());
                counts[slide] = count;
                const delta = count - counts[slide -| 1];
                deltas[slide] = delta;
                slide += 1;
                // print("i={d} counts={d} deltas={d} 2nd differential: {d}\n", .{ i, counts[0..slide], deltas[1..slide], deltas[slide - 1] - deltas[slide -| 2] });
            }

            mem.swap(Set, &visited, &next_visited);
        } else return visited.count();

        // print("counts: {d}\n", .{counts});
        // print("deltas: {d}\n", .{deltas});
        const a = @divFloor(deltas[2] - deltas[1], 2);
        const b = deltas[1] - 3 * a;
        const c = counts[0] - a - b;
        const n: i64 = @intCast(1 + turns / size);
        return @abs(a * n * n + b * n + c);
    }

    fn neighbours(self: *Farm, pos: Pos, buf: []Pos) []Pos {
        var slide: usize = 0;
        const row: u16 = @intCast(pos.row);
        const col: u16 = @intCast(pos.col);
        if (row > 0 and self.tiles[row - 1][col] == .garden_plot) {
            buf[slide] = .{ .row = row - 1, .col = col };
            slide += 1;
        }
        if (col < self.tiles[row].len - 1 and self.tiles[row][col + 1] == .garden_plot) {
            buf[slide] = .{ .row = row, .col = col + 1 };
            slide += 1;
        }
        if (row < self.tiles.len - 1 and self.tiles[row + 1][col] == .garden_plot) {
            buf[slide] = .{ .row = row + 1, .col = col };
            slide += 1;
        }
        if (col > 0 and self.tiles[row][col - 1] == .garden_plot) {
            buf[slide] = .{ .row = row, .col = col - 1 };
            slide += 1;
        }
        return buf[0..slide];
    }

    fn neighboursInfinite(self: *Farm, pos: Pos, buf: []Pos) []Pos {
        // calculate the neighbours positions all at once (if SIMD is available)
        const vec_curr_pos: @Vector(8, i64) = [_]i64{ pos.row, pos.col } ** 4;
        const vec_delta: @Vector(8, i64) = [_]i64{ -1, 0, 0, 1, 1, 0, 0, -1 };
        const positions = @as([8]i64, vec_curr_pos + vec_delta);

        var slide: usize = 0;
        var pairs = mem.window(i64, &positions, 2, 2);
        while (pairs.next()) |pair| {
            const size: i64 = @intCast(self.tiles.len);
            const actual_row: u16 = @intCast(@mod(pair[0], size));
            const actual_col: u16 = @intCast(@mod(pair[1], size));
            if (self.tiles[actual_row][actual_col] == .garden_plot) {
                buf[slide] = .{ .row = pair[0], .col = pair[1] };
                slide += 1;
            }
        }
        return buf[0..slide];
    }

    fn checkAssumptions(self: *Farm, turns: u32) void {
        const size: u32 = @intCast(self.tiles.len);
        const start_pos = self.start_pos;
        const dist_to_edge = size - @as(usize, @intCast(start_pos.col));
        const row: usize = @intCast(start_pos.row);
        const col: usize = @intCast(start_pos.col);

        // grid is a square of odd size and the starting position is at the perfect centre
        assert(row == col);
        assert(size % 2 == 1);
        assert(col % 2 == 1);
        assert(turns % size == dist_to_edge - 1);
        for (1..dist_to_edge) |i| {
            // only garden plots in the middle column
            assert(self.tiles[row - i][col] == .garden_plot);
            assert(self.tiles[row + i][col] == .garden_plot);

            // only garden in the middle row
            assert(self.tiles[row][col - i] == .garden_plot);
            assert(self.tiles[row][col + i] == .garden_plot);

            // only garden plots in the top edge
            assert(self.tiles[0][i] == .garden_plot);
            assert(self.tiles[0][size - i - 1] == .garden_plot);

            // only garden plots in the right edge
            assert(self.tiles[row - i][size - 1] == .garden_plot);
            assert(self.tiles[row + i][size - 1] == .garden_plot);

            // only garden plots in the bottom edge
            assert(self.tiles[size - 1][col - i] == .garden_plot);
            assert(self.tiles[size - 1][col + i] == .garden_plot);

            // only garden plots in the left edge
            assert(self.tiles[row - i][0] == .garden_plot);
            assert(self.tiles[row + i][0] == .garden_plot);
        }
    }

    // unused
    fn dump(self: Farm) void {
        for (0..self.tiles.len) |row| {
            for (0..self.tiles[row].len) |col| {
                const c: u8 = switch (self.tiles[row][col]) {
                    .garden_plot => '.',
                    .rocks => '#',
                };
                print("{c}", .{c});
            }
            print("\n", .{});
        }
    }

    // unused
    fn dumpVisited(self: Farm, visited: *std.AutoHashMap(Pos, void)) void {
        for (0..self.tiles.len) |row| {
            for (0..self.tiles[row].len) |col| {
                const c: u8 = switch (self.tiles[row][col]) {
                    .garden_plot => if (visited.contains(.{ .row = row, .col = col })) 'O' else '.',
                    .rocks => '#',
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

test "example - part 2" {
    var logging_ally = heap.LoggingAllocator(.debug, .debug).init(testing.allocator);
    const ally = logging_ally.allocator();

    var farm = try Farm.initParse(ally, example);
    defer farm.deinit();

    {
        const reachable = try farm.reachablePlotsInfinite(6);
        try expectEqual(16, reachable);
    }

    {
        const reachable = try farm.reachablePlotsInfinite(10);
        try expectEqual(50, reachable);
    }

    {
        const reachable = try farm.reachablePlotsInfinite(50);
        try expectEqual(1594, reachable);
    }

    {
        const reachable = try farm.reachablePlotsInfinite(100);
        try expectEqual(6536, reachable);
    }

    // the below examples are too slow to complete

    // {
    //     const reachable = try farm.reachablePlotsInfinite(500);
    //     try expectEqual(167004, reachable);
    // }

    // {
    //     const reachable = try farm.reachablePlotsInfinite(1000);
    //     try expectEqual(668697, reachable);
    // }

    // {
    //     const reachable = try farm.reachablePlotsInfinite(5000);
    //     try expectEqual(16733044, reachable);
    // }
}

test "input - part 2" {
    var logging_ally = heap.LoggingAllocator(.debug, .debug).init(testing.allocator);
    const ally = logging_ally.allocator();
    var farm = try Farm.initParse(ally, input);
    defer farm.deinit();
    assert(farm.tiles.len == 131);
    const reachable = try farm.reachablePlotsInfinite(26_501_365);
    try expectEqual(625382480005896, reachable);
}
