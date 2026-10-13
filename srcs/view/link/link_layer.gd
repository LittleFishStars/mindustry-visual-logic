class_name LinkLayer
extends Node2D

## 跳线层：把 [LinkRouter] 算出的折线画出来（本层不做几何计算）；它是 Blocks 的第一个子节点，线只在块间空隙露出。

const LINE_WIDTH: float = 2.0
const ARROW_SIZE: float = 9.0
const PREVIEW_COLOR: Color = Color(1.0, 0.9, 0.4, 0.95)
const PREVIEW_CANCEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.4)
const BAND_FILL: Color = Color(0.30, 0.55, 1.0, 0.10)
const BAND_EDGE: Color = Color(0.45, 0.72, 1.0, 0.95)

## 数据由画布提供（它是唯一知道图与布局的地方）。
var canvas: EditorCanvas


func _draw() -> void:
	if canvas == null:
		return
	for segment in canvas.link_segments():
		var points: PackedVector2Array = segment["points"]
		if points.size() < 2:
			continue
		var color: Color = segment["color"]
		draw_polyline(points, color, LINE_WIDTH, true)
		_draw_arrow(points[points.size() - 2], points[points.size() - 1], color)
	var preview: Dictionary = canvas.link_preview()
	if not preview.is_empty():
		_draw_preview(preview)
	# 框选矩形与跳线同层：都是画布上的叠加提示，不遮挡块身
	if canvas.selection_band_on():
		var band := canvas.selection_band()
		draw_rect(band, BAND_FILL, true)
		draw_rect(band, BAND_EDGE, false, 1.5)


## 目标端箭头：贴着终点朝目标块内侧（不沿最后一段延长）。
func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([
		to,
		to - direction * ARROW_SIZE + normal * ARROW_SIZE * 0.5,
		to - direction * ARROW_SIZE - normal * ARROW_SIZE * 0.5,
	]), color)


## 锁定拖拽中的预览线：命中候选时暖色实线，悬在空白处灰白虚线。
func _draw_preview(preview: Dictionary) -> void:
	var from: Vector2 = preview.get("from", Vector2.ZERO)
	var to: Vector2 = preview.get("to", Vector2.ZERO)
	var valid: bool = bool(preview.get("valid", false))
	var color := PREVIEW_COLOR if valid else PREVIEW_CANCEL_COLOR
	draw_dashed_line(from, to, color, LINE_WIDTH, 7.0, true)
	if valid:
		_draw_arrow(from, to, color)
