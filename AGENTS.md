# AGENTS.md — Mindustry Visual Logic

## Project identity

Godot 4.x application (GL Compatibility renderer, not Vulkan). Visual block-based logic editor for Mindustry. Open `project.godot` in the Godot editor. No npm, pip, make, or other build tools apply.

## Key commands

- **LSP**: `godot --headless --editor --lsp-server` (configured in `opencode.json`)
- **Run**: `godot --path /home/ylxc/Projects/app/mindustry-visual-logic`, or F5 in the editor
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
│   ├── graph_serializer.gd     ← JSON 存盘/读盘
│   └── app_settings.gd         ← 应用设置（帧率/UI 缩放/失焦导出）+ user://settings.json
├── defs/                       ← 定义层（块定义的类型化对象）
│   ├── block_def.gd            ← BlockDef：行/元素、导出模板、默认值、字段与槽位索引
│   ├── element_def.gd          ← ElementDef / OptionItem（各自带生效条件 when）
│   ├── export_part.gd          ← ExportPart：字面量 / 取字段 / 首个可见
│   ├── condition_def.gd        ← ConditionDef：when 的表达式树（求值 + 规范化回写）
│   ├── condition_parser.gd     ← when="…" 的词法/语法解析（只做语法，不校验字段）
│   ├── element_builder.gd      ← ElementBuilder：一种元素种类的行为契约
│   ├── block_library.gd        ← XML → BlockDef（不认识具体元素种类）
│   ├── element_registry.gd     ← 元素种类 → 构建器（defs 只问它，不枚举元素种类）
│   └── selector_data.gd        ← 选择器候选（读 blocks/selectors/*.json）
├── view/                       ← 视图层（只渲染与交互，不持有拓扑真相）
│   ├── block_view.gd           ← BlockView：一个块的控件、几何度量、背景绘制
│   ├── editor_canvas.gd        ← EditorCanvas：图 + 撤销栈 + 视图集合 + 布局求解
│   ├── layout_solver.gd        ← 纯函数布局求解（自底向上量、自顶向下摆、产出吸附锚点）
│   ├── block_metrics.gd        ← 块几何契约（尺寸/尾锚点/槽位锚点）
│   ├── layout_result.gd        ← 求解结果（矩形表 + 锚点表）
│   ├── editor_camera.gd        ← 相机：滚轮缩放 + 空白处左键平移
│   ├── drag_controller.gd      ← 拖拽会话（调色板出块 / 画布内搬移 / 落地）
│   ├── link_controller.gd      ← 锁定会话（Jump 的目标按钮：拖到某块上松手 = 锁定）
│   ├── link_layer.gd           ← 跳线层（Jump → 目标块的彩色折线 + 箭头）
│   ├── selector_panel.gd       ← 单位/传感器选择器浮层
│   └── elements/
│       └── element_builders.gd ← 内置元素构建器（ElementBuilder 子类 + 注册）
├── mlog/                       ← 与 mlog 文本互转（纯函数，不碰控件）
│   ├── mlog_exporter.gd        ← LogicGraph → mlog 文本
│   └── mlog_importer.gd        ← mlog 文本 → 尚未入图的节点（复用导出模板反查块类型）
├── controls/
│   ├── notice_window.tscn      ← 公告弹窗（textdb.online）
│   ├── notice_item.tscn
│   ├── settings_window.tscn    ← 设置窗口（帧率上限 / UI 缩放 / 失焦自动导出）
│   ├── settings_window.gd
│   ├── document_page.tscn      ← 文档页（标签页形态：左边章节 / 右边富文本）
│   ├── document_page.gd        ← 文档正文就在这个文件的 SECTIONS 常量里
│   ├── about_window.tscn       ← 关于窗（版本 / 作者 / 反馈与仓库链接）
│   └── about_window.gd
├── scenes/
│   ├── editor.tscn             ← 编辑器标签页（脚本已外置，不再内嵌 GDScript）
│   └── main.tscn               ← 应用入口
└── scripts/
    ├── main.gd                 ← @tool，顶层 UI + 菜单 + 标签页重命名 + 光标
    └── editor.gd               ← 标签页拼装：调色板 + 画布 + 拖拽 + 锁定 + 选择器

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
  一种元素种类的全部行为（建控件 / 回填 / 默认值 / 取值校验 / 是否承载字段或槽位）都长在
  [ElementBuilder] 的子类上，由 [ElementRegistry] 注册（内置实现在 `view/elements/`）。
  导出与条件求值一律读数据层，不读控件 —— 「从控件里读值」这件事在实现里不存在。
- **view 从数据推导**：`BlockView` 是 `Control`（不是 `Container`），行位置自己给；
  尺寸由 `measure(slot_extents) -> BlockMetrics` 主动算出，位置由 `LayoutSolver.solve()` 统一求解。
  **位置绝不从绘制缓存反读**；块与块之间也没有父子关系，嵌套只体现在位置上。

### 一次改动的数据流

1. 用户改控件 → `BlockView.commit_field()` → `EditorCanvas` 用 `GraphHistory.record()` 包住 `LogicGraph.set_field()`；
2. 图发出 `structure_changed` / `field_changed` / `reset` → 画布同步视图集合并重新求解布局；
3. 拖拽：`BlockView.drag_requested` → `DragController` 拿起"这个块 + 它后面的所有块"（各自子树跟着），
   每帧向画布要 `find_anchor()` 找落点，并在落点摆出一组**占位块**（半透明、显示真实字段值、
   不吃鼠标）指示
   "现在放下会怎么样"；插入到链中间时，插入点之后的块会被临时下移给占位块腾位置。
   用[b]开始拖拽的那个键[/b]**松开**才落地（一次撤销记录），原地松手视为没搬动；
   所以左键搬移就左键松手、右键复制就右键松手（`DragController._button`）；
   另一个键按下 = 取消（左键搬移时按右键仍然取消）。
   **拖到左侧块列表上松手 = 删除**（拿起的整串一起删，同样只记一条撤销）；
   拖到画布外其他地方/右键/Esc = 取消 —— 拖拽本身不改数据。
   拖拽期间块里的可交互控件会被统一禁用（`EditorCanvas.set_elements_enabled` →
   `BlockView.set_elements_enabled` → 构建器的 `set_enabled`）：输入框变只读并交出焦点，
   下拉 / 开关 / 选择器按钮置为 `disabled`，松手/取消后恢复。
   [b]右键在块上按下 = 复制[/b]：`BlockView.copy_requested` → `DragController.start_copy_from_view`，
   跟手的是覆盖层里的一组副本（源块既不隐藏也不移动），松手时由 `EditorCanvas.duplicate_subtree`
   一次克隆整棵子树（含槽位结构），一条撤销记录；块引用指向子树[b]内部[/b]的重映射到新节点、
   指向外部的不变。拖到左侧块列表/画布外 = 取消，原地松手 = 不动数据。
   新节点在克隆时就彼此挂好，最后由 `LogicGraph.insert_subtree` 整体入图（不会把中间态暴露给信号）。
4. 锁定跳转目标：Jump 块的目标是一个 `<JumpTarget>` 按钮（不再是手填行号的输入框）。
   在它上面按下 → `BlockView.link_requested` → `LinkController` 接管：拖到某一块上松手 = 锁定到那块，
   拖到自己/左侧块列表 = 解除，空白处松手、右键、Esc = 取消（原样不动；原地松手只算点了一下）。
   落地只写一条撤销记录（`EditorCanvas.set_link`），图发出 `field_changed` 后重算布局并重绘跳线。
   跳线由 `LinkLayer` 画：从源块左侧出发、按“竖直区间是否相交”贪心分层错开、颜色由目标块派生；
   悬停中的候选块由 `BlockView.set_link_highlight` 描边。目标块被删时，指向它的引用会在删除的
   同一条撤销记录里被清掉（`EditorCanvas._clear_links_to`）。

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
<Block name="Print">
  <Literal>print</Literal>                        <!-- 默认导出模板：字面量 / 取字段 / 首个生效 -->
  <Field id="content" />
  <Export when="txt=true">                        <!-- 条件化模板，第一个成立的优先 -->
    <Literal>print</Literal><Field id="content" as="string" />
  </Export>
  <Row>                                           <!-- 显式分行（取代 <Br/>） -->
    <Text id="T1">Print</Text>
    <Text id="T2" when="txt=true">"</Text>	        <!-- 元素自己的生效条件 -->
    <LineBox id="content" placeholder="frog" />   <!-- placeholder 兼作默认值，可用 default 覆盖 -->
    <Text id="T3" when="txt=true">"</Text>
    <Button id="txt" text="TXT" />
  </Row>
</Block>
```

- **导出段**：`<Literal>`（可以含空格）、`<Field id>`、`<Field id link="true">`（块引用，见下）、
  `<FirstOf ids>`（取第一个**此刻生效**的字段，都不可用时输出 `0`）；
  `glue="true"` / `space_before="false"` 表示本段紧贴上一段；
  `<Field as="string">` 表示这一格是字符串（引号与转义由导出器加），
  `<Field allow_empty="true">` 表示空值不补 `0`（注释文本这类字段）；
  `<Item alias="…">` 让导入认出这个选项的旧名字。细节见下节。
- **行**：`<Row [when]>` 显式分行；条件不成立的行**整行不参与布局**（不占位置、不绘制）。
  `<Group when="…">` 给一串连续元素共享条件（不换行，解析时并入元素条件）。
- **元素**：`<Text>` / `<LineBox placeholder>` / `<Option>`+`<Item [value]>` / `<Button text>` / `<Selector kind>` /
  `<JumpTarget>` / `<Nest>`；条件不成立的元素既不占位置也不显示，但控件不重建（输入焦点不会被打断）。
- **选择器**：`<Selector id="unit" kind="units" />`，候选取自 `blocks/selectors/{kind}.json`。
- **块引用**：`<Field id="target" link="true"/>` 声明该字段存的是**另一块的引用**（`#<节点 id>`），
  而不是直接进 mlog 的文本。Jump 就是这么做的：导出时由 `MlogExporter` 把它换成目标块的**指令行号**
  （注释行 `#…` 与标签行 `label:` 不占行号），导入时 `MlogImporter.bind_links` 再把行号绑回块。
  「哪些字段是引用」的唯一真相在导出模板上（`BlockDef.reference_fields()`），元素种类只管怎么编辑它。
- **`<Item value="33">!</Item>`**：显示值与导出值可以不同（PrintChar 是显示字符、导出字符码）。
- **报错要出声**：`condition_parser.gd` 只做语法解析；「字段是否存在、取值是否合法」由 `BlockLibrary`
  在整块解析完后统一校验。语法错、未知字段、非法取值、未注册的元素标签与 `<Br>`/`<Pressed>` 旧写法
  都会进 `BlockLibrary.warnings` —— 写错不会静默变成"恒生效"。
- **改格式时的安全做法**：先 dump 一遍行为快照（每个字段组合的生效元素集合 + 导出结果），
  改完再 dump 比对 —— 迁移就是这么做的（见 git 历史），它抓出过三个"解析零警告但行为已变"的 bug。

### mlog 文本格式（与官方对齐）

Mindustry 的文本读写是[b]构建期生成[/b]的（`annotations/…/LogicStatementProcessor` 生成
`mindustry.logic.LogicIO`）：写 = 语句名 + 该语句类的[b]每一个非 transient 字段[/b]（枚举用 `.name()`）；
读 = 按位置逐个赋值（`if(length > i+1)`，所以[b]短行合法[/b]、缺的参数保持默认）。
由此有三条硬约束，改块定义时不能破：

1. [b]每条语句的参数个数固定[/b]：`draw` 8、`control`/`ucontrol` 7、`radar`/`uradar` 8、`ulocate` 9、
   `op` 5、`select` 7、`sensor`/`read`/`write` 4、`getlink` 3、`packcolor`/`unpackcolor` 6……
   导出模板必须整够这么多格（用 `<Literal>0</Literal>` 占位也行）：少一格后面的参数读串位，
   多一格游戏整行判成无效语句。
2. [b]同一格的含义随选项变[/b]：`draw` 的六格是官方的 (x, y, p1…p4)，哪个字段落在哪一格看 `mode`
   （`LExecutor`/`LogicDisplay`：`rotate` 的角度在 [b]p1[/b]、`print` 的对齐在 p1、`rect` 的宽高在 p1/p2…）；
   `ucontrol` 的 p1…p5 也随类型变（`itemDrop` = 目标+数量，`itemTake` = 目标+物品+数量）。
   这类块用一串 `<FirstOf>` 把「当前模式生效的那个字段」放进对应格子 —— 顺序写错，
   值就落进游戏不读的参数里（表现就是“改一下选项，内容就变了/丢了”）。
3. [b]枚举取值必须是官方的 Java 名[/b]（`col`、`lineRect`、`payTake`、`autoPathfind`…）：
   否则游戏那边 `valueOf()` 抛异常，整行变成无效语句。

导入侧（`MlogImporter`）三条对应规则：

- 结构匹配之外还按[b]选项取值合法性打分[/b]（`_score`）：`ucontrol` 的十几个变体共用 `ucontrol`
  首 token、模板结构也一样，只看结构会把 `ucontrol boost …` 绑给「移动」那块。
- `<FirstOf>` 那一格按[b]已解析出的选项值[/b]挑生效字段（与导出同一套 `is_field_active`）。
- 允许短行，并像 `LParser` 那样把 `;` 当语句分隔符、把 `#` 当行尾注释（`split_statements()`）。

[b]显示层与文本层是两回事[/b]：参数个数固定说的是[b]文本[/b]，界面上该藏的输入框照样要藏。
官方 UI 在每个语句的 `build()` 里按当前选项决定显示哪几个输入框，那张表就是：

- `ucontrol`：[b]`LUnitControl.params`[/b]，逐项声明的（`move("x","y")`、`approach("x","y","radius")`、
  `targetp("unit","shoot")`、`payTake("takeUnits")`，而 `idle`/`stop`/`autoPathfind`/`payDrop`/
  `payEnter`/`unbind` 没有参数）。
- `control`：`LAccess.params`（`enabled("to")`、`shoot("x","y","shoot")`、`shootp("unit","shoot")`、`config("to")`、`color("to")`）。
- `draw`：`DrawStatement.build()` 的 `switch(type)`。
- `jump` / `select`：`addOp()` 里的 `if(op != always)` —— `always` 时[b]两个比较值都不显示[/b]。
- `op`：`LogicOp.unary`（`not`/`abs`/`sign`/`log`/`log10`/`floor`/`ceil`/`round`/`sqrt`/`rand`/`sin`/
  `cos`/`tan`/`asin`/`acos`/`atan`）只显示一个操作数。
- `ulocate`：`switch(locate)`；其中 `building` 这个[b]输出[/b]在 `ore` 以外的三种都有（`if(locate != ore)`）。

所以 XML 里 Row 的每个输入框都要带 `when`，而导出模板里的 `<Field>` 保持无条件 ——
两者分开写：模板负责文本，元素负责显示。改完块定义要同时跑两套检查（只跑一套就会
出现“文本对了但界面多/少一个框”或反之）。

校验手段（改完 XML 跑一遍，[b]文本与显示各一条[/b]）：

- 文本：每块导出一行，token 数应与官方表一致；再逐选项导出，[b]参数个数不能变[/b]
  （选项只换内容，不换参数个数）；以及导出→导入→再导出的往返比对。
- 显示：对每个块 × 每个选项取值，拿 [method BlockDef.is_element_active]（视图用的同一函数）
  算出「可见的输入框」集合，与上面那张官方表逐个对比 —— 只做文本检查的话，
  界面多一个/少一个框这类问题根本测不出来。


### 扩展点

- 新增元素类型：在 `view/elements/element_builders.gd` 里继承 `ElementBuilder` 写一个子类并注册，
  **只改这一处**：解析、条件校验、默认值灌入、`BlockView` 与 `BlockDef` 都不用动
  （它们只问构建器：`is_field` / `is_slot` / `validate_value` / `default_value` / `apply_value` /
  `set_enabled`）。
- 新增块：往 XML 里加 `<Block>`，不需要写 GDScript。
- 新增选择器候选：改 `blocks/selectors/*.json`。

### Other

- **`@tool`**：`main.gd` 在编辑器里也会跑。
- **`class_name`**：模型/定义/视图三层的类都全局注册。
- **公告窗**：`notice_window.tscn` 通过 HTTPRequest 拉 `https://textdb.online/MindVisualLogic`。
- **自定义光标**：`main.gd._ready()` 从 `assets/sprites/cursors/` 装载。
- **顶部工具栏**：左边是 `File`（新建页 / 存 / 开 / 导出到剪贴板 / 剪贴板导入）、
  `Edit`（撤销 / 重做 / 清空 / 设置…，弹出前按当前页状态置灰）、`Help`（文档 / 公告 / 关于）；
  右边是独立的 `Quit` 按钮（`UI._on_sort_children` 里右对齐：先量行高，再按它的宽度把菜单栏缩回去）。
  Help 里的「文档」是标签页（[DocumentPage]，开过就切过去、不重复开），
  「公告」与「关于」是独立窗口（[AboutWindow] 的版本号与引擎版本是运行期读的）。
  「清空」走 `LogicEditorTab.clear_graph()`，算一条可撤销记录；`new_project()` 则是
  「换成另一个文档」，会连撤销栈一起清掉 —— 两者不要混用。
  菜单 id 就是 `item_N/id` 的顺序编号，加删菜单项时记得同步 `_on_*_id_pressed` 里的注释。
  文档页[b]不是[/b] [LogicEditorTab]，所以在它上面「存 / 导出 / 撤销」都是空操作
  （`_current_editor()` 返回 null，编辑菜单据此置灰）—— 这不是 bug，别把菜单项接死。
- **F5 快捷导出**：等价于 `File → 导出到剪贴板`。键位在 [code]project.godot[/code] 的 `[input]` 里，
  action 名沿用旧版的 `compile`（旧版把「导出 mlog」叫 compile），代码里只认
  `Main.QUICK_EXPORT_ACTION` 常量 —— 要换键就改 project.godot，不用碰代码。
  实际按下时是菜单栏先把菜单项的 accelerator 接走（菜单里因此看得见 F5），
  `_unhandled_key_input` 只是焦点不在菜单栏时的兜底；两者不会双触发（前者会标 handled）。
  导出无内容（当前页是文档页等）时在 [method Main._export_to_clipboard] 里统一提示一声，
  菜单项与 F5 共用这一个出口，别再各写一份。
- **入口块（Start）**：XML 里 `<Block entry="true">`，它所在的类别用 `<Kind hidden="true">` 藏起来
  （Special 就是：块还在库里、`BlockLibrary.entry_def()` 找得到，只是不进调色板）。
  新页由 `LogicEditorTab._place_entry_block()` 自动放一个，[b]不进撤销栈[/b]。
  一个文档只该有一个，所以：不能复制（[DragController.start_copy_from_view] 连会话都不开，
  [method EditorCanvas.duplicate_subtree] 再兜一道）、不能删除（拖到左侧列表时
  `_carries_entry()` 拦下）；`is_empty()` [b]不算[/b]入口块，否则「清空」永远不置灰。
  [b]导出只走入口块那条链、从它开始[/b]（[method MlogExporter._walk]）：它前面的块与
  其他链都不导出；它自己渲染成空行、不占行号（跳到它身上的 jump 落到下一条指令）。
  没有入口块的旧存档退回旧规矩（所有链都导出）。
  「清空 / new_project / 剪贴板 Load」都要把入口块放回来，Load 还要把导入的块插到
  入口块那条链上 —— 插到别的链等于导不出来（见 `LogicEditorTab._import_target()`）。
- **应用设置**：`AppSettings`（`model/app_settings.gd`）是纯数据 + `user://settings.json`（容错读、超范围钳制）；
  `SettingsWindow` 只管「值 ↔ 控件」，[b]应用[/b]（`Engine.max_fps` / `root.content_scale_factor`）在 `main.gd`。
  改动即时生效、关闭窗口时才写盘；`@tool` 下 `_apply_settings()` 直接 return，
  免得在编辑器里顺手改掉 Godot 编辑器自己的帧率与界面缩放。
  「失焦自动导出」走 `main.gd._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)`（旧实现叫 compile_when_close）。
  窗口[b]自带 StyleBoxFlat[/b]（与公告窗同一套配色）：主主题只覆盖了 Button/Label/MenuBar/
  PopupMenu/TabContainer/Tree/ScrollBar，`CheckButton`/`LineEdit`/`HSlider` 会顶引擎默认皮肤。
  数值用 `LineEdit` 而不是 `SpinBox`——SpinBox 的样式长在它内部的 LineEdit 与箭头按钮上，
  override 到不了里面；这两类控件的字体也要显式 override（主题里没有它们的 font 条目）。
  窗口尺寸必须放得下内容最小宽度（`Body.get_combined_minimum_size()`），
  否则 VBox 会被压扁、左侧与底部文字直接被切掉。
- **标签页标题**：`LogicEditorTab.display_name()` 先看手动命名（`custom_name`），再跟随文件名。
  重命名是就地编辑：标签条上浮一个 `LineEdit`（TabBar 的子节点，不会变成新页面），
  单击[b]已选中[/b]的标签（延迟一个双击间隔才开，免得双击时闪一下）或[b]右键[/b]任意标签打开；
  [b]双击[/b]任意标签 = 关闭该页（关掉最后一个会自动补一个空白页）；按住拖动（重排标签）
  会取消这次改名。回车/失焦提交、Esc 取消、空名字回落文件名，切页时也会自动提交。
  实现上用 TabBar 的 `gui_input` 而不是 `tab_clicked` 信号：后者是在[b]内建处理之后[/b]才发的，
  那时当前页已经切过去了（分不出「切页」与「点已选中的页」），也拿不到 `double_click`。

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
- **拖拽控制器不要消费 mouse-up**：画布是 SubViewport，而 `SubViewportContainer` 靠
  `is_input_handled()` 决定要不要把事件转发进去 —— 一口吞掉 mouse-up，画布里那层 GUI 的
  鼠标焦点与按键掩码就清不掉，之后的左键按下会被发到残留的那个块上（鼠标不在它身上时
  `_has_point` 为假 → 表现为“拖不动任何块”，要点一下别处才恢复）。所以拖拽结束只调 `_finish()`，
  不要 `set_input_as_handled()`；“另一个键按下 = 取消”可以继续消费，因为它不会留下掩码。
  收尾事件真丢了（切窗口 / 在窗口外松手）时，由 `_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` 收尾。
  也不要拿 `Input.is_mouse_button_pressed` 做守时兜底：触屏（项目有 Android 导出）不反映鼠标键。
