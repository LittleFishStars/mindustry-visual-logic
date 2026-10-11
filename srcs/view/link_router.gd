class_name LinkRouter
extends RefCounted

## 跳线路由：把「哪一块引用了哪一块」算成一组可以直接画的折线。
##
## 纯函数：只读 [LogicGraph] / [BlockLibrary] / [LayoutResult]，不碰控件、不认识画布 ——
## [LinkLayer] 只负责把这里算出的点连成线，[EditorCanvas] 只在布局变化后重新问一次。
##
## 折线形状：从源块左侧中点出发向左绕到一条「母线」（lane）上，竖直走到目标块的高度，
## 最后从左侧进入目标块。竖直区间重叠的线错开道次，不重叠的复用同一条母线。

## 多条跳线共用一条母线时，每条往外错开的距离。
const LANE_GAP: float = 14.0
const LANE_STEP: float = 10.0


## 全部跳线：`[{"points": PackedVector2Array, "color": Color}, …]`。
## [param layout] 为空（还没求解过布局）时返回空数组。
static func segments(graph: LogicGraph, library: BlockLibrary, layout: LayoutResult) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if graph == null or library == null or layout == null:
		return out
	var raw: Array[Dictionary] = []
	for id in graph.all_ids():
		var node := graph.get_node_by_id(id)
		if node == null:
			continue
		var def := library.by_id(node.type_id)
		if def == null:
			continue
		for field_id in def.reference_fields():
			var target := LogicGraph.parse_link_ref(node.get_field(field_id, ""))
			if target <= 0 or not graph.has(target):
				continue
			var start := anchor(layout, id)
			var end := anchor(layout, target)
			raw.append({"start": start, "end": end, "target": target, "span": absf(end.y - start.y)})
	# 短线占内侧道、长线往外让：与旧实现「按距离从短到长排序」同一个意图
	raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["span"]) < float(b["span"]))
	var placed: Array[Dictionary] = []
	for segment in raw:
		var lane := 0
		while _lane_taken(placed, segment, lane):
			lane += 1
		segment["lane"] = lane
		placed.append(segment)
	for segment in placed:
		var start: Vector2 = segment["start"]
		var end: Vector2 = segment["end"]
		var lane_x := minf(start.x, end.x) - LANE_GAP - float(segment["lane"]) * LANE_STEP
		out.append({
			"points": PackedVector2Array([
				start,
				Vector2(lane_x, start.y),
				Vector2(lane_x, end.y),
				end,
			]),
			"color": color_for(int(segment["target"])),
		})
	return out


## 某块在跳线里的出发/到达锚点：块左侧中点（世界坐标）。
static func anchor(layout: LayoutResult, id: int) -> Vector2:
	if layout == null:
		return Vector2.ZERO
	var rect := layout.rect_of(id)
	return Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)


## 同一个目标块永远同色（颜色由节点 id 派生），用户靠颜色 + 走向区分多条线。
static func color_for(target_id: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(target_id)
	return Color.from_hsv(rng.randf(), 0.65, 0.95)


## 该层号上是否已经有「竖直区间与它相交」的线（相交就得换一条道）。
static func _lane_taken(placed: Array[Dictionary], segment: Dictionary, lane: int) -> bool:
	var start: Vector2 = segment["start"]
	var end: Vector2 = segment["end"]
	for other in placed:
		if int(other["lane"]) != lane:
			continue
		var other_start: Vector2 = other["start"]
		var other_end: Vector2 = other["end"]
		if minf(start.y, end.y) < maxf(other_start.y, other_end.y) \
				and maxf(start.y, end.y) > minf(other_start.y, other_end.y):
			return true
	return false
