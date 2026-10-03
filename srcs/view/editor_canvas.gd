class_name EditorCanvas
extends SubViewport

## 画布：持有逻辑图、撤销栈与所有块视图，负责布局求解与结构变更。
##
## 关键点：块视图之间[b]没有父子关系[/b] —— 全部是 [member nBlocks] 的直接子级，
## 位置一律来自 [LayoutSolver] 的求解结果。旧实现里「拖拽时 reparent 整条链、
## 画布外松手 queue_free 连带删掉下游」的结构性风险在这里不存在。

## 撤销栈或内容变化（供菜单/状态栏刷新）。
signal history_changed()
## 字段值变化（导出内容随之改变）。
signal content_changed()
## 需要编辑器标签页打开选择器浮层。
signal picker_requested(element: ElementDef, control: Control)

@onready var nBlocks: Node2D = $Blocks
## 落点占位块（幽灵视图）及其原始位置
var _preview_views: Array[BlockView] = []
var _preview_origins: Array[Vector2] = []
var _preview_ids: Array[int] = []
## 调色板拖出时，占位块对应的块类型（非空表示当前是"新建"预览）
var _preview_def_id: StringName = &""
@onready var nCamera: EditorCamera = $Camera

var library: BlockLibrary
var graph: LogicGraph
var history: GraphHistory
var layout: LayoutResult = null

var _views: Dictionary[int, BlockView] = {}
var _applying_field: bool = false


func setup(p_library: BlockLibrary, p_graph: LogicGraph = null) -> void:
	library = p_library
	graph = p_graph if p_graph != null else LogicGraph.new()
	history = GraphHistory.new(graph)
	graph.structure_changed.connect(_on_structure_changed)
	graph.reset.connect(_on_graph_reset)
	graph.field_changed.connect(_on_field_changed)
	history.changed.connect(func() -> void: history_changed.emit())
	rebuild()


## 换成另一张图（打开项目用）：断开旧信号、接上新图并重建视图与撤销栈。
func adopt_graph(p_graph: LogicGraph) -> void:
	if graph == p_graph:
		return
	if graph != null:
		graph.structure_changed.disconnect(_on_structure_changed)
		graph.reset.disconnect(_on_graph_reset)
		graph.field_changed.disconnect(_on_field_changed)
	graph = p_graph if p_graph != null else LogicGraph.new()
	graph.structure_changed.connect(_on_structure_changed)
	graph.reset.connect(_on_graph_reset)
	graph.field_changed.connect(_on_field_changed)
	history = GraphHistory.new(graph)
	history.changed.connect(func() -> void: history_changed.emit())
	rebuild()


#region 视图与布局

## 按当前图整体重建块视图（撤销/读档/首次打开走这里）。
func rebuild() -> void:
	for id in _views.keys():
		var view: BlockView = _views[id]
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	for id in graph.all_ids():
		_create_view(id)
	relayout()


func relayout() -> void:
	if library == null:
		return
	layout = LayoutSolver.solve(graph, _measure)
	for id in _views:
		var view: BlockView = _views[id]
		if not is_instance_valid(view):
			continue
		var rect := layout.rect_of(id)
		view.position = rect.position
		view.size = rect.size
	content_changed.emit()


func _measure(node: LogicNode, slot_extents: Dictionary[StringName, Vector2]) -> BlockMetrics:
	var view: BlockView = _views.get(node.id)
	if view == null or not is_instance_valid(view):
		# 视图还没建（首次求解）时先建出来再量
		view = _create_view(node.id)
	if view == null:
		return BlockMetrics.new()
	return view.measure(slot_extents)


func view_of(id: int) -> BlockView:
	return _views.get(id)


func _create_view(id: int) -> BlockView:
	var node := graph.get_node_by_id(id)
	if node == null:
		return null
	var def := library.by_id(node.type_id) if library != null else null
	if def == null:
		push_warning("未知块类型：%s（节点 %d）" % [node.type_id, id])
		return null
	var view := BlockView.new()
	view.name = "Block%d" % id
	view.drag_requested.connect(_on_view_drag_requested)
	view.field_committed.connect(_on_view_field_committed)
	view.layout_dirty.connect(_on_view_layout_dirty)
	view.picker_requested.connect(func(element: ElementDef, control: Control) -> void:
		picker_requested.emit(element, control))
	view.history_group_closed.connect(func() -> void:
		history.flush_merge())
	nBlocks.add_child(view)
	view.setup(def, node, false)
	_views[id] = view
	return view


func _on_view_drag_requested(view: BlockView, offset: Vector2) -> void:
	drag_requested.emit(view, offset)


## 由拖拽控制器接管的开始拖动请求。
signal drag_requested(view: BlockView, offset: Vector2)
func _on_view_layout_dirty() -> void:
	relayout()


## 视图内控件改了字段：写进图并记进撤销栈（视图自己发起的改动不回灌控件，避免打断输入）。
func _on_view_field_committed(node: LogicNode, field_id: StringName, value: Variant, merge_key: StringName) -> void:
	_applying_field = true
	history.record("修改 %s" % String(field_id), func() -> void:
		graph.set_field(node.id, field_id, value), merge_key)
	_applying_field = false
	var view: BlockView = _views.get(node.id)
	if view != null and is_instance_valid(view):
		view.refresh_visibility()
	relayout()

#endregion


## 新建一个块并放到 [param owner_id] 的 [param slot_id] 容器里。
func insert_new_node(type_id: StringName, owner_id: int, slot_id: StringName, index: int, label: String = "添加块") -> LogicNode:
	# 先把节点建好（未入图），再放进栈里执行 —— GDScript 的 lambda 按值捕获，
	# 不能在闭包里给外部变量赋值
	var node := _make_node(type_id)
	history.record(label, func() -> void:
		graph.insert_node(node, owner_id, slot_id, index))
	return node


## 在画布空白处新建一条链。
func insert_new_chain(type_id: StringName, world_pos: Vector2, label: String = "添加块") -> LogicNode:
	var node := _make_node(type_id)
	history.record(label, func() -> void:
		var chain := graph.create_chain(world_pos)
		graph.insert_node(node, LogicGraph.ROOT, chain, -1))
	return node


func move_node(id: int, owner_id: int, slot_id: StringName, index: int) -> bool:
	if not graph.has(id):
		return false
	history.record("移动块", func() -> void:
		graph.move_node(id, owner_id, slot_id, index))
	return true


func move_tail(ids: Array[int], owner_id: int, slot_id: StringName, index: int) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	history.record("移动块", func() -> void:
		graph.move_tail(ids, owner_id, slot_id, index))
	return true


## 把一串块整体搬到画布上的一条新链。
func move_tail_to_new_chain(ids: Array[int], world_pos: Vector2) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	history.record("移动块", func() -> void:
		var chain := graph.create_chain(world_pos)
		graph.move_tail(ids, LogicGraph.ROOT, chain, -1))
	return true


func remove_node(id: int) -> bool:
	if not graph.has(id):
		return false
	history.record("删除块", func() -> void:
		graph.remove_node(id))
	return true


## 撤销/重做：history 内部会 load_dict，图发出 reset 信号后画布自行重建。
func undo() -> bool:
	return history.undo()


func redo() -> bool:
	return history.redo()


## 建节点并预置字段默认值（旧版把默认值写在输入框里，这里挪进数据层）。
func _make_node(type_id: StringName) -> LogicNode:
	var node := graph.new_node(type_id)
	var def := library.by_id(type_id) if library != null else null
	if def != null:
		for field_id in def.default_field_values():
			node.fields[field_id] = def.default_field_values()[field_id]
	return node

#endregion


#region 坐标与拖拽辅助

## 屏幕坐标 → 画布世界坐标（[param area_rect] 是 SubViewportContainer 的全局矩形）。
func world_from_screen(area_rect: Rect2, screen_pos: Vector2) -> Vector2:
	var local := screen_pos - area_rect.position
	return get_canvas_transform().affine_inverse() * local


func anchors() -> Array[Dictionary]:
	return layout.anchors if layout != null else []


## 找一个可落点的锚点：优先命中鼠标附近的插入线。
func find_anchor(world_pos: Vector2, radius: float, exclude: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_cost := INF
	for anchor in anchors():
		var from_id: int = anchor.get("from_id", 0)
		if exclude.has(from_id):
			continue
		var owner_id: int = anchor.get("owner_id", 0)
		if owner_id != LogicGraph.ROOT and exclude.has(owner_id):
			continue
		var origin: Vector2 = anchor["position"]
		var width: float = maxf(float(anchor["width"]), 12.0)
		var dy := absf(world_pos.y - origin.y)
		if dy > radius:
			continue
		if world_pos.x < origin.x - radius or world_pos.x > origin.x + width + radius:
			continue
		var cost := dy + absf(world_pos.x - clampf(world_pos.x, origin.x, origin.x + width)) * 0.25
		if cost < best_cost:
			best_cost = cost
			best = anchor
	return best


## 造一个拖拽幽灵/调色板样品：绑定临时节点，不写历史。
func make_ghost(type_id: StringName) -> BlockView:
	var def := library.by_id(type_id) if library != null else null
	if def == null:
		return null
	var temp := LogicNode.new(0, type_id)
	for field_id in def.default_field_values():
		temp.fields[field_id] = def.default_field_values()[field_id]
	var ghost := BlockView.new()
	ghost.interactive = false
	nBlocks.add_child(ghost)
	ghost.setup(def, temp, true)
	ghost.z_index = 50
	return ghost


## 落点占位块：把"如果现在放下会落下哪几个块"摆成一组幽灵视图。
##
## 复用 [method make_ghost]（半透明、不吃鼠标），但改成显示[b]真实字段值[/b]，
## 这样看到的就是"现在放下的样子"。视图只在目标集合变化时重建，之后每帧只更新位置。
func show_placement_preview(ids: Array[int], offset: Vector2) -> void:
	if ids != _preview_ids or _preview_def_id != &"":
		clear_placement_preview()
		_preview_ids = ids.duplicate()
		_preview_origins.clear()
		for id in ids:
			var node := graph.get_node_by_id(id)
			if node == null:
				continue
			var def := library.by_id(node.type_id)
			var ghost := make_ghost(node.type_id)
			if ghost == null or def == null:
				continue
			ghost.setup(def, node, false)
			ghost.modulate = Color(1, 1, 1, 0.5)
			_preview_views.append(ghost)
			_preview_origins.append(layout.rect_of(id).position if layout != null else Vector2.ZERO)
	for i in _preview_views.size():
		if i < _preview_origins.size():
			_preview_views[i].position = _preview_origins[i] + offset


## 调色板拖出时的落点占位块：将要新建的那个块（默认值就是它入图时的取值）。
func show_new_placement_preview(def: BlockDef, top_left: Vector2) -> void:
	if def == null:
		clear_placement_preview()
		return
	if _preview_def_id != def.id:
		clear_placement_preview()
		_preview_def_id = def.id
		var ghost := make_ghost(def.id)
		if ghost != null:
			ghost.modulate = Color(1, 1, 1, 0.5)
			ghost.measure({})
			_preview_views.append(ghost)
	for view in _preview_views:
		if is_instance_valid(view):
			view.position = top_left


## 落点占位块的总高度（"插在中间"时用它给后面的块让位）。
func placement_preview_height() -> float:
	var total := 0.0
	for view in _preview_views:
		if is_instance_valid(view):
			total += maxf(view.metrics.size.y if view.metrics != null else view.size.y, 1.0)
	return total


func clear_placement_preview() -> void:
	for view in _preview_views:
		if is_instance_valid(view):
			view.queue_free()
	_preview_views.clear()
	_preview_origins.clear()
	_preview_ids.clear()
	_preview_def_id = &""

#endregion


#region 图信号

func _on_structure_changed() -> void:
	_sync_views()
	relayout()


func _on_graph_reset() -> void:
	rebuild()


func _on_field_changed(id: int, _field_id: StringName, _value: Variant) -> void:
	if _applying_field:
		return
	var view: BlockView = _views.get(id)
	if view != null and is_instance_valid(view):
		view.sync_from_data()
	relayout()


## 结构变化后对齐视图集合：新增的建、消失的删，其余保持（避免重建打断输入）。
func _sync_views() -> void:
	var alive: Dictionary[int, bool] = {}
	for id in graph.all_ids():
		alive[id] = true
		if not _views.has(id) or not is_instance_valid(_views[id]):
			_create_view(id)
	for id in _views.keys():
		if not alive.has(id):
			var view: BlockView = _views[id]
			if is_instance_valid(view):
				view.queue_free()
			_views.erase(id)

#endregion
