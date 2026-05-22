# AGENTS.md

## Setup / Run
Open in Godot 4.6 Editor. Press F5 (or click "Run Project") to launch.
No CLI commands — there is no package manager, no build script, no lint, no test runner.

## Architecture
- `project.godot` → `Scenes/main.tscn` (script `Scripts/main.gd`) → tabs of `Scenes/editor.tscn`
- Each editor tab (`Scripts/editor.gd`) has a block palette sidebar + a SubViewport canvas
- `BaseBlock` (`Controls/Blocks/base.gd`) is the abstract block class; `CSBlock` extends it with `@export_multiline var template`
- `Scripts/block_data.gd` stores all 41 block definitions, shared constant arrays, and category color map

## Block DSL (template system)
`BaseBlock.parsing()` interprets a custom mini-language. Lines separated by `\n`, tokens by spaces.
Tokens are `%type.id` where `id` indexes into the `options` dictionary.

| Token | Widget | `options[id]` shape |
|-------|--------|---------------------|
| `%in.id` | `LineEdit` | `{ placeholder = "…" }` (optional; falls back to `id`) |
| `%bu.id` | `Button` | `{ text = "…", pressed = Callable }` |
| `%op.id` | `OptionButton` | `{ items = [...], changed = Callable }` |
| `%li` | nested `VBoxContainer` (no `id`) | — |
| plain text | `Label` | — |

## Block drag
- `BaseBlock._gui_input()` handles left-click drag, emits `block_drag_started` signal
- SubViewport must have `handle_input_locally = true` for GUI events to reach blocks
- Camera2D script listens for `block_drag_started` via `child_entered_tree` to stop panning during drag

## Rendering / Graphics
- **GL Compatibility** renderer only (`project.godot` `rendering/rendering_method`)
- Blocks draw rounded-rect rows via `draw_style_box()` with `StyleBoxFlat` (corners configurable per row position)
- Button style overrides (`normal`/`hover`/`pressed`) use `_btn_style()` based on `bg_color`
- Custom pixel cursors registered in `main.gd#_ready()` from `Sprites/Cursor/`
- Themes in `Stytes/`: `main_theme.tres` (general UI), `block.tres` (block widgets)
- Category colors defined in `Scripts/block_data.gd#COLORS`

## Active refactoring
The `refactor-editor` branch is replacing the old `LogicBlocks`-based system.
- **Active code**: `Controls/Blocks/`, `Scripts/`, `Scenes/`
- **Deprecated**: `old/` directory is gitignored — ignore it for all new work

## Conventions
- `.gd` for scripts, `.tscn` for scenes, `.tres` for resources
- LF line endings enforced via `.gitattributes`
- `@tool` scripts run in the editor (`main.gd`, `block_adder.tscn`, sort_children inline script)
- `##` doc comments on functions, `#` inline comments
