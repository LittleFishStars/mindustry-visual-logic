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


func position_of(id: int) -> Vector2:
	var rect: Rect2 = rects.get(id, Rect2())
	return rect.position


func metrics_of(id: int) -> BlockMetrics:
	return metrics.get(id)


## 所有块的并集矩形（画布滚动、居中、导出图片都靠它）。
func bounds() -> Rect2:
	var first := true
	var out := Rect2()
	for id in rects:
		if first:
			out = rects[id]
			first = false
		else:
			out = out.merge(rects[id])
	return out


## 命中测试：返回覆盖 [param point] 的最上层节点 id，没有则返回 0。
## 后加入的块绘制在上层，所以从后往前查。
func node_at(point: Vector2, graph: LogicGraph) -> int:
	var ids := graph.all_ids()
	for i in range(ids.size() - 1, -1, -1):
		var id: int = ids[i]
		var rect: Rect2 = rects.get(id, Rect2())
		# 块之间是竖向相接的，这里把命中区域稍微收窄，避免抢相邻块的点击
		if rect.has_point(point):
			return id
	return 0
