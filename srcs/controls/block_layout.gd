class_name BlockLayout
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

## 绘制缓存
var _bg_rects: Array[Rect2] = []
var _style_boxes: Array[StyleBoxFlat] = []


## 嵌套子块容器（If 块的 <Nest>）
class Box extends VBoxContainer:
	func _ready() -> void:
		self.add_theme_constant_override("separation", 0)


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


func _get_row_size(row: Control) -> Vector2:
	if row.has_meta("tail"):
		return Vector2(self.separation * 8, self.height / 4.0)
	if row.has_meta("nest_id"):
		var box := row as Box
		var box_min := box.get_minimum_size()
		return Vector2(box_min.x, box_min.y if box.get_child_count() else self.height / 2.0)
	var row_min := row.get_minimum_size()
	return Vector2(int(row_min.x), self.height)


func _on_sort_children():
	_bg_rects.clear()
	_style_boxes.clear()
	var visible_rows: Array[Control] = []
	for c in get_children():
		if c.visible:
			visible_rows.append(c)
	var y := 0.0
	
	for i in visible_rows.size():
		var row := visible_rows[i]
		var rs := _get_row_size(row)
		var row_h := rs.y
		var row_w := rs.x if row.has_meta("tail") else row.size.x

		if row.has_meta("tail"):
			fit_child_in_rect(row, Rect2(0, y, row_w, row_h))
		else:
			fit_child_in_rect(row, Rect2(
				self.margin * 2, y + self.margin, 	# 位置（减上边距和左边距）
				row_w, row_h - self.margin * 2 		# 大小（减上下边距）
			))

		_bg_rects.append(Rect2(0, y - 1, row_w + self.margin * 4, row_h + 2))
		_style_boxes.append(_make_row_style(row, i, visible_rows.size()))
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


func _get_minimum_size() -> Vector2:
	var min_w := 0.0
	var total_h := 0.0
	for row: Control in self.get_children():
		if not row.visible:
			continue
		var rs := _get_row_size(row)
		min_w = max(min_w, rs.x + self.margin * 4)
		total_h += rs.y
	return Vector2(min_w, total_h)


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
