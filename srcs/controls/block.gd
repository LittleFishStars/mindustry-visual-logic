class_name Block
extends Container


## 拖拽相关信号
signal drag_started(offset: Vector2)

## 布局间距与行高
@export var margin: int = 6
@export var separation: int = 10
@export var height: int = 40

## 绘制样式
@export_group("styles")
@export var bg_color: Color
@export var font: FontFile = preload("res://assets/fonts/font.woff")
@export var corner_radius: int = 10
@export var shadow_size: int = 4
@export var shadow_offset: Vector2 = Vector2(2, 4)
@export var shadow_color: Color = Color(0, 0, 0, 0.3)

var _block_data: Dictionary = {}  ## XML 解析后的块原始数据（export + elements 列表）

var _elements: Dictionary = {}  ## id → 已创建的控件（Label / LineEdit / OptionButton / Button / Box）
var _option_map: Dictionary = {}  ## Option id → { button: OptionButton, items: Array }，用于取 show 属性
var _button_states: Dictionary = {}  ## Button id → "pressed" | "released"，控制输出加不加引号
var _current_show: String = ""  ## 当前选中 Option Item 的 show 字符串，空则表示全部可见

## 绘制缓存
var _bg_rects: Array[Rect2] = []
var _style_boxes: Array[StyleBoxFlat] = []


## 嵌套子块容器（If 块的 <Nest>）
class Box extends VBoxContainer:
	func _ready() -> void:
		self.add_theme_constant_override("separation", 0)


func _init(block_data: Dictionary, p_color: Color = Color.WHITE) -> void:
	self._block_data = block_data
	self.bg_color = p_color
	self.sort_children.connect(self._on_sort_children)
	_build_elements()


func _make_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	row.size_flags_horizontal = 0
	return row


## 创建全部控件，所有元素始终存在于树中，通过 visible 切换显示，避免重建 DOM。
func _build_elements():
	for child in get_children():
		child.queue_free()
	_elements.clear()
	_option_map.clear()
	_button_states.clear()
	_current_show = ""

	var elements: Array = _block_data.get("elements", [])
	if elements.is_empty():
		return

	var current_row: HBoxContainer
	var need_new_row: bool = false

	for el in elements:
		if need_new_row:
			current_row = _make_row()
			add_child(current_row)
			need_new_row = false
		match el["type"]:
			"Text":
				if current_row == null:
					current_row = _make_row()
					add_child(current_row)
				var lbl = _make_label(el.get("text", ""))
				_elements[el["id"]] = lbl
				current_row.add_child(lbl)
			"LineBox":
				if current_row == null:
					current_row = _make_row()
					add_child(current_row)
				var le = _make_line_edit(el.get("placeholder", ""))
				_elements[el["id"]] = le
				current_row.add_child(le)
			"Option":
				if current_row == null:
					current_row = _make_row()
					add_child(current_row)
				var opt = _make_option(el)
				_elements[el["id"]] = opt
				_option_map[el["id"]] = {"button": opt, "items": el.get("items", [])}
				opt.item_selected.connect(_on_option_changed.bind(el["id"]))
				current_row.add_child(opt)
			"Button":
				if current_row == null:
					current_row = _make_row()
					add_child(current_row)
				var btn = _make_button(el)
				_elements[el["id"]] = btn
				_button_states[el["id"]] = "released"
				btn.toggled.connect(_on_button_toggled.bind(el["id"]))
				current_row.add_child(btn)
			"Br":
				need_new_row = true
				current_row = null
			"Nest":
				var box = Box.new()
				box.set_meta("nest_id", el["id"])
				_elements[el["id"]] = box
				add_child(box)
				need_new_row = false
	# 若 Nest 在末尾则补充 tail
	if self.get_child(-1) is Box:
		var tail = Control.new()
		tail.set_meta("li_tail", true)
		add_child(tail)

	# 初始显示：取第一个有 show 属性的 Option 的选中项
	for opt_id in _option_map:
		var data = _option_map[opt_id]
		var items: Array = data["items"]
		if items.is_empty():
			continue
		var idx = data["button"].selected
		var show_content = items[idx].get("show", "") if idx < items.size() else ""
		if show_content != "":
			_current_show = show_content
			break

	_apply_visibility()


## 创建 OptionButton 并填充 Item 列表及默认选中项
func _make_option(el: Dictionary) -> OptionButton:
	var opt = OptionButton.new()
	for item in el.get("items", []):
		opt.add_item(item["text"])
	var def = el.get("default", "0")
	if def is String and def.is_valid_int():
		opt.selected = int(def)
	opt.add_theme_font_override("font", self.font)
	opt.add_theme_stylebox_override("normal", _control_style(bg_color))
	opt.add_theme_stylebox_override("hover", _control_style(bg_color.lightened(0.15)))
	opt.add_theme_stylebox_override("pressed", _control_style(bg_color.darkened(0.1)))
	return opt


## 创建 toggle 模式按钮
func _make_button(el: Dictionary) -> Button:
	var btn = Button.new()
	btn.text = el.get("text", "")
	btn.toggle_mode = true
	btn.add_theme_font_override("font", self.font)
	btn.add_theme_stylebox_override("normal", _control_style(bg_color))
	btn.add_theme_stylebox_override("hover", _control_style(bg_color.lightened(0.15)))
	btn.add_theme_stylebox_override("pressed", _control_style(bg_color.darkened(0.1)))
	return btn


## 样式复用：阴影、圆角、边距
func _control_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.shadow_size = int(self.shadow_size / 2.0)
	sb.shadow_offset = self.shadow_offset / 2.0
	sb.shadow_color = self.shadow_color
	sb.corner_radius_top_left = self.corner_radius
	sb.corner_radius_top_right = self.corner_radius
	sb.corner_radius_bottom_right = self.corner_radius
	sb.corner_radius_bottom_left = self.corner_radius
	sb.content_margin_left = self.margin
	sb.content_margin_top = self.margin / 2.0
	sb.content_margin_right = self.margin
	sb.content_margin_bottom = self.margin / 2.0
	return sb


func _make_label(text: String) -> Label:
	var Nlabel := Label.new()
	Nlabel.text = text if text != null else ""
	Nlabel.add_theme_font_override("font", self.font)
	return Nlabel


func _make_line_edit(prompt: String) -> LineEdit:
	var Nline_edit := LineEdit.new()
	Nline_edit.placeholder_text = prompt if prompt != null else ""
	Nline_edit.add_theme_font_override("font", self.font)
	return Nline_edit



## Option 选中项变更 → 更新 _current_show → 重新计算可见性
func _on_option_changed(idx: int, opt_id: String):
	if not _option_map.has(opt_id):
		return
	var items: Array = _option_map[opt_id]["items"]
	if idx < items.size():
		_current_show = items[idx].get("show", "")
	else:
		_current_show = ""
	_apply_visibility()
	queue_sort()


## Button toggle 状态变更 → 更新 _button_states → 重新计算可见性
func _on_button_toggled(pressed: bool, btn_id: String):
	_button_states[btn_id] = "pressed" if pressed else "released"
	_apply_visibility()
	queue_sort()


## 数组交集
func _intersect(a: Array, b: Array) -> Array:
	var result: Array = []
	for x in a:
		if b.has(x):
			result.append(x)
	return result


## 取控件当前值，用于导出 mlog
func _get_element_value(id: String) -> String:
	var el = _elements.get(id)
	if el == null:
		return ""
	if el is LineEdit:
		return el.text
	if el is OptionButton:
		return el.get_item_text(el.selected)
	if el is Button:
		return "true" if el.button_pressed else "false"
	return ""


## 导出为 mlog 指令字符串
## %id   → 取对应控件值
## %a|b  → 取第一个可见且有值的控件值
## 无 % 前缀 → 字面量直接输出
## 所有可见控件均无值 → 输出 "0"
func _export() -> String:
	var raw: String = _block_data.get("export", "")
	if raw == "":
		return ""
	var parts := raw.split(" ")
	var result: Array = []
	for part in parts:
		if part.begins_with("%"):
			var ids = part.substr(1).split("|")
			var value = ""
			for id in ids:
				var el = _elements.get(id)
				if el != null and el.visible:
					value = _get_element_value(id)
					break
			result.append(value if value != "" else "0")
		else:
			result.append(part)
	return " ".join(result) + "\n"


func _get_minimum_size() -> Vector2:
	var min_w := 0.0
	var total_h := 0.0
	for row: Control in self.get_children():
		var row_size := Vector2(0, self.height)
		if row.has_meta("li_tail"):
			row_size = Vector2(self.separation * 8, self.height / 4.0)
		elif row.has_meta("nest_id"):
			var box := row as Box
			var box_min := box.get_combined_minimum_size()
			row_size = Vector2(box_min.x, box_min.y if box.get_child_count() else self.height / 2.0)
		else:
			var row_min := row.get_combined_minimum_size()
			row_size.x = int(row_min.x)
		min_w = max(min_w, row_size.x + self.margin * 4)
		total_h += row_size.y
	return Vector2(min_w, total_h)


## 计算并应用可见性：Option Item show ∩ Button show 空 show 视为所有元素可见，交集控制最终显示
func _apply_visibility():
	var ids: Array
	if _current_show != "":
		var parts = _current_show.split(" ")
		ids.assign(parts)
	else:
		ids.assign(_elements.keys())

	for btn_id in _button_states:
		var state = _button_states[btn_id]
		for el in _block_data.get("elements", []):
			if el.get("id") == btn_id and el.get("type") == "Button":
				var state_show = el.get(state, {}).get("show", "")
				if state_show != "":
					ids = _intersect(ids, state_show.split(" "))
				break

	for id in _elements:
		_elements[id].visible = ids.has(id)


func _on_sort_children():
	_bg_rects.clear()
	_style_boxes.clear()
	var children := self.get_children().filter(func(child): return child.visible)
	var total := children.size()
	var y := 0.0
	for i in total:
		var row: Control = children[i]
		var row_h := self.height
		var row_w := row.size.x
		if row.has_meta("li_tail"):
			row_h = int(self.height / 4.0)
			row_w = self.separation * 8
			fit_child_in_rect(row, Rect2(0, y, row_w, row_h))
		elif row.has_meta("nest_id"):
			var box := row as Box
			row_h = int(box.size.y if box.get_child_count() else self.height / 2.0)
			fit_child_in_rect(row, Rect2(
				self.margin * 2, y + self.margin, 
				row_w, row_h - self.margin * 2
			))
			row_w = 0
		else:
			fit_child_in_rect(row, Rect2(
				self.margin * 2, y + self.margin, 
				row_w, row_h - self.margin * 2
			))
		_bg_rects.append(Rect2(0, y - 1, row_w + self.margin * 4, row_h + 2))
		_style_boxes.append(_make_row_style(row, i, total))
		y += row_h
	queue_redraw()

## 构建行级 StyleBoxFlat：nest 行无圆角，首尾行保留左上 / 左下圆角
func _make_row_style(row: Control, index: int, total: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = self.bg_color
	sb.shadow_size = self.shadow_size
	sb.shadow_offset = self.shadow_offset
	sb.shadow_color = self.shadow_color
	if row.has_meta("nest_id"):
		return sb
	sb.corner_radius_top_right = self.corner_radius
	sb.corner_radius_bottom_right = self.corner_radius
	if index == 0:
		sb.corner_radius_top_left = self.corner_radius
	if index == total - 1:
		sb.corner_radius_bottom_left = self.corner_radius
	return sb


## 鼠标拖拽交互
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			self.drag_started.emit(event.position)
			self.accept_event()


## 逐行绘制圆角背景和阴影
func _draw() -> void:
	for i in _bg_rects.size():
		draw_style_box(_style_boxes[i], _bg_rects[i])
