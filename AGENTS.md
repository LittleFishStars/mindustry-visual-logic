# AGENTS.md

## Project overview
Mindustry Visual Logic (MVL) — a visual logic editor for Mindustry, built in Godot 4.6 (GL Compatibility renderer).

## Developer commands
- **Edit/run**: Open the project in the Godot editor. There is no CLI build, lint, or test command.
- The main scene is `res://Scenes/main.tscn`.

## Architecture
```
Scripts/          # GDScript entry points
  main.gd         # Main container: menu bar, tab management, custom cursors (@tool)
  editor.gd       # Editor page: populates BlockKindList buttons & BlockArea block lists (@onready)
  block_data.gd   # Pure data: all Mindustry logic block definitions (extends RefCounted)
Controls/Blocks/
  base.gd         # BaseBlock — parses template strings into UI rows of LineEdit/Button/OptionButton/Label
  block.gd        # Block extends BaseBlock — looks up kind+name in block_data, passes template
Stytes/           # Godot themes (main_theme.tres, block.tres)
```

## Key conventions
- **Template format**: `block_data.gd` uses a custom DSL where `%in.id` → LineEdit, `%bu.id` → Button, `%op.id` → OptionButton, `%li` → inner VBox. `BaseBlock.parsing()` splits on `\n` for rows and `" "` for elements.
- **@tool**: `main.gd` runs in the editor. Changes to `@tool` scripts can affect the editor itself.
- **Godot files**: Always commit `.import` files alongside assets. `.godot/` is gitignored (editor cache). `.tscn` and `.tres` files use LF line endings (enforced via `.gitattributes`).
- **Custom cursors**: Defined programmatically in `main.gd:_ready()` — not set via the editor.
- **Translation**: `tr()` calls and Chinese comments are used throughout.
- **opencode.json** is gitignored (local LSP config for GDScript).
