class_name LayoutSolver
extends RefCounted

## 布局求解：**纯函数**，不碰任何控件、不依赖任何"是否排过版"的状态。
##
## 三趟完成：
##   1. 自底向上量尺寸 —— 子链先算出总尺寸，父块才知道槽位要留多大；
##   2. 自顶向下摆位置 —— 从每条根链的落点出发，兄弟块按 tail_offset 依次往下推；
##   3. 收集吸附锚点 —— 位置已知后，锚点就是位置的直接函数。
##
## 度量函数由 [b]定义层[/b] 提供，签名：
## [code]func(node: LogicNode, slot_extents: Dictionary[StringName, Vector2]) -> BlockMetrics[/code]
## 其中 [param slot_extents] 只包含 [b]图上真实存在[/b] 的槽位，
## 度量函数对未出现的槽位应自行按 [constant Vector2.ZERO] 处理。


static func solve(graph: LogicGraph, measure: Callable) -> LayoutResult:
	var result := LayoutResult.new()
	if graph == null or not measure.is_valid():
		return result
	var measured: Dictionary[int, bool] = {}
	for chain_id in graph.chain_ids():
		for head_id in graph.slot_items(LogicGraph.ROOT, chain_id):
			_measure_node(graph, measure, head_id, result, measured)
	var placed: Dictionary[int, bool] = {}
	for chain_id in graph.chain_ids():
		_place_chain(
			graph, result, graph.slot_items(LogicGraph.ROOT, chain_id),
			graph.chain_position(chain_id), LogicGraph.ROOT, chain_id, placed
		)
	return result


static func _measure_node(
	graph: LogicGraph,
	measure: Callable,
	id: int,
	result: LayoutResult,
	measured: Dictionary[int, bool]
) -> void:
	if measured.has(id) or result.metrics.has(id):
		return
	# 先打标记，防止损坏数据里的环把递归拖死
	measured[id] = true
	var node := graph.get_node_by_id(id)
	if node == null:
		return
	var slot_extents: Dictionary[StringName, Vector2] = {}
	for slot_id in node.slots:
		var children := node.peek_slot(slot_id)
		for child_id in children:
			_measure_node(graph, measure, child_id, result, measured)
		slot_extents[slot_id] = _chain_extent(children, result)
	var metrics: BlockMetrics = measure.call(node, slot_extents)
	result.metrics[id] = metrics if metrics != null else BlockMetrics.new()


## 一条链的总尺寸：宽 = 最宽成员，高 = 首个成员顶到末尾成员底。
static func _chain_extent(ids: Array[int], result: LayoutResult) -> Vector2:
	var width := 0.0
	var height := 0.0
	var previous: BlockMetrics = null
	for id in ids:
		var metrics: BlockMetrics = result.metrics.get(id)
		if metrics == null:
			continue
		width = maxf(width, metrics.size.x)
		if previous != null:
			height += previous.tail_offset.y
		previous = metrics
	if previous != null:
		height += previous.size.y
	return Vector2(width, height)


static func _place_chain(
	graph: LogicGraph,
	result: LayoutResult,
	ids: Array[int],
	origin: Vector2,
	owner_id: int,
	slot_id: StringName,
	placed: Dictionary[int, bool]
) -> void:
	var cursor := origin
	for index in ids.size():
		var id: int = ids[index]
		if placed.has(id):
			continue
		var metrics: BlockMetrics = result.metrics.get(id)
		if metrics == null:
			continue
		placed[id] = true
		result.rects[id] = Rect2(cursor, metrics.size)
		# 尾部锚点：插在"我这个块之后"
		result.anchors.append({
			"owner_id": owner_id,
			"slot": slot_id,
			"index": index + 1,
			"position": cursor + metrics.tail_offset,
			"width": metrics.tail_width,
			"kind": &"tail",
			"from_id": id,
		})
		# 槽位锚点：插进槽内容的最前面（与旧实现"嵌套即成为首个子块"一致）
		for slot_key in metrics.slot_offsets:
			result.anchors.append({
				"owner_id": id,
				"slot": slot_key,
				"index": 0,
				"position": cursor + metrics.slot_offsets[slot_key],
				"width": metrics.slot_widths.get(slot_key, metrics.size.x),
				"kind": &"slot",
				"from_id": id,
			})
			_place_chain(
				graph, result, graph.slot_items(id, slot_key),
				cursor + metrics.slot_offsets[slot_key], id, slot_key, placed
			)
		cursor += metrics.tail_offset
