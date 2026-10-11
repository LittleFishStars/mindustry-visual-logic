class_name SelectorPanel
extends Control

## 内容选择弹窗：单位 / 建筑 / 物品 / 液体 / 传感器属性等候选的图标网格。
##
## 块定义里写 `<Selector id="unit" kind="units" />`（kind 对应 blocks/selectors/<kind>.json），
## 元素构建器给输入框配一个 ▾ 按钮，按下就打开这里；选中的 `@xxx` 回填进那个输入框。
##
## 本体是一层**铺满父级的浮层**：底下是半透明遮罩（点一下 = 关闭），上面是居中的面板。
## 遮罩自己吃鼠标，所以弹窗期间点不到画布 —— 这既是「模态」的意思，也省得外面还要再判断
## 「点到面板外面了吗」。Esc 同样关闭。
##
## 候选可能很多（建筑 259 个），所以有[b]搜索框[/b]：边打边筛，回车直接选第一个。
## 候选来自 [SelectorData]（blocks/selectors/*.json），面板只负责把候选铺成网格、
## 按需分组、按关键词过滤。
##
## 面板是编辑器标签页的子级（在调色板/画布所在的 Control 树里），
## 因此不依赖 Window/Popup —— 在 SubViewport 画布上打开弹窗不会再遇到嵌入窗口的坑。

signal picked(value: String)

const CELL_SIZE: Vector2 = Vector2(40, 40)
const COLUMNS: int = 7
const PANEL_SIZE: Vector2 = Vector2(344, 384)
const GRID_HEIGHT: float = 236.0

## 配色与设置窗/公告窗一致：主主题没有覆盖 PanelContainer，得自己带 StyleBoxFlat。
const COLOR_PANEL: Color = Color(0.207843, 0.180392, 0.25098, 1.0)      # #35304A
const COLOR_BAR: Color = Color(0.258824, 0.22352941, 0.30980393, 1.0)   # #423956
const COLOR_BORDER: Color = Color(0.101961, 0.086275, 0.121569, 1.0)
const COLOR_BACKDROP: Color = Color(0.0, 0.0, 0.0, 0.45)
## 搜索框的底与聚焦描边（照搬设置窗的输入框）
const COLOR_EDIT: Color = Color(0.212113, 0.181757, 0.255897, 1.0)
const COLOR_EDIT_FOCUS: Color = Color(0.398337, 0.3869, 0.73, 1.0)
## 格子底色/描边：普通 / 悬停 / 按下（与设置窗的输入框同一套）。
const CELL_COLORS: Dictionary = {
	&"normal": [Color(0.212113, 0.181757, 0.255897, 1.0), Color(0.142885, 0.124547, 0.161226, 1.0)],
	&"hover": [Color(0.258824, 0.22352941, 0.30980393, 1.0), Color(0.142885, 0.124547, 0.161226, 1.0)],
	&"pressed": [Color(0.30980393, 0.27058825, 0.36862746, 1.0), Color(0.101961, 0.086275, 0.121569, 1.0)],
}

## kind → 弹窗标题（认不出就用 kind 本身）。
const TITLES: Dictionary[StringName, String] = {
	&"units": "单位",
	&"blocks": "建筑",
	&"items": "物品",
	&"liquids": "液体",
	&"sensors": "属性 / 内容",
}

var _backdrop: ColorRect
var _panel: PanelContainer
var _title: Label
var _search: LineEdit
var _groups_bar: HBoxContainer
var _grid: GridContainer
var _count: Label
var _element: ElementDef = null

## 当前 kind 的分组（无分组时为空）；正在看的分组名（空 = 全部）。
var _groups: Dictionary = {}
var _group: StringName = &""
var _icon_cache: Dictionary[String, Texture2D] = {}
## 建好的格子：[{value, group, button}]，按数据顺序一次建齐，筛选只改 visible。
var _cells: Array[Dictionary] = []
## 当前搜索关键词：由 LineEdit 的 text_changed 带进来（不读控件，见 _ready 里的注释）。
var _keyword: String = ""


func _ready() -> void:
	# 整层铺满父级：遮罩要盖住整个编辑器区域，面板在中间
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200

	_backdrop = ColorRect.new()
	_backdrop.color = COLOR_BACKDROP
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	# 顶部标题条：与设置窗/公告窗同一套（浅一档的底 + 5px 顶边）
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _make_bar_style())
	box.add_child(bar)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	bar.add_child(_title)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 10)
	body_margin.add_theme_constant_override("margin_right", 10)
	body_margin.add_theme_constant_override("margin_bottom", 8)
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_child(body)

	_search = LineEdit.new()
	_search.placeholder_text = "搜索（回车选第一个）"
	_search.clear_button_enabled = true
	# 主主题没有 LineEdit 条目，不自己带样式就会顶着引擎默认的浅色皮肤
	_search.add_theme_stylebox_override("normal", _make_edit_style(false))
	_search.add_theme_stylebox_override("focus", _make_edit_style(true))
	var font := load("res://assets/fonts/font.woff") as Font
	if font != null:
		_search.add_theme_font_override("font", font)
	# 用信号带过来的文本，不要去读 _search.text —— 回调比控件自身更新早一步，读到的是旧值
	_search.text_changed.connect(func(text: String) -> void:
		_keyword = text
		_refill())
	_search.text_submitted.connect(func(_text: String) -> void: _pick_first())
	body.add_child(_search)

	_groups_bar = HBoxContainer.new()
	_groups_bar.add_theme_constant_override("separation", 4)
	body.add_child(_groups_bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GRID_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	body.add_child(_count)

	resized.connect(_recenter)
	# 面板尺寸可能因内容变化（字体/滚动条），居中要跟着走
	_panel.resized.connect(_recenter)


## StyleBoxFlat 的统一起手：底色 + 可选描边 + 可选圆角（主主题里没有 PanelContainer /
## LineEdit 的条目，这些样式必须自带）。内容留白各调用点自己写 —— 它们的四边往往不一样。
static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0,
		radius: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if border_width > 0:
		style.set_border_width_all(border_width)
		style.border_color = border
	if radius > 0:
		style.set_corner_radius_all(radius)
	return style


## 面板底：深色底板 + 一圈描边（主主题里没有 PanelContainer 的样式）。
func _make_panel_style() -> StyleBoxFlat:
	var style := _box(COLOR_PANEL, COLOR_BORDER, 2)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	# 子控件要紧贴边框：内容留白交给里面的 MarginContainer，否则标题条两端会缩进去
	style.set_content_margin_all(0.0)
	return style


## 格子的紧凑样式：主题里 Button 的 content margin 高达 30，会把 40px 的格子撑成 115px。
func _make_cell_style(state: StringName) -> StyleBoxFlat:
	var style := _box(CELL_COLORS[state][0], CELL_COLORS[state][1], 2)
	style.set_content_margin_all(4.0)
	return style


## 搜索框：与设置窗的输入框同一套（深底 + 2px 描边，聚焦时描边变亮紫）。
func _make_edit_style(focused: bool) -> StyleBoxFlat:
	var style := _box(COLOR_EDIT, COLOR_EDIT_FOCUS if focused else COLOR_BORDER, 2, 2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _make_bar_style() -> StyleBoxFlat:
	var style := _box(COLOR_BAR)
	style.border_width_top = 5
	style.border_color = Color(0, 0, 0, 0.419608)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 4.0
	return style


## 在编辑器区域[b]居中[/b]打开弹窗。
func open(element: ElementDef) -> void:
	if element == null or not SelectorData.exists(element.selector_kind):
		push_warning("没有选择器数据：%s（kind=%s）" % [
			element.id if element != null else "?",
			element.selector_kind if element != null else "?"])
		return
	_element = element
	_groups = SelectorData.groups(element.selector_kind)
	_group = &""
	_title.text = "%s · %s" % [TITLES.get(element.selector_kind, String(element.selector_kind)), element.id]
	_keyword = ""
	_search.text = ""
	_build_groups()
	_build_cells()
	_refill()
	visible = true
	call_deferred("_fit_and_center")
	# 打开就能直接打字过滤；Esc 关掉由 _unhandled_key_input 兜
	_search.grab_focus()


func close() -> void:
	visible = false
	_element = null
	_group = &""


func is_open() -> bool:
	return visible


## 面板居中：父级矩形中心减去自身一半；父级比面板小就贴左上角，别跑出可视区。
func _recenter() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var span := size - _panel.size
	_panel.position = Vector2(maxf(span.x * 0.5, 0.0), maxf(span.y * 0.5, 0.0))


## 按内容重新定尺寸再居中。
##
## 必须显式做（不能在 open 里同步做）：Control 只会跟着最小尺寸变大、[b]不会自己缩回[/b] ——
## 先开传感器（宽）再开建筑（窄）会留着上一次的宽面板。而最小尺寸要等一帧才重算完，
## 所以 reset_size 走 deferred。
func _fit_and_center() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.reset_size()
	_panel.size = Vector2(
		minf(_panel.size.x, maxf(size.x - 24.0, 200.0)),
		minf(_panel.size.y, maxf(size.y - 24.0, 200.0)))
	_recenter()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 分组按钮：全部 + 数据里的各组（没有分组数据时整条不显示）。
func _build_groups() -> void:
	for child in _groups_bar.get_children():
		_groups_bar.remove_child(child)
		child.queue_free()
	_groups_bar.visible = not _groups.is_empty()
	if _groups.is_empty():
		return
	_add_group_button("", "全部")
	for group_name in _groups:
		_add_group_button(StringName(group_name), String(group_name))


func _add_group_button(id: StringName, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_group = id
		_refill()
		_search.grab_focus())
	_groups_bar.add_child(button)


## 建格子：一次建齐（建筑有 259 个），筛选只改 visible —— 每敲一个字就重建几百个按钮太贵。
## 有分组数据时，每个格子记下自己属于哪一组（分页只切分组，不重建）。
func _build_cells() -> void:
	for child in _grid.get_children():
		# 先摘掉再 free：queue_free 要到本帧末才真删，那一帧里它还在树上、还可见 ——
		# 回车选第一个（以及布局）就可能挑到上一个弹窗留下的旧按钮
		_grid.remove_child(child)
		child.queue_free()
	_cells.clear()
	# 分组数据在 open() 里已经取过一次（_groups），这里直接用 —— 数据源只读一处
	if _groups.is_empty():
		for entry in SelectorData.options(_element.selector_kind):
			_add_cell(entry, &"")
	else:
		for group_name in _groups:
			for entry in _groups[group_name]:
				_add_cell(entry, StringName(group_name))


func _add_cell(entry: Variant, group: StringName) -> void:
	if not (entry is Dictionary):
		return
	var value := String((entry as Dictionary).get("value", ""))
	var button := _make_cell(value, String((entry as Dictionary).get("icon", "")))
	_grid.add_child(button)
	_cells.append({"value": value, "group": group, "button": button})


## 按「当前分组 + 搜索关键词」重排网格：只切可见性与顺序，不重建控件。
func _refill() -> void:
	if _element == null:
		return
	# 关键词以控件为准（信号里的那个值只是它自己报的）；程序化改 text（清空按钮之类）
	# 不一定走 text_changed，所以这里再对一次，不会两边不一致。
	if _keyword != _search.text:
		_keyword = _search.text
	var keyword := _keyword.strip_edges().to_lower()
	# 命中往前排：打了 `router` 就得先看到 `@router`，而不是按字母序排在前面的 `@duct-router`
	var first: Array = []
	var rest: Array = []
	var shown := 0
	var total := 0
	for cell in _cells:
		if _group != &"" and StringName(cell["group"]) != _group:
			(cell["button"] as Button).visible = false
			continue
		total += 1
		var value: String = cell["value"]
		var hit := keyword == "" or _matches(value, keyword)
		(cell["button"] as Button).visible = hit
		if not hit:
			continue
		shown += 1
		if keyword == "" or _starts_with(value, keyword):
			first.append(cell)
		else:
			rest.append(cell)
	# 把排好序的可见格子按顺序挪到前面（隐藏的不占布局，位置无所谓）
	var index := 0
	for cell in first + rest:
		_grid.move_child(cell["button"], index)
		index += 1
	_count.text = "共 %d 项" % total if shown == total else "共 %d 项，匹配 %d 项" % [total, shown]


## 关键词匹配：`@copper` 用 `c`、`copper`、`@copper` 都能搜到。
## 两个分支都不能省：`trim_prefix("@")` 后的 needle 为空串时 [method String.contains] 恒为假，
## 而只打一个 `@` 时用户要的是「列出所有引用名」—— 那正是第一个分支在管的。
func _matches(value: String, keyword: String) -> bool:
	var haystack := value.to_lower()
	return haystack.contains(keyword) or haystack.trim_prefix("@").contains(keyword.trim_prefix("@"))


## 名字（去掉 @）以关键词开头 —— 这种命中排在最前。
func _starts_with(value: String, keyword: String) -> bool:
	return value.to_lower().trim_prefix("@").begins_with(keyword.trim_prefix("@"))


func _make_cell(value: String, icon_path: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.tooltip_text = value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _make_cell_style(&"normal"))
	button.add_theme_stylebox_override("hover", _make_cell_style(&"hover"))
	button.add_theme_stylebox_override("pressed", _make_cell_style(&"pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var texture := _texture_of(icon_path)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
	else:
		# 没有图标的候选（传感器的 @totalItems / @firstItem 这类）退回显示名字：
		# 只显示短标签（全名在悬停提示里）—— 否则一个长名字就能把整排格子擑宽
		var label := value.trim_prefix("@")
		button.text = label if label.length() <= 7 else label.substr(0, 6) + "…"
		button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(func() -> void: picked.emit(value))
	return button


## 回车：选第一个候选（边打边筛 + 回车 = 键盘流）。
func _pick_first() -> void:
	# 只在有效格子里挑（_cells 是唯一真相），取网格里最靠前的那个 —— _refill 已把命中项
	# 按序排到前面，所以最靠前 = 排名第一
	var best: Button = null
	var best_index := 1 << 30
	for cell in _cells:
		var button: Button = cell["button"]
		if button == null or not is_instance_valid(button) or not button.visible:
			continue
		if button.get_index() < best_index:
			best_index = button.get_index()
			best = button
	if best != null:
		picked.emit(best.tooltip_text)


func _texture_of(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_icon_cache[path] = texture
	return texture
