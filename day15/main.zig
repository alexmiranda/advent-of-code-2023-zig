const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Lense = struct {
    label: []const u8,
    focal_length: u8,
};

const Slots = std.DoublyLinkedList(Lense);

const HASHMAP = struct {
    allocator: mem.Allocator,
    boxes: [256]?Slots = undefined,

    fn initParse(allocator: mem.Allocator, buffer: []const u8) !HASHMAP {
        var self = HASHMAP{ .allocator = allocator };
        @memset(&self.boxes, null);
        const s = mem.trimRight(u8, buffer, "\n");
        var it = mem.tokenizeScalar(u8, s, ',');
        while (it.next()) |token| {
            try self.handleToken(token);
        }
        return self;
    }

    fn handleToken(self: *HASHMAP, token: []const u8) !void {
        var it = mem.tokenizeAny(u8, token, "=-");
        const label = it.next() orelse return;
        if (it.next()) |str| {
            const focal_length = try std.fmt.parseInt(u8, str, 10);
            try self.put(Lense{ .label = label, .focal_length = focal_length });
        } else {
            self.remove(label);
        }
    }

    fn put(self: *HASHMAP, lense: Lense) !void {
        const box = hash(lense.label);
        var slots = blk: {
            if (self.boxes[box] == null) self.boxes[box] = Slots{};
            break :blk &self.boxes[box].?;
        };

        var next = slots.first;
        const found_in_slot = while (next) |slot| : (next = slot.next) {
            if (mem.eql(u8, slot.data.label, lense.label)) {
                slot.data = lense;
                break true;
            }
        } else false;

        if (!found_in_slot) {
            const node = try self.allocator.create(Slots.Node);
            errdefer self.allocator.destroy(node);
            node.data = lense;
            slots.append(node);
            // print("added [{s} {d}] into box {d} ({any})\n", .{ lense.label, lense.focal_length, box, slots.first == null });
        }
    }

    fn remove(self: *HASHMAP, label: []const u8) void {
        const box = hash(label);
        if (self.boxes[box]) |*slots| {
            var next = slots.first;
            while (next) |slot| : (next = slot.next) {
                if (mem.eql(u8, slot.data.label, label)) {
                    slots.remove(slot);
                    self.allocator.destroy(slot);
                    break;
                }
            }
        }
    }

    fn focusingPower(self: *HASHMAP) usize {
        var focusing_power: usize = 0;
        for (self.boxes, 1..) |maybe_slots, box_val| {
            if (maybe_slots) |slots| {
                var slot_val: usize = 1;
                var next = slots.first;
                while (next) |slot| : (next = slot.next) {
                    const focal_length = slot.data.focal_length;
                    const individual_focusing_power = box_val * slot_val * focal_length;
                    focusing_power += individual_focusing_power;
                    slot_val += 1;
                    // print("{s}: {d} (box {d}) * {d} ({}th slot) * {d} (focal length) = {d}\n", .{ slot.data.label, box_val, box_val - 1, slot_val, slot_val - 1, focal_length, individual_focusing_power });
                }
            }
        }
        return focusing_power;
    }

    fn deinit(self: *HASHMAP) void {
        for (0..self.boxes.len) |i| {
            var slots = self.boxes[i] orelse continue;
            while (slots.pop()) |node| {
                self.allocator.destroy(node);
            }
        }
    }

    // unused
    fn printBoxes(boxes: []?Slots) void {
        for (boxes, 1..) |maybe_slots, box| {
            if (maybe_slots) |slots| {
                print("Box {d}: ", .{box});
                printSlots(slots);
            }
        }
    }

    fn printSlots(slots: Slots) void {
        var next = slots.first;
        while (next) |slot| : (next = slot.next) {
            print("[{s} {d}] ", .{ slot.data.label, slot.data.focal_length });
        }
        print("\n", .{});
    }
};

fn hash(s: []const u8) u32 {
    var sum: u32 = 0;
    var h: u32 = 0;
    return for (s) |c| switch (c) {
        ',', '\n' => {
            sum += h;
            h = 0;
        },
        else => h = (h + c) * 17 % 256,
    } else sum + h;
}

test "example HASH - part 1" {
    try expectEqual(52, hash("HASH"));
}

test "example - part 1" {
    try expectEqual(1320, hash(example));
}

test "input - part 1" {
    try expectEqual(507769, hash(input));
}

test "example - part 2" {
    var hashmap = try HASHMAP.initParse(testing.allocator, example);
    defer hashmap.deinit();
    try expectEqual(145, hashmap.focusingPower());
}

test "input - part 2" {
    var hashmap = try HASHMAP.initParse(std.heap.page_allocator, input);
    defer hashmap.deinit();
    try expectEqual(269747, hashmap.focusingPower());
}

test "hashes" {
    try expectEqual(0, hash("rn"));
    try expectEqual(1, hash("qp"));
    try expectEqual(0, hash("cm"));
    try expectEqual(3, hash("pc"));
    try expectEqual(3, hash("ot"));
    try expectEqual(3, hash("ab"));
}
