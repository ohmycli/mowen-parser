const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const inline_parser = @import("inline_parser.zig");
const cleanup = @import("cleanup.zig");
const types = @import("core/types.zig");

const Token = tokenizer.Token;
const InlineToken = inline_parser.InlineToken;
const NoteAtom = types.NoteAtom;

pub const ImageResolver = struct {
    ctx: *anyopaque,
    resolve: *const fn (ctx: *anyopaque, source: []const u8, alt: []const u8) anyerror![]const u8,
};

pub const BlockWrapper = enum {
    paragraph,
    quote,
};

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
        cleanup.freeAtomPayloads(allocator, atoms.items);
        atoms.deinit(allocator);
    }

    for (tokens) |token| {
        switch (token) {
            .heading => |h| {
                try appendInlinePieces(allocator, &atoms, try inline_parser.parseInlineMarkup(allocator, h.text), .paragraph, image_resolver);
            },
            .paragraph => |p| {
                try appendInlinePieces(allocator, &atoms, try inline_parser.parseInlineMarkup(allocator, p), .paragraph, image_resolver);
            },
            .quote => |q| {
                try appendInlinePieces(allocator, &atoms, try inline_parser.parseInlineMarkup(allocator, q), .quote, image_resolver);
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
    defer cleanup.freeInlineTokens(allocator, pieces);

    var content: std.ArrayListUnmanaged(NoteAtom) = .empty;
    errdefer {
        cleanup.freeAtomPayloads(allocator, content.items);
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
                    errdefer if (wrapped_opt) |wrapped| cleanup.freeCollectedAtoms(allocator, wrapped);
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
        errdefer if (wrapped_opt) |wrapped| cleanup.freeCollectedAtoms(allocator, wrapped);
        try appendWrappedBlock(allocator, atoms, wrapper, wrapped_opt.?);
        wrapped_opt = null;
    }
}

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
