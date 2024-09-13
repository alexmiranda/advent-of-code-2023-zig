const std = @import("std");
const mem = std.mem;
const math = std.math;
const Order = std.math.Order;
const testing = std.testing;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;
const print = std.debug.print;
const example = @embedFile("example.txt");
const example2 = @embedFile("example2.txt");
const input = @embedFile("input.txt");

const CityBlock = u8;

const Direction = enum {
    up,
    right,
    down,
    left,

    inline fn opposite(self: Direction) Direction {
        return switch (self) {
            .up => .down,
            .right => .left,
            .down => .up,
            .left => .right,
        };
    }
};

const BlockAddress = struct {
    row: u8,
    col: u8,

    fn moveTo(self: BlockAddress, dir: Direction, offset: u8, grid_height: u8, grid_width: u8) ?BlockAddress {
        const last_row_index = grid_height - 1;
        const last_col_index = grid_width - 1;
        return switch (dir) {
            .up => if (self.row >= offset) .{ .row = self.row - offset, .col = self.col } else null,
            .right => if (self.col <= last_col_index - offset) .{ .row = self.row, .col = self.col + offset } else null,
            .down => if (self.row <= last_row_index - offset) .{ .row = self.row + offset, .col = self.col } else null,
            .left => if (self.col >= offset) .{ .row = self.row, .col = self.col - offset } else null,
        };
    }
};

const Edge = struct {
    addr: BlockAddress,
    dir: Direction,
    count: u8,
};

const State = struct {
    edge: Edge,
    heat_lost: u32,
    heuristic: u16 = 0,
};

fn lessThan(ctx: void, lhs: State, rhs: State) Order {
    _ = ctx;
    // return math.order(lhs.heat_lost, rhs.heat_lost);
    return switch (math.order(lhs.heat_lost, rhs.heat_lost)) {
        .eq => math.order(lhs.heuristic, rhs.heuristic),
        else => |cmp| cmp,
    };
}

const PriorityQueue = std.PriorityQueue(State, void, lessThan);

const EdgeContext = struct {
    pub fn hash(ctx: @This(), edge: Edge) u64 {
        _ = ctx;
        var hasher = std.hash.Fnv1a_64.init();
        hasher.update(&mem.toBytes(edge.addr.row));
        hasher.update(&mem.toBytes(edge.addr.col));
        hasher.update(&mem.toBytes(@intFromEnum(edge.dir)));
        hasher.update(&mem.toBytes(edge.count));
        return hasher.final();
    }

    pub fn eql(ctx: @This(), lhs: Edge, rhs: Edge) bool {
        _ = ctx;
        return lhs.addr.row == rhs.addr.row and
            lhs.addr.col == rhs.addr.col and
            lhs.dir == rhs.dir and
            lhs.count == rhs.count;
    }
};

const HeatLossMap = std.HashMap(Edge, u32, EdgeContext, std.hash_map.default_max_load_percentage);

fn CityMap(buffer: []const u8) type {
    const width = comptime mem.indexOfScalar(u8, buffer, '\n').?;
    const height = blk: {
        @setEvalBranchQuota(buffer.len + 1000);
        break :blk comptime mem.count(u8, buffer, "\n");
    };

    return struct {
        const blocks = blk: {
            @setEvalBranchQuota(buffer.len + 1000);
            var data: [height][width]CityBlock = undefined;
            var slide: u16 = 0;
            for (buffer) |c| {
                if (c == '\n') continue;
                data[slide / width][slide % width] = c - '0';
                slide += 1;
            }
            break :blk data;
        };

        const Self = @This();

        fn moveCrucible(self: *Self, allocator: mem.Allocator, min: u8, max: u8) !u32 {
            _ = self;
            std.debug.assert(min < max);
            const start_at = BlockAddress{ .row = 0, .col = 0 };
            const goal = BlockAddress{ .row = height - 1, .col = width - 1 };
            const inf = math.maxInt(u16);

            // queue to keep track of blocks to visit
            var queue = PriorityQueue.init(allocator, {});
            defer queue.deinit();

            // start at the lava pool towards the right edge
            const rightEdge = Edge{ .addr = start_at, .dir = .right, .count = 0 };
            try queue.add(.{ .edge = rightEdge, .heat_lost = 0, .heuristic = inf });

            // or towards the bottom edge
            const downEdge = Edge{ .addr = start_at, .dir = .down, .count = 0 };
            try queue.add(.{ .edge = downEdge, .heat_lost = 0, .heuristic = inf });

            // map to keep track of edges that we visited and the best way to reach them
            var visited = HeatLossMap.init(allocator);
            defer visited.deinit();
            try visited.ensureUnusedCapacity(2);
            visited.putAssumeCapacity(rightEdge, 0);
            visited.putAssumeCapacity(downEdge, 0);

            const directions = [_]Direction{ .up, .right, .down, .left };
            return while (queue.removeOrNull()) |state| {
                assert(state.edge.count <= max);
                const addr = state.edge.addr;
                const curr_dir = state.edge.dir;
                const curr_count = state.edge.count;

                // we've reached the goal
                if (addr.row == goal.row and addr.col == goal.col) {
                    break state.heat_lost;
                }

                for (directions) |dir| {
                    // cannot move to opposite direction or
                    // more than the maximum in the same direction or
                    // in another direction before the minimum
                    if (dir == curr_dir.opposite() or
                        (dir == curr_dir and curr_count == max) or
                        (dir != curr_dir and curr_count < min))
                    {
                        continue;
                    }

                    // determine the next block to visit and the possible amount of heat lost
                    const step = if ((dir == curr_dir and curr_count == 0) or dir != curr_dir) min else 1;
                    const next_addr = addr.moveTo(dir, step, height, width) orelse continue;
                    const cost = calculateCostBetween(addr, next_addr);
                    assert(cost >= 1 and cost <= step * 9);
                    const tentative_heat_lost = state.heat_lost + cost;
                    const count = if (dir == curr_dir) curr_count + step else min;

                    // if we didn't visit this edge before or if we found a better way there
                    const edge = Edge{ .addr = next_addr, .dir = dir, .count = count };
                    const lookup = try visited.getOrPut(edge);
                    if (!lookup.found_existing or tentative_heat_lost < lookup.value_ptr.*) {
                        // update the edge heat lost
                        lookup.value_ptr.* = tentative_heat_lost;

                        // and plan more routes to explore the rest of the city blocks
                        try queue.add(.{
                            .edge = edge,
                            .heat_lost = tentative_heat_lost,
                            .heuristic = manhattan(next_addr, goal),
                        });
                    }
                }
            } else @panic("cannot find a path to reach the goal");
        }

        fn manhattan(a: BlockAddress, b: BlockAddress) u16 {
            const a_row: i16 = @intCast(a.row);
            const a_col: i16 = @intCast(a.col);
            const b_row: i16 = @intCast(b.row);
            const b_col: i16 = @intCast(b.col);
            return @abs(a_row - b_row) + @abs(a_col - b_col);
        }

        // calculate the heat loss between the source and destination blocks, inclusive
        // and then subtract the source
        fn calculateCostBetween(src: BlockAddress, dst: BlockAddress) u16 {
            // print("calculating cost betweenn {any} and {any}\n", .{ src, dst });
            var sum: u16 = 0;
            if (src.row == dst.row) {
                const start = @min(src.col, dst.col);
                const end = @max(src.col, dst.col);
                for (start..end + 1) |col| sum += blocks[src.row][col];
                return sum - blocks[src.row][src.col];
            } else if (src.col == dst.col) {
                const start = @min(src.row, dst.row);
                const end = @max(src.row, dst.row);
                for (start..end + 1) |row| sum += blocks[row][src.col];
                return sum - blocks[src.row][src.col];
            }
            @panic("either the row or the col must match!");
        }
    };
}

test "example - part 1" {
    var city_map = CityMap(example){};
    const result = try city_map.moveCrucible(testing.allocator, 1, 3);
    try expectEqual(102, result);
}

test "input - part 1" {
    var city_map = CityMap(input){};
    const result = try city_map.moveCrucible(testing.allocator, 1, 3);
    try expectEqual(684, result);
}

test "example - part 2" {
    var city_map = CityMap(example){};
    const result = try city_map.moveCrucible(testing.allocator, 4, 10);
    try expectEqual(94, result);
}

test "example 2 - part 2" {
    var city_map = CityMap(example2){};
    const result = try city_map.moveCrucible(testing.allocator, 4, 10);
    try expectEqual(71, result);
}

test "input - part 2" {
    var city_map = CityMap(input){};
    const result = try city_map.moveCrucible(testing.allocator, 4, 10);
    try expectEqual(822, result);
}
