class_name LayoutResult
extends RefCounted

## 一次布局求解的完整结果：每个块的位置、它的几何度量、以及所有吸附锚点。
##
## 视图层与拖拽控制器都只读这一份结果 —— 旧实现里「位置要从绘制缓存反读」
## 的问题在这里消失：布局是纯函数输出，什么时候读都是对的。

## 节点 id → 画布矩形（position 为块左上角，size 为块尺寸）。
var rects: Dictionary[int, Rect2] = {}

## 节点 id → 几何度量。
var metrics: Dictionary[int, BlockMetrics] = {}

## 吸附锚点，元素为 {owner_id, slot, index, position, width, kind, from_id}。
var anchors: Array[Dictionary] = []


func has(id: int) -> bool:
	return rects.has(id)


func rect_of(id: int) -> Rect2:
	return rects.get(id, Rect2())


