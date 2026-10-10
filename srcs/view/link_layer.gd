class_name LinkLayer
extends Node2D

## 跳线层：把「哪个 Jump 跳到哪一块」画成彩色折线 + 箭头。
##
## 线的形状：从源块左侧出发向左绕到一条「母线」（lane）上，竖直走到目标块的高度，
## 最后从左侧进入目标块 —— 折线的三个拐点全部来自 [method EditorCanvas.link_segments]
## 给出的位置，本层只负责画，不做任何几何计算（位置绝不从绘制缓存反读）。
##
## 它是 [b]Blocks 的第一个子节点[/b]：先绘制意味着线被块盖住，于是线只在块与块之间
## 的空隙里露出来；悬停高亮由块自己描边（见 [method BlockView.set_link_highlight]）。
##
## 颜色按目标块取（同一目标同色），而哪块颜色由种子决定 —— 用户靠颜色+走向区分多条线。

const LINE_WIDTH: float = 2.0
const ARROW_SIZE: float = 9.0
const PREVIEW_COLOR: Color = Color(1.0, 0.9, 0.4, 0.95)
const PREVIEW_CANCEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.4)

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


## 目标端的箭头：不画在最后一段的延长线上，而是贴着终点朝目标块内侧。
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


## 锁定拖拽中的预览线：命中候选时是暖色实意，悬在空白处时是灰白虚线。
func _draw_preview(preview: Dictionary) -> void:
	var from: Vector2 = preview.get("from", Vector2.ZERO)
	var to: Vector2 = preview.get("to", Vector2.ZERO)
	var valid: bool = bool(preview.get("valid", false))
	var color := PREVIEW_COLOR if valid else PREVIEW_CANCEL_COLOR
	draw_dashed_line(from, to, color, LINE_WIDTH, 7.0, true)
	if valid:
		_draw_arrow(from, to, color)
