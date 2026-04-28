中文 | [English](README.md)

# mowen-parser

Zig 库，将 Markdown 转换为[墨问](https://mowen.app)平台的 `NoteAtom` AST 结构。

被 [mowen-cli](https://github.com/ohmycli/mowen-cli) 和 [mowen-wasm](https://github.com/ohmycli/mowen-wasm) 使用。

## 支持的语法

- 标题（`# ~ ######`）
- 段落
- 加粗（`**text**`）
- 链接（`[text](url)`）
- 图片（`![alt](src)`）
- 引用（`>`）
- 代码块（围栏式 `` ``` ``）
- 分割线（`---`）

## 使用方式

在 `build.zig.zon` 中添加依赖：

```zig
.@"mowen-parser" = .{
    .url = "https://github.com/ohmycli/mowen-parser/archive/<COMMIT>.tar.gz",
    .hash = "<HASH>",
},
```

在 `build.zig` 中引入模块：

```zig
const parser_dep = b.dependency("mowen-parser", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("mowen-parser", parser_dep.module("mowen-parser"));
```

### 快速上手

```zig
const mowen = @import("mowen-parser");

// 一步到位：Markdown → NoteAtom 文档节点
const doc = try mowen.convert(allocator, "# Hello\n\nWorld");

// Arena 模式：无需手动释放
var result = try mowen.parse(allocator, "# Hello\n\nWorld");
defer result.deinit();
// result.atoms 是 []NoteAtom
```

## 构建与测试

```bash
zig build
zig build test
```

## 环境要求

- Zig 0.16.0+

## 许可证

MIT
