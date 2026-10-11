class_name LayoutResult
extends RefCounted

## 一次布局求解的结果：每个块的矩形、几何度量与全部吸附锚点（只读）。

## 节点 id → 画布矩形（position 为块左上角，size 为块尺寸）。
var rects: Dictionary[int, Rect2] = {}

var metrics: Dictionary[int, BlockMetrics] = {}

## 吸附锚点，元素为 {owner_id, slot, index, position, width, kind, from_id}。
var anchors: Array[Dictionary] = []



func rect_of(id: int) -> Rect2:
	return rects.get(id, Rect2())
