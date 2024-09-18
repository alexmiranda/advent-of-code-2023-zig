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

    fn reachablePlotsInfinite(self: *Farm, turns: u32) !u32 {
        const ally = self.ally;

        // keep track of the visited tiles
        var visited = std.AutoHashMap(Pos, void).init(ally);
        defer visited.deinit();

        // ensure we have enough capacity for at least one node
        // so we don't cause a double free (the head node created outside the loop)
        // if it fails inside of the loop
        try visited.ensureUnusedCapacity(1);

        const Q = std.TailQueue(Pos);
        var queue = Q{};

        // ensure we clean up the queue at the end
        defer while (queue.pop()) |item| ally.destroy(item);

        var node = try ally.create(Q.Node);
        node.data = self.start_pos;

        var buf: [4]Pos = undefined;
        queue.append(node);
        for (0..turns) |_| {
            visited.clearRetainingCapacity();
            try visited.put(self.start_pos, {});
            for (0..queue.len) |_| {
                node = queue.popFirst().?;
                defer ally.destroy(node);

                const next_positions = self.neighboursInfinite(node.data, &buf);
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
    var farm = try Farm.initParse(testing.allocator, example);
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
