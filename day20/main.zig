const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const print = std.debug.print;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const example1 = @embedFile("example1.txt");
const example2 = @embedFile("example2.txt");
const input = @embedFile("input.txt");

// low = false, high = true
const Pulse = bool;
// off = false, on = true
const State = bool;

const ModuleType = union(enum) {
    broadcaster: void,
    flip_flop: State,
    conjunction: std.StringArrayHashMapUnmanaged(Pulse),
};

const Module = struct {
    outputs: [][]const u8,
    type: ModuleType,
};

const ModuleConfiguration = struct {
    arena: heap.ArenaAllocator,
    mods: std.StringHashMapUnmanaged(Module),

    fn initParse(allocator: mem.Allocator, buffer: []const u8) !ModuleConfiguration {
        var arena = heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const ally = arena.allocator();

        var mods = std.StringHashMapUnmanaged(Module){};
        var outputs = std.ArrayListUnmanaged([]const u8){};
        var lines_it = mem.tokenizeScalar(u8, buffer, '\n');
        while (lines_it.next()) |line| {
            try parseLine(ally, line, &mods, &outputs);
        }

        try setConjectionModuleInputs(ally, &mods);
        return .{ .arena = arena, .mods = mods };
    }

    fn deinit(self: ModuleConfiguration) void {
        self.arena.deinit();
    }

    fn sendPulses(self: *ModuleConfiguration, n: u16) !u32 {
        const ally = self.arena.allocator();
        const Transmission = struct { input: []const u8, pulse: Pulse, output: []const u8 };
        var queue = std.ArrayListUnmanaged(Transmission){};
        defer queue.deinit(ally);

        var count_low: u32 = 0;
        var count_high: u32 = 0;
        for (0..n) |_| {
            assert(queue.items.len == 0);
            try queue.append(ally, .{ .input = "button", .pulse = false, .output = "broadcaster" });
            while (queue.items.len > 0) {
                const tx = queue.orderedRemove(0);
                // print("{s} -{s}-> {s}\n", .{ tx.input, if (tx.pulse) "high" else "low", tx.output });
                if (tx.pulse) count_high += 1 else count_low += 1;
                const mod = self.mods.getPtr(tx.output) orelse continue;
                const outgoing = switch (mod.type) {
                    .broadcaster => tx.pulse,
                    .flip_flop => |*state| blk: {
                        // if it receives a low pulse, it flips between on and off
                        // if it was off, it turns on and sends a high pulse
                        // if it was on, it turns off and sends a low pulse
                        if (tx.pulse) continue;
                        state.* = !state.*;
                        break :blk state.*;
                    },
                    .conjunction => |*memory| blk: {
                        // if it remembers high pulses for all inputs, it sends a low pulse; otherwise, it sends a high pulse
                        const gob = memory.getOrPutAssumeCapacity(tx.input);
                        assert(gob.found_existing);
                        gob.value_ptr.* = tx.pulse;
                        const every_pulse_is_high = for (memory.values()) |pulse| {
                            if (!pulse) break false;
                        } else true;
                        break :blk !every_pulse_is_high;
                    },
                };
                for (mod.outputs) |output| try queue.append(ally, .{ .input = tx.output, .pulse = outgoing, .output = output });
            }
        }
        return count_low * count_high;
    }

    fn parseLine(ally: mem.Allocator, line: []const u8, mods: *std.StringHashMapUnmanaged(Module), outputs: *std.ArrayListUnmanaged([]const u8)) !void {
        var it = mem.tokenizeAny(u8, line, " ,");

        var mod_name: []const u8 = undefined;
        var mod_type: ModuleType = undefined;
        var token = it.next().?;
        switch (token[0]) {
            '%' => {
                mod_name = token[1..];
                mod_type = .{ .flip_flop = false };
            },
            '&' => {
                mod_name = token[1..];
                const inputs = std.StringArrayHashMapUnmanaged(Pulse){};
                mod_type = .{ .conjunction = inputs };
            },
            else => {
                assert(mem.eql(u8, token, "broadcaster"));
                mod_name = token;
                mod_type = .{ .broadcaster = {} };
            },
        }

        _ = it.next(); // skip ->
        while (it.next()) |output| {
            try outputs.append(ally, output);
        }

        const mod = Module{
            .outputs = try outputs.toOwnedSlice(ally),
            .type = mod_type,
        };
        // printModule(mod_name, mod);

        try mods.put(ally, mod_name, mod);
    }

    fn setConjectionModuleInputs(ally: mem.Allocator, mods: *std.StringHashMapUnmanaged(Module)) !void {
        var it = mods.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*.outputs) |mod_name| {
                if (mods.getPtr(mod_name)) |mod| {
                    switch (mod.type) {
                        .conjunction => |*memory| {
                            try memory.put(ally, entry.key_ptr.*, false);
                        },
                        else => {},
                    }
                }
            }
        }
    }

    fn printModule(name: []const u8, mod: Module) void {
        const prefix = switch (mod.type) {
            .broadcaster => "",
            .flip_flop => "%",
            .conjunction => "&",
        };
        print("{s}{s} -> {s}\n", .{ prefix, name, mod.outputs });
    }
};

test "example1 - part 1" {
    var config = try ModuleConfiguration.initParse(testing.allocator, example1);
    defer config.deinit();
    const result = try config.sendPulses(1_000);
    try expectEqual(32000000, result);
}

test "example2 - part 1" {
    var config = try ModuleConfiguration.initParse(testing.allocator, example2);
    defer config.deinit();
    const result = try config.sendPulses(1_000);
    try expectEqual(11687500, result);
}

test "input - part 1" {
    var config = try ModuleConfiguration.initParse(testing.allocator, input);
    defer config.deinit();
    const result = try config.sendPulses(1_000);
    try expectEqual(832957356, result);
}
