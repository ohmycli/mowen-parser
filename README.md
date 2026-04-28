# mowen-parser

[中文文档](README_CN.md)

Zig library that converts Markdown to [Mowen](https://mowen.app) platform's `NoteAtom` AST.

Used by [mowen-cli](https://github.com/ohmycli/mowen-cli) and [mowen-wasm](https://github.com/ohmycli/mowen-wasm).

## Supported Syntax

- Headings (`# ~ ######`)
- Paragraphs
- Bold (`**text**`)
- Links (`[text](url)`)
- Images (`![alt](src)`)
- Blockquotes (`>`)
- Code blocks (fenced `` ``` ``)
- Horizontal rules (`---`)

## Usage

Add to `build.zig.zon`:

```zig
.@"mowen-parser" = .{
    .url = "https://github.com/ohmycli/mowen-parser/archive/<COMMIT>.tar.gz",
    .hash = "<HASH>",
},
```

Add to `build.zig`:

```zig
const parser_dep = b.dependency("mowen-parser", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("mowen-parser", parser_dep.module("mowen-parser"));
```

### Quick Start

```zig
const mowen = @import("mowen-parser");

// One-step: Markdown → NoteAtom doc node
const doc = try mowen.convert(allocator, "# Hello\n\nWorld");

// Arena-based: no manual free needed
var result = try mowen.parse(allocator, "# Hello\n\nWorld");
defer result.deinit();
// result.atoms is []NoteAtom
```

## Build & Test

```bash
zig build
zig build test
```

## Requirements

- Zig 0.16.0+

## License

MIT
