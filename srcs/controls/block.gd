class_name Block
extends BlockLayout


var _block_data: Dictionary = {}  ## XML 解析后的块原始数据（export + elements 列表）

var _elements: Dictionary = {}  ## id → 已创建的控件（Label / LineEdit / OptionButton / Button / Box）
var _option_map: Dictionary = {}  ## Option id → { button: OptionButton, items: Array }，用于取 show 属性
var _button_states: Dictionary = {}  ## Button id → { state, pressed_show, released_show }
var _current_show: String = ""  ## 当前选中 Option Item 的 show 字符串，空则表示全部可见


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


func _add_to_row(row: HBoxContainer, child: Control) -> HBoxContainer:
	if row == null:
		row = _make_row()
		add_child(row)
	row.add_child(child)
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
				var lbl = Label.new()
				lbl.text = el.get("text", "")
				lbl.add_theme_font_override("font", font)
				_elements[el["id"]] = lbl
				current_row = _add_to_row(current_row, lbl)
			"LineBox":
				var le = LineEdit.new()
				le.placeholder_text = el.get("placeholder", "")
				le.add_theme_font_override("font", font)
				_elements[el["id"]] = le
				current_row = _add_to_row(current_row, le)
			"Option":
				var opt = _make_option(el)
				_elements[el["id"]] = opt
				_option_map[el["id"]] = {"button": opt, "items": el.get("items", [])}
				opt.item_selected.connect(_on_option_changed.bind(el["id"]))
				current_row = _add_to_row(current_row, opt)
			"Button":
				var btn = _make_button(el)
				_elements[el["id"]] = btn
				_button_states[el["id"]] = {
				"state": "released",
				"pressed_show": el["pressed"]["show"],
				"released_show": el["released"]["show"],
			}
				btn.toggled.connect(_on_button_toggled.bind(el["id"]))
				current_row = _add_to_row(current_row, btn)
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
		tail.set_meta("tail", true)
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
	_button_states[btn_id]["state"] = "pressed" if pressed else "released"
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


## 计算并应用可见性：Option Item show ∩ Button show 空 show 视为所有元素可见，交集控制最终显示
func _apply_visibility():
	var ids: Array
	if _current_show != "":
		var parts = _current_show.split(" ")
		ids.assign(parts)
	else:
		ids.assign(_elements.keys())

	for btn_id in _button_states:
		var btn = _button_states[btn_id]
		var show_key = "pressed_show" if btn["state"] == "pressed" else "released_show"
		var state_show = btn[show_key]
		if state_show != "":
			ids = _intersect(ids, state_show.split(" "))

	for id in _elements:
		_elements[id].visible = ids.has(id)
