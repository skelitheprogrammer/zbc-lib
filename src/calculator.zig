const std = @import("std");

const Token = union(Tag) {
    operand: []const u8,
    operator: u8,
};
const Tag = enum {
    operand,
    operator,
};

const CalculatorError = error{
    InvalidExpression,
    UnexpectedToken,
};

fn tokenize(allocator: std.mem.Allocator, input: *const []const u8) ![]Token {
    var list = std.ArrayList(Token).init(allocator);
    defer list.deinit();

    var i: usize = 0;
    while (i < input.len) {
        switch (input.*[i]) {
            '-' => {
                if (i == 0 or (i > 0 and list.items[i - 1] != .operand)) {
                    const start = i;
                    i += 1;
                    while (i < input.len and (std.ascii.isDigit(input.*[i]) or input.*[i] == '.')) {
                        i += 1;
                    }
                    try list.append(.{ .operand = input.*[start..i] });
                } else {
                    try list.append(.{ .operator = '-' });
                    i += 1;
                }
            },
            '+', '/', '*', '(', ')' => {
                try list.append(.{ .operator = input.*[i] });
                i += 1;
            },
            '0'...'9' => {
                const start = i;
                while (i < input.len and (std.ascii.isDigit(input.*[i]) or input.*[i] == '.')) {
                    i += 1;
                }

                try list.append(.{ .operand = input.*[start..i] });
            },
            '.' => {
                const start = i;
                i += 1;
                while (i < input.len and std.ascii.isDigit(input.*[i])) {
                    i += 1;
                }
                try list.append(.{ .operand = input.*[start..i] });
            },
            '\n' => break,
            else => return CalculatorError.UnexpectedToken,
        }
    }
    return list.toOwnedSlice();
}

fn validate(allocator: std.mem.Allocator, tokens: *const []const Token) !void {
    if (tokens.len < 3) {
        return CalculatorError.InvalidExpression;
    }

    var stack = std.ArrayList(Token).init(allocator);
    defer stack.deinit();

    var previousToken: ?Token = undefined;
    for (tokens.*) |token| {
        if (previousToken != null) {
            switch (token) {
                .operand => {
                    if (previousToken.? == .operand) {
                        return CalculatorError.InvalidExpression;
                    }
                },
                .operator => |value| {
                    switch (value) {
                        '+', '-', '/', '*' => {
                            if (previousToken.? == .operator) {
                                return CalculatorError.InvalidExpression;
                            }
                        },
                        '(' => {
                            if (previousToken.? == .operand) {
                                return CalculatorError.InvalidExpression;
                            }
                            try stack.append(token);
                        },
                        ')' => {
                            if (stack.items.len == 0) {
                                return CalculatorError.InvalidExpression;
                            }

                            _ = stack.pop();
                        },
                        else => return CalculatorError.InvalidExpression,
                    }
                },
            }
        }

        previousToken = token;
    }

    if (stack.items.len > 0) {
        return error.InvalidExpression;
    }
}

fn postfix(allocator: std.mem.Allocator, tokens: *const []const Token) ![]Token {
    var stack = std.ArrayList(Token).init(allocator);
    var queue = std.ArrayList(Token).init(allocator);
    defer stack.deinit();
    defer queue.deinit();

    for (tokens.*) |token| {
        try ls: switch (token) {
            .operand => try queue.append(token),
            .operator => |value| {
                try switch (value) {
                    '+', '-', '/', '*' => {
                        if (stack.items.len > 0) {
                            const current = precedence(token.operator);
                            const previous = precedence(stack.items[stack.items.len - 1].operator);

                            if (current <= previous) {
                                try queue.append(stack.pop().?);
                            }

                            try stack.append(token);
                        } else {
                            try stack.append(token);
                        }
                    },
                    '(' => stack.append(token),
                    ')' => {
                        while (true) {
                            const op = stack.pop().?;
                            if (op.operator == '(') {
                                break;
                            }
                            try queue.append(op);
                        }
                    },
                    else => break :ls CalculatorError.InvalidExpression,
                };
            },
        };
    }

    while (stack.items.len > 0) {
        try queue.append(stack.pop().?);
    }

    return queue.toOwnedSlice();
}

fn evaluate(allocator: std.mem.Allocator, tokens: *const []const Token) !f64 {
    var numStack = std.ArrayList(f64).init(allocator);
    defer numStack.deinit();

    for (tokens.*) |token| {
        if (token == .operand) {
            const num = try std.fmt.parseFloat(f64, token.operand);
            try numStack.append(num);
        } else {
            const b = numStack.pop().?;
            const a = numStack.pop().?;
            const result = try calculate(f64, a, b, token.operator);
            try numStack.append(result);
        }
    }
    return numStack.items[0];
}

pub fn process(input: *const []const u8) !f64 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try tokenize(allocator, input);
    defer allocator.free(tokens);

    try validate(allocator, &tokens);
    const converted = try postfix(allocator, &tokens);
    defer allocator.free(converted);

    return try evaluate(allocator, &converted);
}

fn calculate(comptime T: type, num1: T, num2: T, op: u8) !T {
    return switch (op) {
        '+' => num1 + num2,
        '-' => num1 - num2,
        '*' => num1 * num2,
        '/' => if (num2 == 0) return error.DivisionByZero else num1 / num2,
        else => error.InvalidOperation,
    };
}
fn precedence(op: u8) u8 {
    switch (op) {
        '+', '-' => return 1,
        '*', '/' => return 2,
        else => return 0,
    }
}

fn isOperator(tag: u8) bool {
    switch (tag) {
        '+', '-', '/', '*' => return true,
        else => return false,
    }
}

fn expectTokens(input: []const u8, expected: [*][]const u8) !void {
    const tokens = try tokenize(std.testing.allocator, &input);
    defer std.testing.allocator.free(tokens);

    for (expected, tokens) |exp, token| {
        switch (token) {
            .operand => try std.testing.expectEqualStrings(exp, token.operand),
            .operator => {
                const slice: []const u8 = &[_]u8{token.operator};
                try std.testing.expectEqualStrings(exp, slice);
            },
        }
    }
}

test "tokenize" {
    {
        var expected = [_][]const u8{ "1", "+", "(", "2", "-", "3", ")" };
        try expectTokens("1+(2-3)", &expected);
    }

    {
        var expected = [_][]const u8{ "-1", "+", "2" };
        try expectTokens("-1+2", &expected);
    }

    {
        var expected = [_][]const u8{ "1", "+", "-1.1" };
        try expectTokens("1+-1.1", &expected);
    }
}

test "validate" {
    const tokens = try tokenize(std.testing.allocator, &"1");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(CalculatorError.InvalidExpression, validate(std.testing.allocator, &tokens));
}

test "postfix" {
    const input = "1+(2-3)\n";
    const tokens = try tokenize(std.testing.allocator, &input[0..input.len]);
    defer std.testing.allocator.free(tokens);
    const expected = "123-+";

    const converted = try postfix(std.testing.allocator, &tokens);
    defer std.testing.allocator.free(converted);

    for (converted, 0..) |item, i| {
        switch (item) {
            .operand => {
                const st = std.mem.eql(u8, item.operand, expected[i .. i + 1]);
                try std.testing.expect(st);
            },
            .operator => {
                try std.testing.expect(item.operator == expected[i]);
            },
        }
    }
}

test "evalulate" {
    {
        const input: []const u8 = "1+(2-3)";
        const result = try process(&input);
        try std.testing.expect(result == 0);
    }

    {
        const input: []const u8 = "1+.1";
        const result = try process(&input);
        try std.testing.expectEqual(1.1, result);
    }
}
