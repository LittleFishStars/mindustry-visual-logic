class_name BlockLayout
extends Container


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

# 绘制缓存
var _bg_rects: Array[Rect2] = []
var _style_boxes: Array[StyleBoxFlat] = []

# 衍生块
var _nest_block: Dictionary[String, Block] = {}
var _nest_rects: Dictionary[String, Rect2] = {}
var _next_block: Block = null
var _last_block: Block = null



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
		var box_min := row.get_minimum_size()
		return Vector2(box_min.x, box_min.y if row.get_child_count() else self.height / 2.0)
	var row_min := row.get_minimum_size()
	return Vector2(int(row_min.x), self.height)


func _on_sort_children():
	_bg_rects.clear()
	_style_boxes.clear()
	var visible_children: Array[Control] = []
	for c in get_children():
		if c.visible:
			visible_children.append(c)
	var y := 0.0
	
	for i in visible_children.size():
		var child := visible_children[i]
		
		var rs := _get_row_size(child)
		var row_h := rs.y
		var row_w: float = rs.x if child.has_meta("tail") else child.size.x

		if child.has_meta("tail"):
			fit_child_in_rect(child, Rect2(0, y, row_w, row_h))
		else:
			fit_child_in_rect(child, Rect2(
				self.margin * 2, y + self.margin, 	# 位置（减上边距和左边距）
				row_w, row_h - self.margin * 2 		# 大小（减上下边距）
			))

		_bg_rects.append(Rect2(0, y - 1, row_w + self.margin * 4, row_h + 2))
		_style_boxes.append(_make_row_style(child, i, visible_children.size()))
		if child.has_meta("nest_id"):
			var nest_id: String = child.get_meta("nest_id")
			_nest_rects[nest_id] = _bg_rects.back()
			if child.get_child_count():
				_nest_block[nest_id] = child.get_child(0)
		y += row_h
	queue_redraw()

## 构建行级 StyleBoxFlat：nest 行无圆角，首尾行保留左上 / 左下圆角
func _make_row_style(row: Control, index: int, total: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = self.bg_color
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
	for row: Control in get_children():
		if not row.visible:
			continue
		var rs := _get_row_size(row)
		min_w = max(min_w, rs.x + self.margin * 4)
		total_h += rs.y
	return Vector2(min_w, total_h)


func _has_point(point: Vector2) -> bool:
	for rect in _bg_rects:
		if rect.has_point(point):
			return true
	return false


## 鼠标拖拽交互
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _has_point(event.position):
			self.drag_started.emit(event.position)
			self.accept_event()


## 逐行绘制圆角背景和阴影
func _draw() -> void:
	for i in _bg_rects.size():
		draw_style_box(_style_boxes[i], _bg_rects[i])


func get_end_position() -> Vector2:
	return self.position + _bg_rects.back().position + Vector2(0, _bg_rects.back().size.y)
func get_end_width() -> float:
	return _bg_rects.back().size.x

func get_nest_position(nest_id: String) -> Vector2:
	return self.position + _nest_rects[nest_id].position + Vector2(0, _nest_rects[nest_id].size.y)
func get_nest_width(nest_id: String) -> float:
	return _nest_rects[nest_id].size.x

func get_all_rect() -> Rect2:
	var rect = Rect2(Vector2.ZERO, _get_minimum_size())
	if _next_block != null:
		rect.expand(_next_block.get_all_rect().size)
	return rect

func change_position(pos: Vector2):
	self.position = pos
	if self._next_block != null:
		self._next_block.change_position(get_end_position())

func capture_block(block: Block, id: String = ""):
	self._last_block = block
	if id.is_empty():
		if block._next_block == null:
			block._next_block = self
			change_position(block.get_end_position())
		else:
			var old = block._next_block
			block._next_block = self
			change_position(block.get_end_position())
			add_block(old)
	else:
		if block._nest_block[id] == null:
			block._nest_block[id] = self
			change_position(block.get_nest_position(id))
		else:
			var old = block._next_block
			block._nest_block[id] = self
			change_position(block.get_nest_position(id))
			add_block(old)

func add_block(block: Block):
	if self._next_block == null:
		block.capture_block(self)
	else:
		self._next_block.add_block(block)
