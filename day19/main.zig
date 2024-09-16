const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;
const math = std.math;
const Order = std.math.Order;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;
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

    fn fromChar(c: u8, val: u16) Cond {
        return switch (c) {
            '<' => .{ .lt = val },
            '>' => .{ .gt = val },
            else => undefined,
        };
    }

    fn eval(self: Cond, n: u16) bool {
        return switch (self) {
            .lt => |val| n < val,
            .gt => |val| n > val,
        };
    }
};

const Predicate = struct {
    field: u8,
    cond: Cond,

    fn eval(self: Predicate, part: Part) bool {
        const n = switch (self.field) {
            inline 'x', 'm', 'a', 's' => |c| @field(part, &[_]u8{c}),
            else => unreachable,
        };
        return self.cond.eval(n);
    }

    fn neg(self: Predicate) Predicate {
        return switch (self.cond) {
            .lt => |val| .{ .field = self.field, .cond = .{ .gt = val - 1 } },
            .gt => |val| .{ .field = self.field, .cond = .{ .lt = val + 1 } },
        };
    }
};

const Result = union(enum) {
    accepted: void,
    rejected: void,
    eval: []const u8,
};

const Rule = union(enum) {
    immediate: Result,
    constrained: struct { pred: Predicate, res: Result },
};

const Workflow = struct {
    rules: []Rule,
};

const WorkflowMap = std.StringHashMap(Workflow);

const PartList = std.ArrayList(Part);

const PredicateStack = std.ArrayList(Predicate);

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
            // break if we find an empty line
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
        // need to clean up every rules array of every workflow
        var it = self.workflows.valueIterator();
        while (it.next()) |wf| {
            self.allocator.free(wf.rules);
        }
        self.workflows.deinit();
        self.allocator.free(self.parts);
    }

    // sum the ratings of parts which are accepted
    fn execute(self: *System) u32 {
        var sum: u32 = 0;
        for (self.parts) |part| {
            if (self.isAccepted(part, "in")) sum += part.rating();
        }
        return sum;
    }

    // compute all the possible combinations of parts where each
    // individual category has values in the range 1...4000
    fn computeAllCombinations(self: *System) !u64 {
        var stack = PredicateStack.init(self.allocator);
        defer stack.deinit();
        return try self.countCombinations("in", &stack);
    }

    // recursively count all combinations of accepted parts in the implicit range 0...4000
    fn countCombinations(self: *System, wf_name: []const u8, stack: *PredicateStack) !u64 {
        var sum_combinations: u64 = 0;
        const workflow = self.workflows.get(wf_name).?;
        for (workflow.rules) |rule| {
            var is_constrained = false;
            const res = switch (rule) {
                .constrained => |constraint| blk: {
                    try stack.append(constraint.pred);
                    is_constrained = true;
                    break :blk constraint.res;
                },
                .immediate => |res| res,
            };
            switch (res) {
                .eval => |next_wf_name| {
                    const stack_size = stack.items.len;
                    defer stack.shrinkRetainingCapacity(stack_size);
                    sum_combinations += try self.countCombinations(next_wf_name, stack);
                },
                .accepted => {
                    sum_combinations += countRangesIn(stack.items);
                },
                .rejected => {},
            }
            if (is_constrained) {
                const pred = stack.pop();
                try stack.append(pred.neg());
            }
        }
        return sum_combinations;
    }

    // calculate the product of all categories which pass all of the predicates
    fn countRangesIn(predicates: []Predicate) u64 {
        const Range = struct { start: u64, end: u64 };
        var xr = Range{ .start = 1, .end = 4000 };
        var mr = Range{ .start = 1, .end = 4000 };
        var ar = Range{ .start = 1, .end = 4000 };
        var sr = Range{ .start = 1, .end = 4000 };

        // evaluate each predicate and narrow the appropriate range
        for (predicates) |pred| {
            var range = switch (pred.field) {
                'x' => &xr,
                'm' => &mr,
                'a' => &ar,
                's' => &sr,
                else => unreachable,
            };
            switch (pred.cond) {
                .lt => |val| {
                    if (val > range.start and val <= range.end) {
                        range.end = val - 1;
                    } else {
                        // we found a predicate that results in an empty range
                        return 0;
                    }
                },
                .gt => |val| {
                    if (val >= range.start and val < range.end) {
                        range.start = val + 1;
                    } else {
                        // we found a predicate that results in an empty range
                        return 0;
                    }
                },
            }
            // printPredicate(pred);
            // print(" => {any}\n", .{range});
        }
        return (xr.end - xr.start + 1) *
            (mr.end - mr.start + 1) *
            (ar.end - ar.start + 1) *
            (sr.end - sr.start + 1);
    }

    // evaluate the workflow rules for a given part
    fn isAccepted(self: *System, part: Part, wf_name: []const u8) bool {
        const workflow = self.workflows.get(wf_name).?;
        for (workflow.rules) |rule| {
            // get the result only if the predicate condition passes
            const result = switch (rule) {
                .immediate => |res| res,
                .constrained => |constraint| blk: {
                    if (constraint.pred.eval(part)) {
                        break :blk constraint.res;
                    }
                    break :blk null;
                },
            };
            if (result) |res| {
                return switch (res) {
                    .accepted => true,
                    .rejected => false,
                    // evaluate the next workflow
                    .eval => |wf| self.isAccepted(part, wf),
                };
            }
        }
        @panic("at least one rule must match!");
    }

    fn addWorkflow(allocator: mem.Allocator, workflows: *WorkflowMap, line: []const u8) !void {
        // ensure that we have capacity to store at least one workflow so that we don't need an errdefer
        // after creating a slice of rules
        try workflows.ensureUnusedCapacity(1);
        const bracket_pos = mem.indexOfScalar(u8, line, '{').?;
        const wf_name = line[0..bracket_pos];
        var it = mem.tokenizeScalar(u8, line[bracket_pos + 1 .. line.len - 1], ',');
        const rules = blk: {
            var rules = try std.ArrayList(Rule).initCapacity(allocator, 4);
            defer rules.deinit();
            while (it.next()) |token| {
                switch (token[0]) {
                    // conditionless accepted
                    'A' => try rules.append(.{ .immediate = .{ .accepted = {} } }),
                    // conditionless rejected
                    'R' => try rules.append(.{ .immediate = .{ .rejected = {} } }),
                    else => {
                        // conditionless deferred to another workflow evaluation
                        if (token[1] != '<' and token[1] != '>') {
                            try rules.append(.{ .immediate = .{ .eval = token } });
                            continue;
                        }

                        // rule with a predicate
                        const field = token[0];
                        const sep = mem.indexOfScalarPos(u8, token, 3, ':').?;
                        const val = try fmt.parseInt(u16, token[2..sep], 10);
                        const cond = Cond.fromChar(token[1], val);
                        const pred = Predicate{ .field = field, .cond = cond };
                        switch (token[sep + 1]) {
                            'A' => try rules.append(.{ .constrained = .{ .pred = pred, .res = .{ .accepted = {} } } }),
                            'R' => try rules.append(.{ .constrained = .{ .pred = pred, .res = .{ .rejected = {} } } }),
                            else => try rules.append(.{ .constrained = .{ .pred = pred, .res = .{ .eval = token[sep + 1 ..] } } }),
                        }
                    },
                }
            }
            break :blk try rules.toOwnedSlice();
        };
        workflows.putAssumeCapacity(wf_name, .{ .rules = rules });
    }

    fn addPart(parts: *PartList, line: []const u8) !void {
        var it = mem.tokenizeAny(u8, line[1 .. line.len - 1], ",=");
        var part: Part = undefined;
        while (it.next()) |field_name| {
            const val = try fmt.parseInt(u16, it.next().?, 10);
            switch (field_name[0]) {
                inline 'x', 'm', 'a', 's' => |c| @field(part, &[_]u8{c}) = val,
                else => unreachable,
            }
        }
        try parts.append(part);
    }

    // unused
    fn printPredicate(pred: Predicate) void {
        switch (pred.cond) {
            .lt => |val| print("{c}<{d}", .{ pred.field, val }),
            .gt => |val| print("{c}>{d}", .{ pred.field, val }),
        }
    }

    // unused
    fn dump(self: *System) void {
        const F = struct {
            fn printResult(res: Result) void {
                switch (res) {
                    .accepted => print("A", .{}),
                    .rejected => print("R", .{}),
                    .eval => |val| print("{s}", .{val}),
                }
            }
        };
        var it = self.workflows.iterator();
        while (it.next()) |entry| {
            print("{s}{{", .{entry.key_ptr.*});
            for (entry.value_ptr.*.rules, 0..) |rule, i| {
                switch (rule) {
                    .immediate => |res| F.printResult(res),
                    .constrained => |constraint| {
                        printPredicate(constraint.pred);
                        print(":", .{});
                        F.printResult(constraint.res);
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

test "example - part 2" {
    var system = try System.initParse(testing.allocator, example);
    defer system.deinit();
    const combinations = try system.computeAllCombinations();
    try expectEqual(167_409_079_868_000, combinations);
}

test "input - part 2" {
    var system = try System.initParse(testing.allocator, input);
    defer system.deinit();
    const combinations = try system.computeAllCombinations();
    try expectEqual(132380153677887, combinations);
}
