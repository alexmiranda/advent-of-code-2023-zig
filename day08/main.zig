const std = @import("std");
const print = std.debug.print;
const example1 = @embedFile("example1.txt");
const example2 = @embedFile("example2.txt");
const example3 = @embedFile("example3.txt");
const input = @embedFile("input.txt");

const Node = struct {
    left: []const u8,
    right: []const u8,
};

const Network = struct {
    allocator: std.mem.Allocator,
    instructions: []const u8,
    map: std.StringHashMap(Node),

    fn init(allocator: std.mem.Allocator, s: []const u8) !Network {
        var network: Network = undefined;
        var it = std.mem.tokenizeScalar(u8, s, '\n');
        network.allocator = allocator;
        network.instructions = it.next().?;
        network.map = std.StringHashMap(Node).init(allocator);
        while (it.next()) |line| {
            const key = line[0..3];
            const left = line[7..10];
            const right = line[12..15];
            const node = Node{ .left = left, .right = right };
            try network.map.put(key, node);
        }
        return network;
    }

    fn deinit(self: *Network) void {
        self.map.deinit();
    }

    fn navigate(self: *Network) u32 {
        const starting_point = "AAA";
        const end_point = "ZZZ";
        var slide: usize = 0;
        var curr: []const u8 = starting_point;
        var node = self.map.get(starting_point).?;
        var distance: u32 = 0;
        while (!std.mem.eql(u8, curr, end_point)) : (slide = (slide + 1) % self.instructions.len) {
            const turn = self.instructions[slide];
            curr = if (turn == 'L') node.left else node.right;
            node = self.map.get(curr).?;
            distance += 1;
        }
        return distance;
    }

    fn navigateMultiple(self: *Network) !u64 {
        // let's use an arena allocator so that we can free all of the memory at once
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const arena_allocator = arena.allocator();
        const Cycle = struct {
            distance_to_first: u64 = 0,
            cycle_length: ?usize = null,
        };

        const State = struct {
            start_at: []const u8,
            curr: []const u8,
            node: *Node,
            cycles: std.StringHashMap(Cycle),
        };

        const SeenKey = struct {
            pos: []const u8,
            slide: usize,
        };

        const SeenContext = struct {
            pub fn hash(ctx: @This(), key: SeenKey) u64 {
                _ = ctx;
                var h = std.hash.Fnv1a_64.init();
                h.update(key.pos);
                h.update(&std.mem.toBytes(key.slide));
                return h.final();
            }

            pub fn eql(ctx: @This(), lhs: SeenKey, rhs: SeenKey) bool {
                _ = ctx;
                return std.mem.eql(u8, lhs.pos, rhs.pos) and lhs.slide == rhs.slide;
            }
        };

        // collect all the ghosts and initialise its state
        const ghosts = blk: {
            var list = try std.ArrayList(State).initCapacity(arena_allocator, 6);
            defer list.deinit();

            var it = self.map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (key[2] == 'A') {
                    const cycles = std.StringHashMap(Cycle).init(arena_allocator);
                    list.appendAssumeCapacity(.{ .start_at = key, .curr = key, .node = entry.value_ptr, .cycles = cycles });
                }
            }
            break :blk try list.toOwnedSlice();
        };

        for (ghosts) |*ghost| {
            var distance: u64 = 0;
            var slide: usize = 0;
            var cycle_detected = false;
            var seen = std.HashMap(SeenKey, void, SeenContext, std.hash_map.default_max_load_percentage).init(arena_allocator);

            // detect cycles
            const found_cycle = while (true) : (slide = (slide + 1) % self.instructions.len) {
                const turn = self.instructions[slide];
                const curr = if (turn == 'L') ghost.node.left else ghost.node.right;
                ghost.curr = curr;
                ghost.node = self.map.getPtr(curr).?;
                distance += 1;

                // we have reached a target node
                if (ghost.curr[2] == 'Z') {
                    const seenKey = SeenKey{ .pos = curr, .slide = slide };
                    // if we've seen the same target node at the same instruction, we've identified a cycle
                    if (try seen.fetchPut(seenKey, {})) |_| {
                        const cycle = ghost.cycles.getPtr(curr).?;
                        cycle.cycle_length = distance - cycle.distance_to_first;
                        cycle_detected = true;
                        // print("CYCLE: start_at: {s} distance_to_first: {d} pos: {s} slide: {d} cycle_length: {d}\n", .{ ghost.start_at, cycle.distance_to_first, curr, slide, cycle.cycle_length.? });
                        break cycle;
                    } else {
                        // print("TARGET: start_at: {s} distance_to_first: {d} pos: {s} slide: {d}\n", .{ ghost.start_at, distance, curr, slide });
                        try ghost.cycles.put(curr, .{ .distance_to_first = distance });
                    }
                }
            };

            // based on the evidence of the data:
            // each ghost can only reach a single target (a node terminating with Z)
            // after that they cycle infinitely back to that same target position
            // hence we know that all 6 ghosts will eventually be at a _different_ target
            // because of that, the instruction that at which all the captured cycles are, are always the same
            // so there's no need to group them based on the last instructions they've seen
            // besides that, the distance to first reach a target is the same as the distance to repeat the cycle
            // which suggested the data was carefully planned to make this much simpler to solve
            // that being the case, we don't have to do anything else other than computing the number of
            // combined cycles until all of the ghost are at a final position
            // so we can discard the cycle found as we know that the hash map will only ever contain
            // a single entry.
            _ = found_cycle;
        }

        var result: u64 = 1;
        for (ghosts) |*ghost| {
            // we know that each ghost only has a single cycle with a determined length
            var it = ghost.cycles.valueIterator();
            const cycle = it.next().?;
            const cycle_length = cycle.cycle_length orelse 1;
            result = result * cycle_length / std.math.gcd(result, cycle_length);
        }

        return result;
    }
};

test "example 1 - part 1" {
    var network = try Network.init(std.testing.allocator, example1);
    defer network.deinit();

    try std.testing.expectEqual(2, network.navigate());
}

test "example 2 - part 1" {
    var network = try Network.init(std.testing.allocator, example2);
    defer network.deinit();

    try std.testing.expectEqual(6, network.navigate());
}

test "input - part 1" {
    var network = try Network.init(std.testing.allocator, input);
    defer network.deinit();

    try std.testing.expectEqual(16897, network.navigate());
}

test "example 3 - part 2" {
    var network = try Network.init(std.testing.allocator, example3);
    defer network.deinit();

    try std.testing.expectEqual(6, try network.navigateMultiple());
}

test "input - part 2" {
    var network = try Network.init(std.testing.allocator, input);
    defer network.deinit();

    try std.testing.expectEqual(16563603485021, try network.navigateMultiple());
}
