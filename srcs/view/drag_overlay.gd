class_name DragOverlay
extends Node2D

## 拖拽时的落点预览层：把将要落下的那几个块画成一份**黑色副本**。
##
## （原来这里画的是吸附提示线与高亮框，按需求换成了黑色副本。）

## 落点处那几个块的矩形（画布坐标）。
var rects: Array[Rect2] = []


func set_preview(p_rects: Array[Rect2]) -> void:
	rects = p_rects
	queue_redraw()


func clear() -> void:
	rects = []
	queue_redraw()


func _draw() -> void:
	for rect in rects:
		draw_rect(rect, Color.BLACK)
