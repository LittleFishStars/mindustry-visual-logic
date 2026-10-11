class_name SelectorPanel
extends PanelContainer

## 内容选择弹窗：单位 / 建筑 / 物品 / 液体 / 传感器属性等候选的图标网格。
##
## 块定义里写 `<Selector id="unit" kind="units" />`（kind 对应 blocks/selectors/<kind>.json），
## 元素构建器给输入框配一个 ▾ 按钮，按下就打开这里；选中的 `@xxx` 回填进那个输入框。
##
## 候选可能很多（建筑 259 个），所以有[b]搜索框[/b]：边打边筛，回车直接选第一个。
## 旧实现是两个各 400 多个按钮的巨型场景（unit_select_container / sensor_selector），
## 候选写死在场景里；现在候选来自 [SelectorData]（blocks/selectors/*.json），
## 面板只负责把候选铺成网格、按需分组、按关键词过滤。
##
## 面板是编辑器标签页的子级（在调色板/画布所在的 Control 树里），
## 因此不依赖 Window/Popup —— 在 SubViewport 画布上打开弹窗不会再遇到嵌入窗口的坑。

signal picked(value: String)

const CELL_SIZE: Vector2 = Vector2(40, 40)
const COLUMNS: int = 7
const PANEL_SIZE: Vector2 = Vector2(344, 360)
const GRID_HEIGHT: float = 248.0

## kind → 弹窗标题（认不出就用 kind 本身）。
const TITLES: Dictionary[StringName, String] = {
	&"units": "单位",
	&"blocks": "建筑",
	&"items": "物品",
	&"liquids": "液体",
	&"sensors": "属性 / 内容",
}

var _title: Label
var _search: LineEdit
var _groups_bar: HBoxContainer
var _grid: GridContainer
var _count: Label
var _element: ElementDef = null

## 当前 kind 的全部分组（无分组时为空），以及正在看的分组名（空 = 全部）。
var _groups: Dictionary = {}
var _group: StringName = &""
var _icon_cache: Dictionary[String, Texture2D] = {}
## 建好的格子：[{value, group, button}]，按数据顺序一次建齐，筛选只改 visible。
var _cells: Array[Dictionary] = []
## 当前搜索关键词：由 LineEdit 的 text_changed 带进来（不读控件，见 _ready 里的注释）。
var _keyword: String = ""


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	visible = false
	z_index = 200
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	box.add_child(_title)

	_search = LineEdit.new()
	_search.placeholder_text = "搜索（回车选第一个）"
	_search.clear_button_enabled = true
	# 用信号带过来的文本，不要去读 _search.text —— 回调比控件自身更新早一步，读到的是旧值
	_search.text_changed.connect(func(text: String) -> void:
		_keyword = text
		_refill())
	_search.text_submitted.connect(func(_text: String) -> void: _pick_first())
	box.add_child(_search)

	_groups_bar = HBoxContainer.new()
	_groups_bar.add_theme_constant_override("separation", 4)
	box.add_child(_groups_bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GRID_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	box.add_child(_count)


## 在 [param anchor]（全局坐标）附近打开弹窗。[param control] 是回填目标（Selector 那个组合控件）。
func open(element: ElementDef, control: Control, anchor: Vector2) -> void:
	if element == null or not SelectorData.exists(element.selector_kind):
		push_warning("没有选择器数据：%s（kind=%s）" % [element.id if element != null else "?", element.selector_kind if element != null else "?"])
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
	_position_at(anchor)
	# 打开就能直接打字过滤；Esc 关掉由 _unhandled_key_input 兜
	_search.grab_focus()


func close() -> void:
	visible = false
	_element = null
	_group = &""


func is_open() -> bool:
	return visible


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 分组按钮：全部 + 数据里的各组（没有分组数据时整条不显示）。
func _build_groups() -> void:
	for child in _groups_bar.get_children():
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
	var groups := SelectorData.groups(_element.selector_kind)
	if groups.is_empty():
		for entry in SelectorData.options(_element.selector_kind):
			_add_cell(entry, &"")
	else:
		for group_name in groups:
			for entry in groups[group_name]:
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
	var texture := _texture_of(icon_path)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
	else:
		# 没有图标的候选（传感器的 @totalItems 之类）退回显示名字
		button.text = value.trim_prefix("@")
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


## 贴着锚点摆，并夹在自己的父级矩形内。
func _position_at(anchor: Vector2) -> void:
	var parent := self.get_parent() as Control
	if parent == null:
		return
	var local := anchor - parent.global_position
	var limit := parent.size - size
	position = Vector2(
		clampf(local.x, 0.0, maxf(limit.x, 0.0)),
		clampf(local.y, 0.0, maxf(limit.y, 0.0))
	)
