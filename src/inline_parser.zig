const std = @import("std");

pub const InlineToken = union(enum) {
    text: []const u8,
    bold: []const u8,
    link: struct { text: []const u8, url: []const u8 },
    image: struct { alt: []const u8, src: []const u8 },
};

const InlineParseResult = struct { token: InlineToken, new_i: usize };

/// Flush accumulated text buffer as an InlineToken.text
fn flushInlineText(alloc: std.mem.Allocator, out_tokens: *std.ArrayListUnmanaged(InlineToken), text_buf: *std.ArrayListUnmanaged(u8)) !void {
    if (text_buf.items.len == 0) return;
    var text_opt: ?[]const u8 = try text_buf.toOwnedSlice(alloc);
    errdefer if (text_opt) |value| alloc.free(value);
    try out_tokens.append(alloc, .{ .text = text_opt.? });
    text_opt = null;
    text_buf.clearRetainingCapacity();
}

fn parseImageToken(allocator: std.mem.Allocator, text: []const u8, start: usize) !?InlineParseResult {
    var i = start + 2;
    const alt_start = i;
    while (i < text.len and text[i] != ']') : (i += 1) {}
    if (i >= text.len or i + 1 >= text.len or text[i + 1] != '(') return null;
    const alt = text[alt_start..i];
    i += 2;
    const src_start = i;
    while (i < text.len and text[i] != ')') : (i += 1) {}
    if (i >= text.len) return null;
    var src_opt: ?[]const u8 = try allocator.dupe(u8, text[src_start..i]);
    errdefer if (src_opt) |s| allocator.free(s);
    var alt_opt: ?[]const u8 = try allocator.dupe(u8, alt);
    errdefer if (alt_opt) |a| allocator.free(a);
    const token = InlineToken{ .image = .{ .alt = alt_opt.?, .src = src_opt.? } };
    src_opt = null;
    alt_opt = null;
    return .{ .token = token, .new_i = i + 1 };
}

fn parseBoldToken(allocator: std.mem.Allocator, text: []const u8, start: usize) !?InlineParseResult {
    var i = start + 2;
    const bold_start = i;
    while (i + 1 < text.len) : (i += 1) {
        if (text[i] == '*' and text[i + 1] == '*') break;
    }
    if (i + 1 >= text.len) return null;
    var bold_opt: ?[]const u8 = try allocator.dupe(u8, text[bold_start..i]);
    errdefer if (bold_opt) |b| allocator.free(b);
    const token = InlineToken{ .bold = bold_opt.? };
    bold_opt = null;
    return .{ .token = token, .new_i = i + 2 };
}

fn parseLinkToken(allocator: std.mem.Allocator, text: []const u8, start: usize) !?InlineParseResult {
    var i = start + 1;
    const text_start = i;
    while (i < text.len and text[i] != ']') : (i += 1) {}
    if (i >= text.len or i + 1 >= text.len or text[i + 1] != '(') return null;
    const link_text = text[text_start..i];
    i += 2;
    const url_start = i;
    while (i < text.len and text[i] != ')') : (i += 1) {}
    if (i >= text.len) return null;
    var url_opt: ?[]const u8 = try allocator.dupe(u8, text[url_start..i]);
    errdefer if (url_opt) |u| allocator.free(u);
    var link_text_opt: ?[]const u8 = try allocator.dupe(u8, link_text);
    errdefer if (link_text_opt) |l| allocator.free(l);
    const token = InlineToken{ .link = .{ .text = link_text_opt.?, .url = url_opt.? } };
    url_opt = null;
    link_text_opt = null;
    return .{ .token = token, .new_i = i + 1 };
}

pub fn parseInlineMarkup(allocator: std.mem.Allocator, text: []const u8) ![]InlineToken {
    const cleanup = @import("cleanup.zig");

    var tokens = std.ArrayListUnmanaged(InlineToken).empty;
    errdefer {
        cleanup.freeInlineTokenPayloads(allocator, tokens.items);
        tokens.deinit(allocator);
    }

    var i: usize = 0;
    var current_text = std.ArrayListUnmanaged(u8).empty;
    defer current_text.deinit(allocator);

    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '!' and text[i + 1] == '[') {
            if (try parseImageToken(allocator, text, i)) |result| {
                try flushInlineText(allocator, &tokens, &current_text);
                try tokens.append(allocator, result.token);
                i = result.new_i;
                continue;
            }
            try current_text.append(allocator, '!');
            try current_text.append(allocator, '[');
            i += 2;
            continue;
        }

        if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
            if (try parseBoldToken(allocator, text, i)) |result| {
                try flushInlineText(allocator, &tokens, &current_text);
                try tokens.append(allocator, result.token);
                i = result.new_i;
            } else {
                try current_text.append(allocator, '*');
                try current_text.append(allocator, '*');
                i += 2;
            }
            continue;
        }

        if (text[i] == '[') {
            if (try parseLinkToken(allocator, text, i)) |result| {
                try flushInlineText(allocator, &tokens, &current_text);
                try tokens.append(allocator, result.token);
                i = result.new_i;
                continue;
            }
            try current_text.append(allocator, '[');
            i += 1;
            continue;
        }

        try current_text.append(allocator, text[i]);
        i += 1;
    }

    try flushInlineText(allocator, &tokens, &current_text);

    return tokens.toOwnedSlice(allocator);
}
