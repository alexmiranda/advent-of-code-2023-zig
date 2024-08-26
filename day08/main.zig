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

    fn navigateMultiple(self: *Network) !u32 {
        const State = struct {
            curr: []const u8,
            node: *Node,
        };
        var state = std.ArrayList(State).init(self.allocator);
        defer state.deinit();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (key[2] == 'A') {
                try state.append(.{ .curr = key, .node = entry.value_ptr });
            }
        }

        var slide: usize = 0;
        var reached: u32 = 0;
        var distance: u32 = 0;
        while (reached < state.items.len) : (slide = (slide + 1) % self.instructions.len) {
            const turn = self.instructions[slide];
            reached = 0;
            for (state.items) |*item| {
                item.curr = if (turn == 'L') item.node.left else item.node.right;
                item.node = self.map.getPtr(item.curr).?;
                if (item.curr[2] == 'Z') {
                    reached += 1;
                }
            }
            distance += 1;
        }
        return distance;
    }
};

test "example 1 - part 1" {
    var network = try Network.init(std.testing.allocator, example1);
    defer network.deinit();

    try std.testing.expectEqual(@as(u32, 2), network.navigate());
}

test "example 2 - part 1" {
    var network = try Network.init(std.testing.allocator, example2);
    defer network.deinit();

    try std.testing.expectEqual(@as(u32, 6), network.navigate());
}

test "input - part 1" {
    var network = try Network.init(std.testing.allocator, input);
    defer network.deinit();

    try std.testing.expectEqual(@as(u32, 16897), network.navigate());
}

test "example 3 - part 2" {
    var network = try Network.init(std.testing.allocator, example3);
    defer network.deinit();

    try std.testing.expectEqual(@as(u32, 6), try network.navigateMultiple());
}

test "input - part 2" {
    var network = try Network.init(std.testing.allocator, input);
    defer network.deinit();

    try std.testing.expectEqual(@as(u32, 0), try network.navigateMultiple());
}
