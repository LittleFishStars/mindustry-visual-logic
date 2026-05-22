class_name BaseBlock
extends Container


@export var margin: int = 6
@export var separation: int = 10
@export var height: int = 40


@export_group("styles")
@export var bg_color: Color
@export var corner_radius: int = 10
@export var shadow_size: int = 4
@export var shadow_offset: Vector2 = Vector2(2, 4)
@export var shadow_color: Color = Color(0, 0, 0, 0.3)

var _bg_rects: Array[Rect2] = []
var _style_boxes: Array[StyleBoxFlat] = []


class Box extends VBoxContainer:
	func _ready() -> void:
		self.add_theme_constant_override("separation", 0)


func _init(
	template: String,
	options: Dictionary[String, Variant] = {},
	color: Color = Color.WHITE
) -> void:
	self.parsing(template, options)
	self.bg_color = color
	self.sort_children.connect(self._on_sort_children)
	self.theme = load("res://Stytes/block.tres")


func _create_element(element: String, options: Dictionary) -> Control:
	if element.begins_with("%"):
		var tmp := element.substr(1).split(".")
		var t := tmp[0]               # token: in/bu/op/li
		var p := tmp.get(1)           # payload: placeholder/key/label
		match t:
			"in":
				return self.line_edit(p)
			"bu":
				return self.button(p.get_slice("@", 1), options[p.get_slice("@", 0)])
			"op":
				return self.option_button(options[p])
			"li":
				return Box.new()
	return self.label(element)


## 解析块样式，按换行分行，每行创建一个 HBoxContainer
func parsing(template: String, options: Dictionary[String, Variant] = {}):
	var lines := template.split("\n", false)
	for i in lines.size():
		var elements := lines[i].split(" ", false)
		if elements.is_empty():
			continue
		if elements.size() == 1 and elements[0] == "%li":
			# 嵌套 Box：独占一行
			var box := Box.new()
			box.set_meta("li_row", true)
			self.add_child(box)
			if i == lines.size() - 1:
				var tail := Control.new()
				tail.set_meta("li_tail", true)
				self.add_child(tail)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", self.separation)
			for element: String in elements:
				row.add_child(self._create_element(element, options))
			self.add_child(row)
	self.queue_redraw()


func label(text: String) -> Label:
	var Nlabel := Label.new()
	Nlabel.text = text if text != null else ""
	return Nlabel

## 按钮 StyleBoxFlat 复用：阴影、全四角圆角、内容边距
func _btn_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	# 阴影
	sb.shadow_size = int(self.shadow_size / 2.0)
	sb.shadow_offset = self.shadow_offset / 2.0
	sb.shadow_color = self.shadow_color
	# 圆角
	sb.corner_radius_top_left = self.corner_radius
	sb.corner_radius_top_right = self.corner_radius
	sb.corner_radius_bottom_right = self.corner_radius
	sb.corner_radius_bottom_left = self.corner_radius
	# 边距
	sb.content_margin_left = self.margin
	sb.content_margin_top = self.margin / 2.0
	sb.content_margin_right = self.margin
	sb.content_margin_bottom = self.margin / 2.0
	return sb

## 积木内置按钮：normal/hover/pressed 三态皆基于 bg_color 调亮暗
func button(text: String, pressed: Callable) -> Button:
	var Nbutton := Button.new()
	Nbutton.text = text
	Nbutton.pressed.connect(pressed)
	Nbutton.add_theme_stylebox_override("normal", _btn_style(self.bg_color))
	Nbutton.add_theme_stylebox_override("hover", _btn_style(self.bg_color.lightened(0.15)))
	Nbutton.add_theme_stylebox_override("pressed", _btn_style(self.bg_color.darkened(0.1)))
	return Nbutton

func line_edit(prompt: String) -> LineEdit:
	var Nline_edit := LineEdit.new()
	Nline_edit.placeholder_text = prompt if prompt != null else ""
	return Nline_edit

func option_button(options: Array[String]) -> OptionButton:
	var Noption_button := OptionButton.new()
	for o in options:
		Noption_button.add_item(o)
	return Noption_button


## 计算最小尺寸，用于布局系统确定积木所需空间
func _get_minimum_size() -> Vector2:
	var min_w := 0.0
	var total_h := 0.0
	for row: Control in self.get_children():
		var row_h := self.height
		var row_w: int
		if row.has_meta("li_tail"):
			row_h = int(self.height / 4.0)      # 尾行，细条
			row_w = self.separation * 8
		elif row.has_meta("li_row"):
			var box := row as Box
			var box_min := box.get_combined_minimum_size()
			row_h = int(box_min.y if box.get_child_count() else self.height / 2.0)
			row_w = int(box_min.x)              # Box 内部撑开
		else:
			var row_min := row.get_combined_minimum_size()
			row_w = int(row_min.x)              # HBoxContainer 内部撑开
		min_w = max(min_w, row_w + self.margin * 4)
		total_h += row_h
	return Vector2(min_w, total_h)


func _on_sort_children():
	_bg_rects.clear()
	_style_boxes.clear()
	var children := self.get_children()
	var total := children.size()
	var y := 0.0                       # 当前行 y 偏移
	for i in total:
		var row: Control = children[i]
		var row_h := self.height
		var row_w := row.size.x
		if row.has_meta("li_tail"):           # 尾行：缩进 + 固定尺寸
			row_h = int(self.height / 4.0)
			row_w = self.separation * 8
			fit_child_in_rect(row, Rect2(0, y, row_w, row_h))
		elif row.has_meta("li_row"):           # 嵌套 Box：动态高度
			var box := row as Box
			row_h = int(box.size.y if box.get_child_count() else self.height / 2.0)
			fit_child_in_rect(row, Rect2(
				self.margin * 2, y + self.margin, 
				row_w, row_h - self.margin * 2
			))
			row_w = 0
		else:                                  # 普通行：HBoxContainer
			fit_child_in_rect(row, Rect2(
				self.margin * 2, y + self.margin, 
				row_w, row_h - self.margin * 2
			))
		_bg_rects.append(Rect2(0, y - 1, row_w + self.margin * 4, row_h + 2))
		_style_boxes.append(_make_row_style(row, i, total))
		y += row_h
	queue_redraw()


## 构建行级 StyleBoxFlat，首行/末行/中间行圆角配置不同，%li 行无圆角
func _make_row_style(row: Control, index: int, total: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = self.bg_color
	sb.shadow_size = self.shadow_size
	sb.shadow_offset = self.shadow_offset
	sb.shadow_color = self.shadow_color
	if row.has_meta("li_row"):
		return sb                        # li 行不设圆角
	sb.corner_radius_top_right = self.corner_radius
	sb.corner_radius_bottom_right = self.corner_radius
	if index == 0:
		sb.corner_radius_top_left = self.corner_radius    # 首行开左上
	if index == total - 1:
		sb.corner_radius_bottom_left = self.corner_radius # 末行开左下
	return sb


## 逐行绘制圆角矩形背景和阴影
func _draw() -> void:
	for i in _bg_rects.size():
		draw_style_box(_style_boxes[i], _bg_rects[i])


func export(): pass
