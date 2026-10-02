# AGENTS.md — Mindustry Visual Logic

## Project identity

Godot 4.x application (GL Compatibility renderer, not Vulkan). Visual block-based logic editor for Mindustry. Open `project.godot` in the Godot editor. No npm, pip, make, or other build tools apply.

## Key commands

- **LSP**: `godot --headless --editor --lsp-server` (configured in `opencode.json`)
- **Run**: `godot --path /home/ylxc/Projects/Godot/mindustry-visual-logic`, or F5 in the editor
- **Export**: via editor UI only — `export_presets.cfg` is gitignored
- **Headless 冒烟**: `godot --headless --path . --quit-after 60` —— 加载主场景跑若干帧，能捕到脚本解析/运行期错误
- **No tests, no CI, no linter** — do not attempt to run any

## Directory layout

```
srcs/
├── model/                      ← 纯数据层（无 Node、无控件，可序列化、可撤销）
│   ├── logic_node.gd           ← LogicNode：类型 + 字段值 + 各槽位的有序子节点 id
│   ├── logic_graph.gd          ← LogicGraph：画布上的若干条链；容器 = (owner_id, slot_id)
│   ├── graph_history.gd        ← 快照式撤销/重做
│   └── graph_serializer.gd     ← JSON 存盘/读盘
├── defs/                       ← 定义层（块定义的类型化对象）
│   ├── block_def.gd            ← BlockDef：元素、导出模板、事件、行为脚本
│   ├── element_def.gd          ← ElementDef / Visibility / OptionItem
│   ├── export_part.gd          ← ExportPart：字面量 / 取字段 / 首个可见
│   ├── action_def.gd           ← ActionDef：声明式事件（<Event>）
│   ├── block_library.gd        ← XML → BlockDef（不认识具体元素种类）
│   ├── element_registry.gd     ← 元素种类 → 构建器
│   └── selector_data.gd        ← 选择器候选（读 blocks/selectors/*.json）
├── view/                       ← 视图层（只渲染与交互，不持有拓扑真相）
│   ├── block_view.gd           ← BlockView：一个块的控件、几何度量、背景绘制
│   ├── editor_canvas.gd        ← EditorCanvas：图 + 撤销栈 + 视图集合 + 布局求解
│   ├── layout_solver.gd        ← 纯函数布局求解（自底向上量、自顶向下摆、产出吸附锚点）
│   ├── block_metrics.gd        ← 块几何契约（尺寸/尾锚点/槽位锚点）
│   ├── layout_result.gd        ← 求解结果（矩形表 + 锚点表）
│   ├── editor_camera.gd        ← 相机：滚轮缩放 + 空白处左键平移
│   ├── drag_controller.gd      ← 拖拽会话（调色板出块 / 画布内搬移 / 落地）
│   ├── drag_overlay.gd         ← 吸附提示线与高亮
│   ├── selector_panel.gd       ← 单位/传感器选择器浮层
│   └── elements/
│       └── element_builders.gd ← 内置元素构建器 + 注册
├── controls/
│   ├── notice_window.tscn      ← 公告弹窗（textdb.online）
│   └── notice_item.tscn
├── scenes/
│   ├── editor.tscn             ← 编辑器标签页（脚本已外置，不再内嵌 GDScript）
│   └── main.tscn               ← 应用入口
└── scripts/
    ├── main.gd                 ← @tool，顶层 UI + 菜单 + 光标
    └── editor.gd               ← 标签页拼装：调色板 + 画布 + 拖拽 + 选择器

blocks/{locale}/*.xml           ← 块定义
blocks/selectors/*.json         ← 选择器候选（units / sensors）
assets/
├── fonts/
├── sprites/cursors/           ← custom mouse cursors
├── sprites/previews/          ← block/item/unit sprite previews
└── styles/main_theme.tres     ← main app theme
```

## Architecture

### 三层分离（重构定稿）

- **model 不知道视图**：`LogicGraph` 里只有「谁是谁的子节点、字段是什么值、每条链摆在画布什么位置」，
  没有控件、没有绝对坐标递归。容器统一表示为 `(owner_id, slot_id)`，成员是**有序数组**，
  顺序即数组下标，空位就是不存在 —— 没有 `_next_block`/`_last_block` 双向指针，也没有用 `null` 占位的字典项。
- **defs 不知道视图**：`BlockLibrary` 把 XML 解析成有类型的 `BlockDef`，且**不认识具体元素种类**；
  「怎么建控件、怎么读值」由 `ElementRegistry` 里的构建器决定（内置的放在 `view/elements/`）。
- **view 从数据推导**：`BlockView` 是 `Control`（不是 `Container`），行位置自己给；
  尺寸由 `measure(slot_extents) -> BlockMetrics` 主动算出，位置由 `LayoutSolver.solve()` 统一求解。
  **位置绝不从绘制缓存反读**；块与块之间也没有父子关系，嵌套只体现在位置上。

### 一次改动的数据流

1. 用户改控件 → `BlockView.commit_field()` → `EditorCanvas` 用 `GraphHistory.record()` 包住 `LogicGraph.set_field()`；
2. 图发出 `structure_changed` / `field_changed` / `reset` → 画布同步视图集合并重新求解布局；
3. 拖拽：`BlockView.drag_requested` → `DragController` 建幽灵（或移动被拖块及其子树）→
   每帧向画布要 `find_anchor()` 并在 `DragOverlay` 上高亮 → 松手才产生一条撤销记录。
   拖到画布外松手 = 取消，**不会删除任何数据**。

### 块定义格式（`blocks/{locale}/*.xml`）

布局与可见性都用**条件**表达，逻辑运算符只有三个：

| 写法 | 含义 |
|---|---|
| `when="mode=clear"` | 相等（`!=` 表示不等） |
| `when="mode=clear|color"` | 同一字段的多取值（`|` 右边是裸取值时沿用左边的字段） |
| `when="mode=poly|image & txt=true"` | `&` 与 |
| `when="~(mode=col & txt=true)"` | `~` 非、括号 |
| `when="find=building & group=enemy"` | 多个字段共同决定 |

字段必须显式写（没有"默认字段"）；`&&` `||` `!` `and` `or` `not` 会被明确拒绝并提示改法。
拼错字段或取值会在解析时报出来 —— 旧 `show` 白名单是静默失效的。

```xml
<Block name="Print" export="print {content}">
  <Export when="txt=true">print "{content}"</Export>   <!-- 条件化导出模板，第一个成立的优先 -->
  <Export when="txt=false">print {content}</Export>
  <Row>                                                <!-- 显式分行（取代 <Br/>） -->
    <Text id="T1">Print</Text>
    <Text id="T2" when="txt=true">"</Text>             <!-- 元素自己的生效条件 -->
    <LineBox id="content" placeholder="frog" />
    <Text id="T3" when="txt=true">"</Text>
    <Button id="txt" text="TXT" />
  </Row>
</Block>
```

- **导出模板**：模板就是"mlog 那一行长什么样" —— 字面量照原样写（可含空格与引号），
  取值用 `{字段}`，`{a|b|c}` 取第一个**此刻生效**的字段（都不可用时输出 `0`），
  需要字面大括号写 `{{` `}}`。默认模板写 `export="…"`，条件化的写 `<Export when="…">…</Export>`。
- **行**：`<Row [when]>` 显式分行；条件不成立的行**整行不参与布局**（不占位置、不绘制）。
  `<Group when="…">` 给一串连续元素共享条件（不换行，解析时并入元素条件）。
- **元素**：`<Text>` / `<LineBox placeholder>` / `<Option>`+`<Item [value]>` / `<Button text>` / `<Selector kind>` / `<Nest>`；
  条件不成立的元素既不占位置也不显示，但控件不重建（输入焦点不会被打断）。
- **选择器**：`<Selector id="unit" kind="units" />`，候选取自 `blocks/selectors/{kind}.json`。
- **事件**：`<Event on="field_changed" field="v"><SetField id="x" value="0" /><SetVisible ids="T1 T2" /></Event>`；
  更复杂的交互用 `<Script path="res://…gd" />` 挂行为脚本。
- **`<Item value="33">!</Item>`**：显示值与导出值可以不同（PrintChar 是显示字符、导出字符码）。
- **旧写法仍会被解析，但已无人使用**：`<Item show="A B">` / `<Br/>` / `<Pressed>`/`<Released>` /
  `export="draw %a|b"` 旧占位符 / 结构化 `<Literal>`/`<Field>`/`<FirstOf>` 段落。
  它们在解析时一律翻译成上面的条件与模板，所以内部只有一种机制；改块定义时不要再用。
- **改格式时的安全做法**：先 dump 一遍行为快照（每个字段组合的生效元素集合 + 导出结果），
  改完再 dump 比对 —— 官方迁移就是这么做的（见 git 历史），它抓出过三个"解析零警告但行为已变"的 bug。

### 扩展点

- 新增元素类型：在 `view/elements/element_builders.gd` 里加一个构建器并注册，**只改这一处**；解析器与 `BlockView` 都不用动。
- 新增块：往 XML 里加 `<Block>`，不需要写 GDScript。
- 新增选择器候选：改 `blocks/selectors/*.json`。
- **导出处理（模板表达不了时）**：给块挂行为脚本 `<Block name="X" script="res://…gd">`，
  脚本是 `RefCounted`，按需实现两个钩子：
  - `export_line(node, def, render, context) -> Variant`：返回字符串就接管这一行（可含 `\n` 输出多行）；
    `render.call()` 是模板渲染结果，所以能只做后处理（`render.call() + " always"`）；
    返回 `null` 表示"用模板" —— 常见情况不必自己拼字符串。
  - `pre_export(node, context) -> void`：整图导出前按遍历顺序每个块调一次，
    `context["scratch"]` 可以放整图级别的信息（例如给 `If` 分配跳转标签、统计指令数）。
  两个钩子都不改变"数据层是唯一真相"：导出仍然只读 `LogicGraph`，不碰控件。

### Other

- **`@tool`**：`main.gd` 在编辑器里也会跑。
- **`class_name`**：模型/定义/视图三层的类都全局注册。
- **公告窗**：`notice_window.tscn` 通过 HTTPRequest 拉 `https://textdb.online/MindVisualLogic`。
- **自定义光标**：`main.gd._ready()` 从 `assets/sprites/cursors/` 装载。

## Conventions and gotchas

- **`old/` 是 gitignored 的旧版实现**：只作行为对照（块清单、导出顺序、默认值、选择器候选都从它提取过），
  不要修改。它的内部资源路径（`res://Blocks/…`）已失效，不能就地运行。
- **`build/` 与 `export_presets.cfg` 是 gitignored**。
- **只用 GDScript**。
- **XML 块文件是块定义的唯一来源** —— 改块就是改 XML，不要改 GDScript。
- **改模型/视图后跑一次 headless 冒烟**：`godot --headless --path . --quit-after 60`。
- **GDScript 的 lambda 按值捕获**：不要在闭包里给外部变量赋值再读它（撤销栈的记录就踩过这个坑）。
- **撤销/读档会整体替换图**：`LogicGraph.load_dict()` 复用同 id 的节点对象，外部引用不会失联，
  但仍应在 `reset` 之后重新取节点。
