class_name DragOverlay
extends Node2D

## 拖拽时的吸附提示层。
##
## 旧实现只做吸附判定、不画任何东西，用户看不到「会吸到哪」；
## 这里把当前命中的锚点画成一条高亮插入线，并给人眼一个宽度参考。

const COLOR_IDLE: Color = Color(1, 1, 1, 0.18)
const COLOR_TARGET: Color = Color(1, 0.78, 0.24, 0.95)
const LINE_THICKNESS: float = 3.0
const CAP_RADIUS: float = 4.0

## 是否显示全部候选锚点（拖拽中为 true，便于看清可插入的位置）。
var show_all: bool = false
## 当前命中的锚点；空字典表示没有命中。
var target: Dictionary = {}
var anchors: Array[Dictionary] = []


func set_state(p_show_all: bool, p_anchors: Array[Dictionary], p_target: Dictionary) -> void:
	show_all = p_show_all
	anchors = p_anchors
	target = p_target
	queue_redraw()


func clear() -> void:
	show_all = false
	anchors = []
	target = {}
	queue_redraw()


func _draw() -> void:
	if show_all:
		for anchor in anchors:
			_draw_anchor(anchor, COLOR_IDLE, 1.5, CAP_RADIUS * 0.6)
	if not target.is_empty():
		_draw_anchor(target, COLOR_TARGET, LINE_THICKNESS, CAP_RADIUS)


func _draw_anchor(anchor: Dictionary, color: Color, thickness: float, cap: float) -> void:
	var origin: Vector2 = anchor.get("position", Vector2.ZERO)
	var width: float = maxf(float(anchor.get("width", 0.0)), 12.0)
	draw_line(origin, origin + Vector2(width, 0), color, thickness)
	draw_circle(origin, cap, color)
	draw_circle(origin + Vector2(width, 0), cap, color)
