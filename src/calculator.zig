const std = @import("std");
pub const Token = struct { tag: Tag, value: []const u8 };

pub const Tag = enum {
    number,
    plus,
    minus,
    slash,
    asterisk,
    l_paren,
    r_paren,
};

fn tokenize(allocator: std.mem.Allocator, input: *const []const u8) ![]Token {
    var list = std.ArrayList(Token).init(allocator);
    defer list.deinit();

    var i: usize = 0;
    while (i < input.len) {
        switch (input.*[i]) {
            '+' => {
                try list.append(.{ .tag = .plus, .value = input.*[i .. i + 1] });
                i += 1;
            },
            '-' => {
                if (i == 0 or (i > 0 and list.items[i - 1].tag != .number)) {
                    const start = i;
                    i += 1;
                    while (i < input.len and (std.ascii.isDigit(input.*[i]) or input.*[i] == '.')) {
                        i += 1;
                    }
                    try list.append(.{ .tag = .number, .value = input.*[start..i] });
                } else {
                    try list.append(.{ .tag = .minus, .value = input.*[i .. i + 1] });
                    i += 1;
                }
            },
            '/' => {
                try list.append(.{ .tag = .slash, .value = input.*[i .. i + 1] });
                i += 1;
            },
            '*' => {
                try list.append(.{ .tag = .asterisk, .value = input.*[i .. i + 1] });
                i += 1;
            },
            '(' => {
                try list.append(.{ .tag = .l_paren, .value = input.*[i .. i + 1] });
                i += 1;
            },
            ')' => {
                try list.append(.{ .tag = .r_paren, .value = input.*[i .. i + 1] });
                i += 1;
            },
            '0'...'9' => {
                const start = i;
                while (i < input.len and (std.ascii.isDigit(input.*[i]) or input.*[i] == '.')) {
                    i += 1;
                }

                try list.append(.{ .tag = .number, .value = input.*[start..i] });
            },
            '.' => {
                const start = i;
                i += 1;
                while (i < input.len and std.ascii.isDigit(input.*[i])) {
                    i += 1;
                }
                try list.append(.{ .tag = .number, .value = input.*[start..i] });
            },
            '\n' => break,
            else => return error.UnexpectedToken,
        }
    }
    return list.toOwnedSlice();
}

fn validate(allocator: std.mem.Allocator, tokens: *const []const Token) !void {
    if (tokens.len < 3) {
        return error.InvalidExpression;
    }

    var stack = std.ArrayList(Tag).init(allocator);
    defer stack.deinit();

    var previousToken: ?Token = undefined;
    for (tokens.*) |token| {
        if (previousToken != null) {
            switch (token.tag) {
                .number => {
                    if (previousToken.?.tag == .number) {
                        return error.InvalidExpression;
                    }
                },
                .plus, .minus, .slash, .asterisk => {
                    if (isOperator(previousToken.?.tag)) {
                        return error.InvalidExpression;
                    }
                },
                .l_paren => {
                    if (previousToken.?.tag == .number) {
                        return error.InvalidExpression;
                    }
                    try stack.append(token.tag);
                },
                .r_paren => {
                    if (stack.items.len == 0) {
                        return error.InvalidExpression;
                    }

                    _ = stack.pop();
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
        try switch (token.tag) {
            .number => try queue.append(token),
            .minus,
            .plus,
            .slash,
            .asterisk,
            => {
                if (stack.items.len > 0) {
                    const current = precedence(token.tag);
                    const previous = precedence(stack.items[stack.items.len - 1].tag);

                    if (current <= previous) {
                        try queue.append(stack.pop().?);
                    }

                    try stack.append(token);
                } else {
                    try stack.append(token);
                }
            },
            .l_paren => stack.append(token),
            .r_paren => {
                while (true) {
                    const op = stack.pop().?;
                    if (op.tag == .l_paren) {
                        break;
                    }
                    try queue.append(op);
                }
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
        switch (token.tag) {
            .number => {
                const num = try std.fmt.parseFloat(f64, token.value);
                try numStack.append(num);
            },
            else => {
                const b = numStack.pop().?;
                const a = numStack.pop().?;
                const result = try calculate(f64, a, b, token.tag);
                try numStack.append(result);
            },
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

fn calculate(comptime T: type, num1: T, num2: T, op: Tag) !T {
    return switch (op) {
        .plus => num1 + num2,
        .minus => num1 - num2,
        .asterisk => num1 * num2,
        .slash => if (num2 == 0) return error.DivisionByZero else num1 / num2,
        else => error.InvalidOperation,
    };
}
fn precedence(tag: Tag) u8 {
    switch (tag) {
        .plus, .minus => return 1,
        .asterisk, .slash => return 2,
        else => return 0,
    }
}

fn isOperator(tag: Tag) bool {
    switch (tag) {
        .plus, .minus, .slash, .asterisk => return true,
        else => return false,
    }
}

test "tokenize" {
    {
        const input: []const u8 = "1+(2-3)";
        const tokens = try tokenize(std.testing.allocator, &input);
        defer std.testing.allocator.free(tokens);

        const expected = [_][]const u8{ "1", "+", "(", "2", "-", "3", ")" };

        for (tokens, expected) |token, exp| {
            try std.testing.expectEqualStrings(exp, token.value);
        }
    }

    {
        const input: []const u8 = "-1+2";
        const tokens = try tokenize(std.testing.allocator, &input);
        defer std.testing.allocator.free(tokens);

        const expected = [_][]const u8{ "-1", "+", "2" };

        for (tokens, expected) |token, exp| {
            try std.testing.expectEqualStrings(exp, token.value);
        }
    }

    {
        const input: []const u8 = "1+-1.1";
        const tokens = try tokenize(std.testing.allocator, &input);
        defer std.testing.allocator.free(tokens);

        const expected = [_][]const u8{ "1", "+", "-1.1" };

        for (tokens, expected) |token, exp| {
            try std.testing.expectEqualStrings(exp, token.value);
        }
    }
}

test "validate" {
    const tokens = try tokenize(std.testing.allocator, &"1");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.InvalidExpression, validate(std.testing.allocator, &tokens));
}

test "postfix" {
    const input = "1+(2-3)\n";
    const tokens = try tokenize(std.testing.allocator, &input[0..input.len]);
    defer std.testing.allocator.free(tokens);
    const expected = "123-+";

    const converted = try postfix(std.testing.allocator, &tokens);
    defer std.testing.allocator.free(converted);

    for (converted, 0..) |item, i| {
        const st = std.mem.eql(u8, item.value, expected[i .. i + 1]);
        try std.testing.expect(st);
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
