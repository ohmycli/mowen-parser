const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const inline_parser = @import("inline_parser.zig");
const types = @import("core/types.zig");

const Token = tokenizer.Token;
const InlineToken = inline_parser.InlineToken;
const NoteAtom = types.NoteAtom;

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

pub fn freeInlineTokens(allocator: std.mem.Allocator, tokens: []InlineToken) void {
    freeInlineTokenPayloads(allocator, tokens);
    allocator.free(tokens);
}

pub fn freeInlineTokenPayloads(allocator: std.mem.Allocator, tokens: []InlineToken) void {
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

pub fn freeAtomPayloads(allocator: std.mem.Allocator, atoms: []NoteAtom) void {
    for (atoms) |atom| {
        atom.deinit(allocator);
    }
}

pub fn freeCollectedAtoms(allocator: std.mem.Allocator, atoms: []NoteAtom) void {
    freeAtomPayloads(allocator, atoms);
    allocator.free(atoms);
}
