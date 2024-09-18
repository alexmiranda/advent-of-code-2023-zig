const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const testing = std.testing;
const Tuple = std.meta.Tuple;
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

const Transmission = struct {
    input: []const u8,
    pulse: Pulse,
    output: []const u8,
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
        var queue = std.ArrayListUnmanaged(Transmission){};
        defer queue.deinit(ally);

        var empty = std.StringHashMapUnmanaged(usize){};
        defer empty.deinit(ally);

        var count_low: u32 = 0;
        var count_high: u32 = 0;
        for (1..n + 1) |i| {
            const counts = try self.transmit(ally, &queue, &empty, i);
            count_low += counts.@"0";
            count_high += counts.@"1";
        }

        return count_low * count_high;
    }

    fn turnMachineOn(self: *ModuleConfiguration) !u64 {
        const ally = self.arena.allocator();
        var queue = std.ArrayListUnmanaged(Transmission){};
        defer queue.deinit(ally);

        var tracker = std.StringHashMapUnmanaged(usize){};
        defer tracker.deinit(ally);

        const modules_to_track = try self.findModulesToTrack(ally);
        for (modules_to_track) |mod_name| {
            try tracker.put(ally, mod_name, 0);
        }

        var result: u64 = 1;
        var slider: usize = 1;
        var all_cycles_tracked = false;
        while (!all_cycles_tracked) : (slider += 1) {
            _ = try self.transmit(ally, &queue, &tracker, slider);
            var it = tracker.valueIterator();
            all_cycles_tracked = while (it.next()) |x| {
                if (x.* == 0) break false;
                result = lcm(result, x.*);
            } else true;
        }
        return result;
    }

    fn transmit(self: *ModuleConfiguration, ally: mem.Allocator, queue: *std.ArrayListUnmanaged(Transmission), tracker: *std.StringHashMapUnmanaged(usize), i: usize) !struct { u32, u32 } {
        var count_low: u32 = 0;
        var count_high: u32 = 0;
        try queue.append(ally, .{ .input = "button", .pulse = false, .output = "broadcaster" });
        while (queue.items.len > 0) {
            const tx = queue.orderedRemove(0);
            // print("{s} -{s}-> {s}\n", .{ tx.input, if (tx.pulse) "high" else "low", tx.output });
            if (tx.pulse) count_high += 1 else count_low += 1;

            // track cycles
            if (tracker.contains(tx.output) and !tx.pulse) {
                // print("{s} received high pulse after {d} presses.\n", .{ tx.output, i });
                tracker.getPtr(tx.output).?.* = i;
            }

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
                    const gop = memory.getOrPutAssumeCapacity(tx.input);
                    assert(gop.found_existing);
                    gop.value_ptr.* = tx.pulse;
                    const every_pulse_is_high = for (memory.values()) |pulse| {
                        if (!pulse) break false;
                    } else true;
                    break :blk !every_pulse_is_high;
                },
            };
            for (mod.outputs) |output| try queue.append(ally, .{ .input = tx.output, .pulse = outgoing, .output = output });
        }
        return .{ count_low, count_high };
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

    fn findModulesToTrack(self: *ModuleConfiguration, ally: mem.Allocator) ![][]const u8 {
        var it = self.mods.iterator();

        // first determine the module that feeds into rx itself. There's only one!
        var rx_input: []const u8 = undefined;
        outer: while (it.next()) |entry| {
            for (entry.value_ptr.outputs) |output| {
                if (mem.eql(u8, output, "rx")) {
                    rx_input = entry.key_ptr.*;
                    break :outer;
                }
            }
        }

        // There are four conjunction inputs that feed into the rx input module
        var inputs = std.ArrayListUnmanaged([]const u8){};
        errdefer inputs.deinit(ally); // errdefer because we call toOwnedSlice at the end
        try inputs.ensureTotalCapacityPrecise(ally, 4);

        it.index = 0; // reset iterator
        while (it.next()) |entry| {
            for (entry.value_ptr.outputs) |output| {
                if (mem.eql(u8, output, rx_input)) {
                    try inputs.append(ally, entry.key_ptr.*);
                }
            }
        }

        return try inputs.toOwnedSlice(ally);
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

test "input - part 2" {
    var config = try ModuleConfiguration.initParse(testing.allocator, input);
    defer config.deinit();
    const result = try config.turnMachineOn();
    try expectEqual(240162699605221, result);
}

test "lcm" {
    var x: u64 = lcm(3733, 3911);
    x = lcm(x, 4019);
    x = lcm(x, 4093);
    try expectEqual(240162699605221, x);
}

fn lcm(a: anytype, b: anytype) @TypeOf(a, b) {
    return (a * b) / math.gcd(a, b);
}
