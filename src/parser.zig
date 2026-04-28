const std = @import("std");
pub const NoteAtom = @import("core/types.zig").NoteAtom;

pub const Token = union(enum) {
    heading: struct { level: u8, text: []const u8 },
    paragraph: []const u8,
    quote: []const u8,
    text: []const u8,
    code_block: struct { language: []const u8, code: []const u8 },
    horizontal_rule: void,
};

pub const ImageResolver = struct {
    ctx: *anyopaque,
    resolve: *const fn (ctx: *anyopaque, source: []const u8, alt: []const u8) anyerror![]const u8,
};

pub const InlineToken = union(enum) {
    text: []const u8,
    bold: []const u8,
    link: struct { text: []const u8, url: []const u8 },
    image: struct { alt: []const u8, src: []const u8 },
};

pub const BlockWrapper = enum {
    paragraph,
    quote,
};

fn flushParagraph(allocator: std.mem.Allocator, current_para: *std.ArrayListUnmanaged(u8), tokens: *std.ArrayListUnmanaged(Token)) !void {
    if (current_para.items.len > 0) {
        try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
        current_para.clearRetainingCapacity();
    }
}

pub fn tokenize(allocator: std.mem.Allocator, content: []const u8) ![]Token {
    var tokens = std.ArrayListUnmanaged(Token).empty;
    errdefer {
        freeTokenPayloads(allocator, tokens.items);
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

/// Flush accumulated text buffer as an InlineToken.text
fn flushInlineText(alloc: std.mem.Allocator, out_tokens: *std.ArrayListUnmanaged(InlineToken), text_buf: *std.ArrayListUnmanaged(u8)) !void {
    if (text_buf.items.len == 0) return;
    var text_opt: ?[]const u8 = try text_buf.toOwnedSlice(alloc);
    errdefer if (text_opt) |value| alloc.free(value);
    try out_tokens.append(alloc, .{ .text = text_opt.? });
    text_opt = null;
    text_buf.clearRetainingCapacity();
}

const InlineParseResult = struct { token: InlineToken, new_i: usize };

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

fn parseInlineMarkup(allocator: std.mem.Allocator, text: []const u8) ![]InlineToken {
    var tokens = std.ArrayListUnmanaged(InlineToken).empty;
    errdefer {
        freeInlineTokenPayloads(allocator, tokens.items);
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

pub fn tokensToNoteAtoms(allocator: std.mem.Allocator, tokens: []Token) ![]NoteAtom {
    return try tokensToNoteAtomsWithResolver(allocator, tokens, null);
}

pub fn tokensToNoteAtomsWithResolver(
    allocator: std.mem.Allocator,
    tokens: []Token,
    image_resolver: ?ImageResolver,
) ![]NoteAtom {
    var atoms = std.ArrayListUnmanaged(NoteAtom).empty;
    errdefer {
        freeAtomPayloads(allocator, atoms.items);
        atoms.deinit(allocator);
    }

    for (tokens) |token| {
        switch (token) {
            .heading => |h| {
                try appendInlinePieces(allocator, &atoms, try parseInlineMarkup(allocator, h.text), .paragraph, image_resolver);
            },
            .paragraph => |p| {
                try appendInlinePieces(allocator, &atoms, try parseInlineMarkup(allocator, p), .paragraph, image_resolver);
            },
            .quote => |q| {
                try appendInlinePieces(allocator, &atoms, try parseInlineMarkup(allocator, q), .quote, image_resolver);
            },
            .code_block => |cb| {
                var code_text_opt: ?[]NoteAtom = try allocator.alloc(NoteAtom, 1);
                errdefer if (code_text_opt) |value| allocator.free(value);
                code_text_opt.?[0] = .{ .text = .{ .text = try allocator.dupe(u8, cb.code) } };
                try atoms.append(allocator, .{ .codeblock = .{
                    .attrs = .{ .language = try allocator.dupe(u8, cb.language) },
                    .content = code_text_opt.?,
                } });
                code_text_opt = null;
            },
            .horizontal_rule => {
                try atoms.append(allocator, .{ .horizontal_rule = {} });
            },
            else => {},
        }
    }

    return atoms.toOwnedSlice(allocator);
}

fn appendInlinePieces(
    allocator: std.mem.Allocator,
    atoms: *std.ArrayListUnmanaged(NoteAtom),
    pieces: []InlineToken,
    wrapper: BlockWrapper,
    image_resolver: ?ImageResolver,
) !void {
    defer freeInlineTokens(allocator, pieces);

    var content: std.ArrayListUnmanaged(NoteAtom) = .empty;
    errdefer {
        freeAtomPayloads(allocator, content.items);
        content.deinit(allocator);
    }

    for (pieces) |piece| {
        switch (piece) {
            .text => |text| {
                try appendTextAtom(allocator, &content, try allocator.dupe(u8, text), &[_]NoteAtom.Mark{});
            },
            .bold => |text| {
                var marks_opt: ?[]NoteAtom.Mark = try allocator.alloc(NoteAtom.Mark, 1);
                errdefer if (marks_opt) |marks| allocator.free(marks);
                marks_opt.?[0] = .{ .bold = {} };
                try appendTextAtom(allocator, &content, try allocator.dupe(u8, text), marks_opt.?);
                marks_opt = null;
            },
            .link => |link| {
                var marks_opt: ?[]NoteAtom.Mark = try allocator.alloc(NoteAtom.Mark, 1);
                errdefer if (marks_opt) |marks| allocator.free(marks);
                marks_opt.?[0] = .{ .link = .{ .href = try allocator.dupe(u8, link.url) } };
                try appendTextAtom(allocator, &content, try allocator.dupe(u8, link.text), marks_opt.?);
                marks_opt = null;
            },
            .image => |image| {
                if (content.items.len > 0) {
                    var wrapped_opt: ?[]NoteAtom = try content.toOwnedSlice(allocator);
                    errdefer if (wrapped_opt) |wrapped| freeCollectedAtoms(allocator, wrapped);
                    try appendWrappedBlock(allocator, atoms, wrapper, wrapped_opt.?);
                    wrapped_opt = null;
                }

                const resolver = image_resolver orelse return error.ImageResolverRequired;
                var file_id_opt: ?[]const u8 = try resolver.resolve(resolver.ctx, image.src, image.alt);
                errdefer if (file_id_opt) |file_id| allocator.free(file_id);
                var alt_opt: ?[]const u8 = try allocator.dupe(u8, image.alt);
                errdefer if (alt_opt) |alt| allocator.free(alt);
                try atoms.append(allocator, .{ .image = .{
                    .attrs = .{
                        .uuid = file_id_opt.?,
                        .alt = alt_opt.?,
                        .@"align" = "",
                    },
                } });
                file_id_opt = null;
                alt_opt = null;
            },
        }
    }

    if (content.items.len > 0) {
        var wrapped_opt: ?[]NoteAtom = try content.toOwnedSlice(allocator);
        errdefer if (wrapped_opt) |wrapped| freeCollectedAtoms(allocator, wrapped);
        try appendWrappedBlock(allocator, atoms, wrapper, wrapped_opt.?);
        wrapped_opt = null;
    }
}

/// Takes ownership of `text` — caller must not free it after this call.
fn appendTextAtom(
    allocator: std.mem.Allocator,
    content: *std.ArrayListUnmanaged(NoteAtom),
    text: []const u8,
    marks: []NoteAtom.Mark,
) !void {
    errdefer allocator.free(text);

    try content.append(allocator, .{ .text = .{
        .text = text,
        .marks = marks,
    } });
}

fn appendWrappedBlock(
    allocator: std.mem.Allocator,
    atoms: *std.ArrayListUnmanaged(NoteAtom),
    wrapper: BlockWrapper,
    content: []NoteAtom,
) !void {
    switch (wrapper) {
        .paragraph => try atoms.append(allocator, .{ .paragraph = .{ .content = content } }),
        .quote => {
            var quote_content: ?[]NoteAtom = try allocator.alloc(NoteAtom, 1);
            errdefer if (quote_content) |value| allocator.free(value);
            quote_content.?[0] = .{ .paragraph = .{ .content = content } };
            try atoms.append(allocator, .{ .quote = .{ .content = quote_content.? } });
            quote_content = null;
        },
    }
}

fn freeCollectedAtoms(allocator: std.mem.Allocator, atoms: []NoteAtom) void {
    freeAtomPayloads(allocator, atoms);
    allocator.free(atoms);
}

fn freeAtomPayloads(allocator: std.mem.Allocator, atoms: []NoteAtom) void {
    for (atoms) |atom| {
        atom.deinit(allocator);
    }
}

pub fn freeTokenPayloads(allocator: std.mem.Allocator, tokens: []Token) void {
    for (tokens) |token| {
        switch (token) {
            .heading => |h| allocator.free(h.text),
            .paragraph => |p| allocator.free(p),
            .quote => |q| allocator.free(q),
            .code_block => |cb| {
                allocator.free(cb.language);
                allocator.free(cb.code);
            },
            else => {},
        }
    }
}

fn freeInlineTokens(allocator: std.mem.Allocator, tokens: []InlineToken) void {
    freeInlineTokenPayloads(allocator, tokens);
    allocator.free(tokens);
}

fn freeInlineTokenPayloads(allocator: std.mem.Allocator, tokens: []InlineToken) void {
    for (tokens) |token| {
        switch (token) {
            .text => |text| allocator.free(text),
            .bold => |text| allocator.free(text),
            .link => |link| {
                allocator.free(link.text);
                allocator.free(link.url);
            },
            .image => |image| {
                allocator.free(image.alt);
                allocator.free(image.src);
            },
        }
    }
}
