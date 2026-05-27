const std = @import("std");

pub const Token = union(enum) {
    heading: struct { level: u8, text: []const u8 },
    paragraph: []const u8,
    quote: []const u8,
    text: []const u8,
    code_block: struct { language: []const u8, code: []const u8 },
    horizontal_rule: void,
};

fn flushParagraph(allocator: std.mem.Allocator, current_para: *std.ArrayListUnmanaged(u8), tokens: *std.ArrayListUnmanaged(Token)) !void {
    if (current_para.items.len > 0) {
        try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
        current_para.clearRetainingCapacity();
    }
}

pub fn tokenize(allocator: std.mem.Allocator, content: []const u8) ![]Token {
    const cleanup = @import("cleanup.zig");

    var tokens = std.ArrayListUnmanaged(Token).empty;
    errdefer {
        cleanup.freeTokenPayloads(allocator, tokens.items);
        tokens.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_para = std.ArrayListUnmanaged(u8).empty;
    defer current_para.deinit(allocator);

    var in_code_block = false;
    var code_language = std.ArrayListUnmanaged(u8).empty;
    defer code_language.deinit(allocator);
    var code_content = std.ArrayListUnmanaged(u8).empty;
    defer code_content.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (std.mem.startsWith(u8, trimmed, "```")) {
            try flushParagraph(allocator, &current_para, &tokens);

            if (!in_code_block) {
                in_code_block = true;
                const lang = std.mem.trim(u8, trimmed[3..], " ");
                try code_language.appendSlice(allocator, lang);
            } else {
                in_code_block = false;
                try tokens.append(allocator, .{ .code_block = .{
                    .language = try code_language.toOwnedSlice(allocator),
                    .code = try code_content.toOwnedSlice(allocator),
                } });
                code_language.clearRetainingCapacity();
                code_content.clearRetainingCapacity();
            }
            continue;
        }

        if (in_code_block) {
            if (code_content.items.len > 0) {
                try code_content.append(allocator, '\n');
            }
            try code_content.appendSlice(allocator, line);
            continue;
        }

        if (std.mem.eql(u8, trimmed, "---") or std.mem.eql(u8, trimmed, "***") or std.mem.eql(u8, trimmed, "___")) {
            try flushParagraph(allocator, &current_para, &tokens);
            try tokens.append(allocator, .{ .horizontal_rule = {} });
            continue;
        }

        if (trimmed.len == 0) {
            try flushParagraph(allocator, &current_para, &tokens);
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "#")) {
            try flushParagraph(allocator, &current_para, &tokens);

            var level: u8 = 0;
            var i: usize = 0;
            while (i < trimmed.len and trimmed[i] == '#' and level < 6) : (i += 1) {
                level += 1;
            }

            const text = std.mem.trim(u8, trimmed[i..], " ");
            try tokens.append(allocator, .{ .heading = .{ .level = level, .text = try allocator.dupe(u8, text) } });
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, ">")) {
            try flushParagraph(allocator, &current_para, &tokens);

            const text = std.mem.trim(u8, trimmed[1..], " ");
            try tokens.append(allocator, .{ .quote = try allocator.dupe(u8, text) });
            continue;
        }

        if (current_para.items.len > 0) {
            try current_para.append(allocator, ' ');
        }
        try current_para.appendSlice(allocator, trimmed);
    }

    // Handle unclosed code block: output accumulated content as paragraph
    if (in_code_block) {
        if (code_content.items.len > 0) {
            try tokens.append(allocator, .{ .paragraph = try code_content.toOwnedSlice(allocator) });
            code_content.clearRetainingCapacity();
        }
    }

    try flushParagraph(allocator, &current_para, &tokens);

    return tokens.toOwnedSlice(allocator);
}
