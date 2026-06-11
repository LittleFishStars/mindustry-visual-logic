# AGENTS.md — Mindustry Visual Logic

## Project identity

Godot 4.x application (GL Compatibility renderer, not Vulkan). Visual block-based logic editor for Mindustry. Open `project.godot` in the Godot editor. No npm, pip, make, or other build tools apply.

## Key commands

- **LSP**: `godot --headless --editor --lsp-server` (configured in `opencode.json`)
- **Run**: `godot --path /home/ylxc/File/Project/Godot/mindustry-visual-logic`, or F5 in the editor
- **Export**: via editor UI only — `export_presets.cfg` is gitignored
- **No tests, no CI, no linter** — do not attempt to run any

## Directory layout

```
srcs/                          ← all current source code
├── controls/block.gd          ← Block (extends Container, renders a logic block)
├── controls/notice_*.tscn     ← notice popup window
├── scenes/editor.tscn         ← editor workspace (3 embedded GDScripts)
├── scenes/main.tscn           ← app entry point
└── scripts/
    ├── main.gd                ← @tool, top-level UI + menu + cursors
    ├── editor.gd               ← palette builder, category switcher
    ├── block_parse.gd          ← XML parser (assets/blocks/*.xml → Dictionary)
    └── block_data.gd           ← LEGACY: old template-based block definitions

assets/
├── blocks/*.xml               ← block definitions (41 blocks across 5 files)
├── fonts/
├── sprites/cursors/           ← custom mouse cursors (7 shapes)
├── sprites/previews/          ← block/item/unit sprite previews
└── styles/main_theme.tres     ← main app theme
```

## Architecture

### Block definition system (XML-based)

Blocks are defined in `assets/blocks/*.xml` — one file per category. The format:

```xml
<Kind name="Controls" color="#A15800">
  <Block name="Control" export="control %mode %block %index|x|unit %y|shootp %shoot 0">
    <Text id="T1">Control</Text>
    <Option id="mode" default="0">
      <Item show="T1 mode T2 block T3 index">enabled</Item>   ← only these IDs visible
      <Item show="T1 mode T2 block T4 x T5 y T7 shoot">shoot</Item>
    </Option>
    <Text id="T2">of</Text>
    <LineBox id="block" placeholder="block1" />
    <Br />                    ← line break (new row)
    <Nest id="nest" />        ← nested VBoxContainer (for If block body)
  </Block>
</Kind>
```

Element types: `Text` (Label), `LineBox` (LineEdit), `Option` + `Item` (OptionButton), `Button` + `Pressed`/`Released` (toggle button), `Br` (new row), `Nest` (indented child container).

**`show` attribute**: On `<Item>`, lists IDs visible for that option. On `<Pressed>`/`<Released>`, lists IDs visible per button toggle state. If absent, all elements are visible (layout unchanged by selection).

**`export` attribute**: Pipe syntax `%id1|id2` means "use value from the first visible ID". Literal text is output directly (e.g., ` 0`). Empty string means no mlog output.

### Parsing

`BlockParse` (class_name) in `srcs/scripts/block_parse.gd`:
- `BlockParse.new().parse()` → scans `assets/blocks/*.xml`, returns Dictionary
- Structure: `{"Controls": {"color": Color, "blocks": {"Drawflush": {export:..., elements:[...]}, ...}}, ...}`
- Called once in `editor.gd._ready()`, result stored in `_block_data`

### Block rendering

`Block` (class_name) in `srcs/controls/block.gd`, extends `Container`:
- `_init(block_data: Dictionary, p_color: Color)` — takes parsed XML data dict directly
- `_build_elements()` — traverses `elements` list, creates all `Text`/`LineBox`/`Option`/`Button`/`Br`/`Nest` controls
- Visibility: all elements created once, toggled `visible` by `_apply_visibility()` (Option show ∩ Button state show)
- `_export() → String` — resolves pipe syntax to mlog command string
- Drag signals: `drag_started(offset)`, `drag_ended`, `drag_moved(pos)`
- Style: procedural `StyleBoxFlat` per row with rounded corners and shadows

### Drag system

`Dragger` (embedded GDScript on a `Node` child of editor root in `editor.tscn`):
- `start_drag(offset, node, copy)` — creates block copy (palette) or reparents existing block, attaches to Dragger
- `_input(event)` — global mouse tracking during drag (not `_gui_input`, so works outside any control bounds)
- Drop: removes from Dragger, converts screen → world coordinates via `_screen_to_world()`, adds to `nSpace` SubViewport
- EditSpace script (`extends SubViewport`) connects `drag_started` to Camera's `stop_moving()` on block enter

### Camera

Embedded script on Camera2D in `editor.tscn`: `_input()` handles scroll-zoom (×1.1) and left-click pan. `stop_moving()` stops pan during block drag.

### Other

- **`@tool`**: `main.gd` runs in the editor. `_ready` fires on scene changes.
- **`class_name`**: `Block`, `BlockData`, `BlockParse` are globally registered.
- **`block_data.gd`**: Legacy data source with old template-based `BLOCKS` dictionary. Not used by current rendering path; kept for reference.
- **Notice window**: `notice_window.tscn` fetches from `https://textdb.online/MindVisualLogic` via HTTPRequest.
- **Custom cursors**: Loaded from `res://assets/sprites/cursors/` in `main.gd._ready()`.

## Conventions and gotchas

- **`old/` is gitignored** — legacy code, do not modify or reference.
- **`build/` and `export_presets.cfg` are gitignored** — do not expect these.
- **`assets/styles/`** (not Stytes) — theme dir typo was fixed in the rewrite.
- **GDScript is the only language** — no C#, Rust, or other.
- **XML block files are the source of truth** — editing a block means updating the XML, not GDScript.
