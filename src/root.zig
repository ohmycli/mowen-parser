const std = @import("std");
const parser = @import("parser.zig");
const types = @import("core/types.zig");

/// Markdown AST node type used by the Mowen platform.
pub const NoteAtom = types.NoteAtom;

/// Lexer token produced by `tokenize`.
pub const Token = parser.Token;

/// Inline-level token (text, bold, link, image).
pub const InlineToken = parser.InlineToken;

/// Callback interface for resolving image sources to file IDs.
pub const ImageResolver = parser.ImageResolver;

/// Tokenize markdown content into a flat token array.
/// Caller owns the returned slice and must free it (or use `parseArena`).
pub const tokenize = parser.tokenize;

/// Convert tokens to NoteAtom array (images skipped).
pub const tokensToNoteAtoms = parser.tokensToNoteAtoms;

/// Convert tokens to NoteAtom array with image resolver.
pub const tokensToNoteAtomsWithResolver = parser.tokensToNoteAtomsWithResolver;

/// Free the payloads inside a token slice (caller still owns the slice itself).
pub const freeTokenPayloads = parser.freeTokenPayloads;

/// One-step: markdown string → NoteAtom doc node.
pub fn convert(allocator: std.mem.Allocator, markdown: []const u8) !NoteAtom {
    return try convertWithResolver(allocator, markdown, null);
}

/// One-step with image resolver.
pub fn convertWithResolver(
    allocator: std.mem.Allocator,
    markdown: []const u8,
    image_resolver: ?ImageResolver,
) !NoteAtom {
    const tokens = try tokenize(allocator, markdown);
    defer {
        freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    const atoms = try tokensToNoteAtomsWithResolver(allocator, tokens, image_resolver);

    return NoteAtom{ .doc = .{ .content = atoms } };
}

/// Arena-based parsing result. Call `deinit()` to free everything at once.
pub const ParseResult = struct {
    arena: std.heap.ArenaAllocator,
    atoms: []NoteAtom,

    pub fn deinit(self: *ParseResult) void {
        self.arena.deinit();
    }
};

/// Parse markdown and return all atoms in an arena.
/// No manual free needed — just call `result.deinit()`.
pub fn parse(backing_allocator: std.mem.Allocator, markdown: []const u8) !ParseResult {
    return parseWithResolver(backing_allocator, markdown, null);
}

/// Parse markdown with image resolver, arena-managed.
pub fn parseWithResolver(backing_allocator: std.mem.Allocator, markdown: []const u8, image_resolver: ?ImageResolver) !ParseResult {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const tokens = try tokenize(a, markdown);
    const atoms = try tokensToNoteAtomsWithResolver(a, tokens, image_resolver);

    return .{ .arena = arena, .atoms = atoms };
}

test {
    std.testing.refAllDecls(@This());
}

test "parse arena API" {
    var result = try parse(std.testing.allocator, "# Hello\n\nWorld");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.atoms.len);
}
