const std = @import("std");
const parser = @import("parser");
const NoteAtom = parser.NoteAtom;
const testing = std.testing;

test "tokenize heading" {
    const allocator = testing.allocator;
    const content = "# Hello World";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .heading);
    try testing.expectEqual(@as(u8, 1), tokens[0].heading.level);
    try testing.expectEqualStrings("Hello World", tokens[0].heading.text);
}

test "tokenize multiple headings" {
    const allocator = testing.allocator;
    const content =
        \\# Heading 1
        \\## Heading 2
        \\### Heading 3
    ;

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 3), tokens.len);
    try testing.expectEqual(@as(u8, 1), tokens[0].heading.level);
    try testing.expectEqual(@as(u8, 2), tokens[1].heading.level);
    try testing.expectEqual(@as(u8, 3), tokens[2].heading.level);
}

test "tokenize paragraph" {
    const allocator = testing.allocator;
    const content = "This is a simple paragraph.";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .paragraph);
}

test "tokenize bold text" {
    const allocator = testing.allocator;
    const content = "This is **bold** text.";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expect(tokens.len > 0);
    // Bold should be detected in the paragraph
}

test "tokenize link" {
    const allocator = testing.allocator;
    const content = "Check [this link](https://example.com) out.";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expect(tokens.len > 0);
}

test "tokenize quote" {
    const allocator = testing.allocator;
    const content = "> This is a quote";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .quote);
}

test "tokenize code block" {
    const allocator = testing.allocator;
    const content =
        \\```zig
        \\const x = 42;
        \\```
    ;

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .code_block);
    try testing.expectEqualStrings("zig", tokens[0].code_block.language);
}

test "tokenize horizontal rule" {
    const allocator = testing.allocator;
    const content = "---";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .horizontal_rule);
}

test "tokenize empty content" {
    const allocator = testing.allocator;
    const content = "";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 0), tokens.len);
}

const TestImageResolver = struct {
    allocator: std.mem.Allocator,

    fn parserResolver(self: *TestImageResolver) parser.ImageResolver {
        return .{
            .ctx = self,
            .resolve = resolveThunk,
        };
    }

    fn resolveThunk(ctx: *anyopaque, source: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *TestImageResolver = @ptrCast(@alignCast(ctx));
        return try self.resolve(source);
    }

    fn resolve(self: *TestImageResolver, source: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "file-id:{s}", .{source});
    }
};

test "tokensToNoteAtomsWithResolver splits inline image into block image node" {
    const allocator = testing.allocator;
    const content = "hello ![alt text](img.png) world";

    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }

    var resolver = TestImageResolver{ .allocator = allocator };
    const atoms = try parser.tokensToNoteAtomsWithResolver(allocator, tokens, resolver.parserResolver());
    defer freeAtoms(allocator, atoms);

    try testing.expectEqual(@as(usize, 3), atoms.len);
    try testing.expect(atoms[0] == .paragraph);
    try testing.expect(atoms[1] == .image);
    try testing.expect(atoms[2] == .paragraph);
    try testing.expectEqualStrings("alt text", atoms[1].image.attrs.alt);
    try testing.expectEqualStrings("file-id:img.png", atoms[1].image.attrs.uuid);
}

test "image note atom serializes to JSON" {
    const allocator = testing.allocator;

    const atom = NoteAtom{
        .image = .{
            .attrs = .{
                .uuid = "file-id-123",
                .alt = "caption",
                .@"align" = "center",
            },
        },
    };

    const json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(atom, .{})});
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"type\":\"image\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"uuid\":\"file-id-123\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"alt\":\"caption\"") != null);
}

fn freeAtoms(allocator: std.mem.Allocator, atoms: []NoteAtom) void {
    for (atoms) |atom| {
        atom.deinit(allocator);
    }
    allocator.free(atoms);
}

test "unclosed image syntax preserved as text" {
    const allocator = testing.allocator;
    const tokens = try parser.tokenize(allocator, "hello ![alt](incomplete");
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }
    try testing.expectEqual(@as(usize, 1), tokens.len);
    // The unclosed image syntax should be preserved as paragraph text
    try testing.expect(tokens[0] == .paragraph);
}

test "unclosed bold preserved as text" {
    const allocator = testing.allocator;
    const tokens = try parser.tokenize(allocator, "hello **unclosed bold");
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }
    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .paragraph);
}

test "unclosed link preserved as text" {
    const allocator = testing.allocator;
    const tokens = try parser.tokenize(allocator, "hello [text](incomplete");
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }
    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .paragraph);
}

test "empty image alt and src" {
    const allocator = testing.allocator;
    const content = "![]()";
    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }
    try testing.expectEqual(@as(usize, 1), tokens.len);
}

test "consecutive images" {
    const allocator = testing.allocator;
    const content = "![a](1.png)![b](2.png)";
    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }
    try testing.expectEqual(@as(usize, 1), tokens.len);
    // Both images are inline in one paragraph
}

test "unclosed code block preserved as paragraph" {
    const allocator = testing.allocator;
    const content = "```js\nconsole.log('hi');";
    const tokens = try parser.tokenize(allocator, content);
    defer {
        parser.freeTokenPayloads(allocator, tokens);
        allocator.free(tokens);
    }
    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expect(tokens[0] == .paragraph);
}
