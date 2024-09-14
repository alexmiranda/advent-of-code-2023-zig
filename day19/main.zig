const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Part = struct {
    x: u16,
    m: u16,
    a: u16,
    s: u16,

    fn rating(self: Part) u32 {
        const res: u32 = self.x + self.m + self.a + self.s;
        return res;
    }
};

const Cond = union(enum) {
    lt: u16,
    gt: u16,

    fn fromChar(c: u8) Cond {
        return switch (c) {
            '<' => .lt,
            '>' => .gt,
            else => undefined,
        };
    }

    fn eval(self: Cond, val: u16) bool {
        return switch (self) {
            .lt => |n| val < n,
            .gt => |n| val > n,
        };
    }
};

const Result = union(enum) {
    accepted: void,
    rejected: void,
    eval: []const u8,
};

const Rule = union(enum) {
    pred: struct { field: u8, cond: Cond, res: Result },
    immediate: Result,
};

const Workflow = struct {
    rules: []Rule,
};

const WorkflowMap = std.StringHashMap(Workflow);
const PartList = std.ArrayList(Part);

const System = struct {
    allocator: mem.Allocator,
    workflows: std.StringHashMap(Workflow),
    parts: []Part,

    fn initParse(allocator: mem.Allocator, buffer: []const u8) !System {
        var it = mem.splitScalar(u8, buffer, '\n');

        // add workflows
        var workflows = WorkflowMap.init(allocator);
        errdefer workflows.deinit();
        while (it.next()) |line| {
            if (line.len == 0) break;
            try addWorkflow(allocator, &workflows, line);
        }

        // add parts
        var parts = try PartList.initCapacity(allocator, 4);
        defer parts.deinit();
        while (it.next()) |line| {
            if (line.len == 0) continue;
            try addPart(&parts, line);
        }

        return .{
            .allocator = allocator,
            .workflows = workflows,
            .parts = try parts.toOwnedSlice(),
        };
    }

    fn deinit(self: *System) void {
        var it = self.workflows.valueIterator();
        while (it.next()) |wf| {
            self.allocator.free(wf.rules);
        }
        self.workflows.deinit();
        self.allocator.free(self.parts);
    }

    fn execute(self: *System) u32 {
        var sum: u32 = 0;
        for (self.parts) |part| {
            if (self.isAccepted(part, "in")) sum += part.rating();
        }
        return sum;
    }

    fn isAccepted(self: *System, part: Part, wf_name: []const u8) bool {
        const workflow = self.workflows.get(wf_name).?;
        for (workflow.rules) |rule| {
            switch (rule) {
                .immediate => |res| {
                    return switch (res) {
                        .accepted => true,
                        .rejected => false,
                        .eval => |wf| self.isAccepted(part, wf),
                    };
                },
                .pred => |predicate| {
                    const val = switch (predicate.field) {
                        'x' => part.x,
                        'm' => part.m,
                        'a' => part.a,
                        's' => part.s,
                        else => unreachable,
                    };
                    if (predicate.cond.eval(val)) {
                        return switch (predicate.res) {
                            .accepted => true,
                            .rejected => false,
                            .eval => |wf| self.isAccepted(part, wf),
                        };
                    }
                },
            }
        }
        @panic("at least one rule must match!");
    }

    fn addWorkflow(allocator: mem.Allocator, workflows: *WorkflowMap, line: []const u8) !void {
        const bracket_pos = mem.indexOfScalar(u8, line, '{').?;
        const wf_name = line[0..bracket_pos];
        var it = mem.tokenizeScalar(u8, line[bracket_pos + 1 .. line.len - 1], ',');
        const rules = blk: {
            var rules = try std.ArrayList(Rule).initCapacity(allocator, 4);
            defer rules.deinit();
            while (it.next()) |token| {
                switch (token[0]) {
                    'A' => try rules.append(.{ .immediate = .{ .accepted = {} } }),
                    'R' => try rules.append(.{ .immediate = .{ .rejected = {} } }),
                    else => {
                        if (mem.indexOfAny(u8, token, "<>")) |op_pos| {
                            const field = token[0];
                            const colon_pos = mem.indexOfScalarPos(u8, token, op_pos + 2, ':').?;
                            const val = try fmt.parseInt(u16, token[op_pos + 1 .. colon_pos], 10);
                            const cond = switch (token[op_pos]) {
                                '<' => Cond{ .lt = val },
                                '>' => Cond{ .gt = val },
                                else => unreachable,
                            };
                            switch (token[colon_pos + 1]) {
                                'A' => try rules.append(.{ .pred = .{ .field = field, .cond = cond, .res = .{ .accepted = {} } } }),
                                'R' => try rules.append(.{ .pred = .{ .field = field, .cond = cond, .res = .{ .rejected = {} } } }),
                                else => try rules.append(.{ .pred = .{ .field = field, .cond = cond, .res = .{ .eval = token[colon_pos + 1 ..] } } }),
                            }
                        } else {
                            try rules.append(.{ .immediate = .{ .eval = token } });
                        }
                    },
                }
            }
            break :blk try rules.toOwnedSlice();
        };
        try workflows.put(wf_name, .{ .rules = rules });
    }

    fn addPart(parts: *PartList, line: []const u8) !void {
        var it = mem.tokenizeAny(u8, line[1 .. line.len - 1], ",=");
        var part: Part = undefined;
        while (it.next()) |field_name| {
            const val = try fmt.parseInt(u16, it.next().?, 10);
            switch (field_name[0]) {
                'x' => part.x = val,
                'm' => part.m = val,
                'a' => part.a = val,
                's' => part.s = val,
                else => unreachable,
            }
        }
        try parts.append(part);
    }

    // unused
    fn dump(self: *System) void {
        var it = self.workflows.iterator();
        while (it.next()) |entry| {
            print("{s}{{", .{entry.key_ptr.*});
            for (entry.value_ptr.*.rules, 0..) |rule, i| {
                switch (rule) {
                    .immediate => |res| {
                        switch (res) {
                            .accepted => print("A", .{}),
                            .rejected => print("R", .{}),
                            .eval => |val| print("{s}", .{val}),
                        }
                    },
                    .pred => |pred| {
                        switch (pred.cond) {
                            .lt => |val| print("{c}<{d}:", .{ pred.field, val }),
                            .gt => |val| print("{c}>{d}:", .{ pred.field, val }),
                        }
                        switch (pred.res) {
                            .accepted => print("A", .{}),
                            .rejected => print("R", .{}),
                            .eval => |val| print("{s}", .{val}),
                        }
                    },
                }
                if (i < entry.value_ptr.*.rules.len - 1) print(",", .{}) else print("}}\n", .{});
            }
        }
        print("\n", .{});
        for (self.parts) |part| {
            print("{{x={d},m={d},a={d},s={d}}}\n", part);
        }
    }
};

test "example - part 1" {
    var system = try System.initParse(testing.allocator, example);
    defer system.deinit();
    const total_ratings = system.execute();
    try expectEqual(19114, total_ratings);
}

test "input - part 1" {
    var system = try System.initParse(testing.allocator, input);
    defer system.deinit();
    const total_ratings = system.execute();
    try expectEqual(476889, total_ratings);
}
