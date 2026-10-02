class_name BlockMetrics
extends RefCounted

## 一个块自身的几何度量结果（相对块左上角，单位与画布一致）。
##
## 由 [b]定义层[/b] 的度量函数算出：它知道自己的行、间距、圆角与槽位位置，
## 并接收「各槽位内子链的总尺寸」作为输入 —— 于是尺寸永远是自底向上算出来的，
## 不依赖任何控件是否排过版。

## 块自身尺寸。
var size: Vector2 = Vector2.ZERO

## 尾部吸附：下一个兄弟块的落点（相对块左上角）与吸附线宽度。
var tail_offset: Vector2 = Vector2.ZERO
var tail_width: float = 0.0

## 子槽位：槽位 id → 槽内第一个子块的落点（相对块左上角）。
var slot_offsets: Dictionary[StringName, Vector2] = {}

## 子槽位：槽位 id → 吸附线宽度。
var slot_widths: Dictionary[StringName, float] = {}


## 槽位是否参与布局。
func has_slot(slot_id: StringName) -> bool:
	return slot_offsets.has(slot_id)


func slot_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(slot_offsets.keys())
	return out
