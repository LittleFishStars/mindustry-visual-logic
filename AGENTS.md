# AGENTS.md — Mindustry Visual Logic

## Project identity

Godot 4.x application (GL Compatibility renderer, not Vulkan). Visual block-based logic editor for Mindustry. Open `project.godot` in the Godot editor. No npm, pip, make, or other build tools apply.

## Key commands

- **LSP**: `godot --headless --editor --lsp-server` (configured in `opencode.json`)
- **Run**: `godot --path /home/ylxc/File/Project/Godot/mindustry-visual-logic`, or F5 in the editor
- **Export**: via editor UI only — `export_presets.cfg` is gitignored
- **No tests, no CI, no linter** — do not attempt to run any

## Architecture notes

- **`@tool` scripts**: `Scripts/main.gd` runs in the editor. GDScript `@tool` semantics apply — `_ready` fires on scene changes, not just at startup.
- **`class_name`**: `BaseBlock`, `Block`, and `BlockData` are globally registered via `class_name`. No `preload` needed to reference them.
- **BlockData singleton**: Access via static methods only — `BlockData.kinds()`, `BlockData.blocks()`, `BlockData.get_block(kind, name)`. The inner `BLOCKS` dictionary is the source of truth for all block definitions.
- **Block template DSL**: Templates use custom tokens parsed by `BaseBlock.parsing()`:
  - `%in.id` → LineEdit (input field)
  - `%bu.id` → Button
  - `%op.id` → OptionButton (dropdown)
  - `%li` → nested VBoxContainer (indented branch, e.g. for `If`)
  - Lines split by `\n`, elements by space. Editing a template string incorrectly breaks block rendering.
- **Drag-to-create**: `editor.gd` clones a `Block` from the palette into the `SubViewport` canvas when dropped. Coordinates go through `CanvasTransform.affine_inverse()` for Camera2D offset.

## Conventions and gotchas

- **`Stytes/`** (not `Styles/`) — theme directory name has a typo. The base block loads `res://Stytes/block.tres` at runtime.
- **`old/` is gitignored legacy code** — do not modify or reference it. Current codebase is a rewrite.
- **`build/` and `export_presets.cfg` are gitignored** — do not expect these to be present.
- **Notice window** fetches from `https://textdb.online/MindVisualLogic` via HTTPRequest. This is an expected external dependency.
- **Custom cursors** loaded from `Sprites/Cursor/` in `main.gd` `_ready()`. Cursor paths must stay valid.
- **GDScript is the only language** — do not introduce C#, Rust bindings, or other languages.
