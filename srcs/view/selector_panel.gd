class_name SelectorPanel
extends PanelContainer

## 选择器浮层：单位 / 传感器等在块旁边的候选面板。
##
## 旧实现是两个各 400 多个按钮的巨型场景（unit_select_container / sensor_selector），
## 候选写死在场景里；这里候选来自 [SelectorData]（blocks/selectors/*.json），
## 面板本身只负责把候选铺成网格并按需分组。
##
## 面板是编辑器标签页的子级（在调色板/画布所在的 Control 树里），
## 因此不依赖 Window/Popup —— 在 SubViewport 画布上打开弹窗不会再遇到嵌入窗口的坑。

signal picked(value: String)

const CELL_SIZE: Vector2 = Vector2(38, 38)
const COLUMNS: int = 6
const PANEL_SIZE: Vector2 = Vector2(300, 260)

var _groups_bar: HBoxContainer
var _grid: GridContainer
var _hint: Label
var _element: ElementDef = null

var _icon_cache: Dictionary[String, Texture2D] = {}
var _current_kind: StringName = &""


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	visible = false
	z_index = 200
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_groups_bar = HBoxContainer.new()
	_groups_bar.add_theme_constant_override("separation", 4)
	_hint = Label.new()
	_hint.text = "选择候选"
	box.add_child(_hint)
	box.add_child(_groups_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)
	add_child(box)


## 在 [param anchor]（全局坐标）附近打开面板。[param control] 是回填目标（选择器那个文本框）。
func open(element: ElementDef, control: Control, anchor: Vector2) -> void:
	if element == null or not SelectorData.exists(element.selector_kind):
		return
	_element = element
	_hint.text = "%s：%s" % [element.id, element.selector_kind]
	_build_groups()
	_fill(SelectorData.options(element.selector_kind))
	visible = true
	_position_at(anchor)


func close() -> void:
	visible = false
	_element = null


func is_open() -> bool:
	return visible


func _build_groups() -> void:
	for child in _groups_bar.get_children():
		child.queue_free()
	var groups := SelectorData.groups(_element.selector_kind)
	if groups.is_empty():
		return
	for group_name in groups:
		var button := Button.new()
		button.text = String(group_name)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_fill(groups[group_name] as Array))
		_groups_bar.add_child(button)


func _fill(entries: Array) -> void:
	for child in _grid.get_children():
		child.queue_free()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var value := String((entry as Dictionary).get("value", ""))
		var icon_path := String((entry as Dictionary).get("icon", ""))
		var button := Button.new()
		button.custom_minimum_size = CELL_SIZE
		button.tooltip_text = value
		button.focus_mode = Control.FOCUS_NONE
		var texture := _texture_of(icon_path)
		if texture != null:
			button.icon = texture
			button.expand_icon = true
		else:
			button.text = value.trim_prefix("@")
		button.pressed.connect(func() -> void:
			picked.emit(value))
		_grid.add_child(button)


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
	var parent := get_parent() as Control
	if parent == null:
		return
	var local := anchor - parent.global_position
	var limit := parent.size - size
	position = Vector2(
		clampf(local.x, 0.0, maxf(limit.x, 0.0)),
		clampf(local.y, 0.0, maxf(limit.y, 0.0))
	)
