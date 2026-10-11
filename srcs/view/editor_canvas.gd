class_name EditorCanvas
extends SubViewport

## 画布：持有逻辑图、撤销栈与所有块视图，负责布局求解与结构变更。
##
## 关键点：块视图之间[b]没有父子关系[/b] —— 全部是 [member nBlocks] 的直接子级，
## 位置一律来自 [LayoutSolver] 的求解结果。旧实现里「拖拽时 reparent 整条链、
## 画布外松手 queue_free 连带删掉下游」的结构性风险在这里不存在。

## 需要编辑器标签页打开选择器浮层。
signal picker_requested(view: BlockView, element: ElementDef, control: Control)
## 需要编辑器标签页接管「拖拽锁定跳转目标」（见 [LinkController]）。
signal link_requested(view: BlockView, element: ElementDef, control: Control)
## 右键在块上按下：要拖出一份副本（见 [method duplicate_subtree]）。
signal copy_requested(view: BlockView, offset: Vector2)

@onready var nBlocks: Node2D = $Blocks
## 跳线层（Blocks 的第一个子节点，见 [LinkLayer]）。
@onready var nLinks: LinkLayer = $Links
## 落点占位块（幽灵视图）：状态全在 [PlacementPreview] 里，画布只留一层转发。
var _placement: PlacementPreview = null
@onready var nCamera: EditorCamera = $Camera

var library: BlockLibrary
var graph: LogicGraph
var history: GraphHistory
var layout: LayoutResult = null

var _views: Dictionary[int, BlockView] = {}
var _applying_field: bool = false
## 跳线数据（线段 + 颜色），由 [method _refresh_links] 在每次布局后重算。
var _segments: Array[Dictionary] = []
## 锁定拖拽的预览线：{from, to, valid}；空字典 = 没在拖。
var _preview: Dictionary = {}
## 当前被高亮描边圈住的块（0 = 没有）。
var _highlight_id: int = 0



func setup(p_library: BlockLibrary, p_graph: LogicGraph = null) -> void:
	library = p_library
	_placement = PlacementPreview.new(self)
	# 跳线层要拿图与布局才画得出线（它在 scene 里是 Blocks 的第一个子节点）
	nLinks.canvas = self
	_attach_graph(p_graph)


## 换成另一张图（打开项目用）：断开旧信号、接上新图并重建视图与撤销栈。
func adopt_graph(p_graph: LogicGraph) -> void:
	if graph == p_graph:
		return
	_attach_graph(p_graph)


## 建图接线只在这一处：setup 与 adopt_graph 共用同一条路径。
func _attach_graph(p_graph: LogicGraph) -> void:
	if graph != null:
		graph.structure_changed.disconnect(_on_structure_changed)
		graph.reset.disconnect(_on_graph_reset)
		graph.field_changed.disconnect(_on_field_changed)
	graph = p_graph if p_graph != null else LogicGraph.new()
	graph.structure_changed.connect(_on_structure_changed)
	graph.reset.connect(_on_graph_reset)
	graph.field_changed.connect(_on_field_changed)
	history = GraphHistory.new(graph)
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
	_refresh_links()


## 拖拽期间统一开关所有块视图里的可交互控件（拖拽只搬位置，不该顺手改数据）。
func set_elements_enabled(enabled: bool) -> void:
	for id in _views:
		var view: BlockView = _views[id]
		if is_instance_valid(view):
			view.set_elements_enabled(enabled)


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



## 现有内容占的矩形（世界坐标，取所有块视图的并集；什么也没有时返回空矩形）。
##
## Ctrl+V 靠它把新链摆到现有内容[b]下面[/b]——不接在入口块那条链上，另起一条。
func content_rect() -> Rect2:
	var out := Rect2()
	var first := true
	for id in _views:
		var view: BlockView = _views[id]
		if view == null or not is_instance_valid(view):
			continue
		var rect := Rect2(view.position, view.size)
		out = rect if first else out.merge(rect)
		first = false
	return out
## 这个节点是不是入口块（XML `entry="true"`，目前是 Start）。
## 一个文档只该有一个：不放复制、不准删，导出也从它开始。
func is_entry(node: LogicNode) -> bool:
	return node != null and library != null and library.is_entry(node.type_id)

## 某节点各槽位在[b]当前布局[/b]里的尺寸（巢里子链的总尺寸）。
## 幽灵与落点占位块拿它再量一次自己 —— 否则带巢的块（If）副本只看得见空巢，
## 拖动时会比本体矮一截，巢里的子块也就“掉”到块外面了。
func slot_extents_of(id: int) -> Dictionary[StringName, Vector2]:
	var out: Dictionary[StringName, Vector2] = {}
	var node := graph.get_node_by_id(id)
	if node == null or layout == null:
		return out
	for slot_id in node.slots:
		out[slot_id] = LayoutSolver.chain_extent(node.peek_slot(slot_id), layout)
	return out


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
	view.copy_requested.connect(func(v: BlockView, offset: Vector2) -> void:
		copy_requested.emit(v, offset))
	view.link_labeler = _link_label
	view.link_requested.connect(func(v: BlockView, element: ElementDef, control: Control) -> void:
		link_requested.emit(v, element, control))
	view.field_committed.connect(_on_view_field_committed)
	view.layout_dirty.connect(_on_view_layout_dirty)
	view.picker_requested.connect(func(v: BlockView, element: ElementDef, control: Control) -> void:
		picker_requested.emit(v, element, control))
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
	# 被删的块可能是别的 Jump 的目标：指向它们的引用要一并清掉（同一撤销记录）
	var doomed: Dictionary = {}
	for victim in graph.subtree_ids(id):
		doomed[victim] = true
	history.record("删除块", func() -> void:
		graph.remove_node(id)
		_clear_links_to(doomed))
	return true


## 删除一串块（被拖走的那整串）——一次撤销记录，整串一起消失。
## [param ids] 一般是 [method LogicGraph.tail_ids] 的结果（拿起的块 + 它后面的兄弟）。
func remove_tail(ids: Array[int]) -> bool:
	if ids.is_empty() or not graph.has(ids[0]):
		return false
	# lambda 按值捕获，不能在闭包里给外部变量赋值，所以先把要删的名单复制出来
	var doomed := ids.duplicate()
	var links: Dictionary = {}
	for id in doomed:
		for victim in graph.subtree_ids(id):
			links[victim] = true
	history.record("删除块", func() -> void:
		for id in doomed:
			graph.remove_node(id)
		_clear_links_to(links))
	return true

## 复制以 [param source_id] 为根的整棵子树，插到 [param owner_id] 的容器里（一条撤销记录）。
## 返回新根的节点 id（失败返回 0）。
func duplicate_subtree(source_id: int, owner_id: int, slot_id: StringName, index: int) -> int:
	return _duplicate(source_id, func(nodes: Array[LogicNode]) -> void:
		graph.insert_subtree(nodes, owner_id, slot_id, index))


## 复制到画布上的一条新链（拖到空白处松手）。
func duplicate_subtree_to_new_chain(source_id: int, world_pos: Vector2) -> int:
	return _duplicate(source_id, func(nodes: Array[LogicNode]) -> void:
		var chain := graph.create_chain(world_pos)
		graph.insert_subtree(nodes, LogicGraph.ROOT, chain, -1))


## 复制一棵子树并整体入图（一条撤销记录），返回新根的节点 id。
## [param mutate] 拿到的是尚未入图的副本：插入的目标不同（容器里 / 新链），这一步才分道。
func _duplicate(source_id: int, mutate: Callable) -> int:
	# 入口块拒绝复制（右键拖拽在 [DragController] 就已经拦下了，这里再兜一道：
	# 复制入口 = 一个文档冒出两个起点，导出“从 Start 开始”就没意义了）
	if self.is_entry(graph.get_node_by_id(source_id)):
		return 0
	var clone := _clone_subtree(source_id)
	if clone.is_empty():
		return 0
	var nodes: Array[LogicNode] = clone["nodes"]
	var new_root: LogicNode = clone["root"]
	history.record("复制块", mutate.bind(nodes))
	return new_root.id


## 深拷贝一棵子树（含槽位结构）：实现全在 [GraphCloner]（纯数据、不碰控件）。
func _clone_subtree(source_id: int) -> Dictionary:
	return GraphCloner.clone(graph, source_id, _reference_fields_of)


## 某节点的块引用字段（「哪些字段是引用」的真相在块定义上）。
func _reference_fields_of(node: LogicNode) -> Array[StringName]:
	var def := library.by_id(node.type_id) if library != null else null
	return def.reference_fields() if def != null else [] as Array[StringName]


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
		def.apply_defaults(node)
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


## 造一个"幽灵"块视图（半透明、不吃鼠标、绑临时节点不写历史）。
## [param parent] 指定父节点 —— 需要画在整个界面之上时传顶层覆盖层（画布是 SubViewport，
## 里面的块永远盖不过兄弟控件）；[param source] 传入真实节点，则显示它的字段值而不是默认值，
## 并按本体在当前布局里的槽位尺寸再量一次（否则带巢的块副本只会量出空巢）。
func make_ghost(type_id: StringName, parent: Node = null, source: LogicNode = null) -> BlockView:
	var def := library.by_id(type_id) if library != null else null
	if def == null:
		return null
	var temp := source if source != null else LogicNode.new(0, type_id)
	if source == null:
		def.apply_defaults(temp)
	var ghost := BlockView.new()
	ghost.interactive = false
	# 幽灵也要显示「锁到了哪一块」：不注入这个标签器，跳转目标会一律显示未锁定
	ghost.link_labeler = _link_label
	(parent if parent != null else nBlocks).add_child(ghost)
	ghost.setup(def, temp, true)
	if source != null:
		ghost.measure(slot_extents_of(source.id))
	ghost.z_index = 50
	return ghost


## 落点占位块：把"如果现在放下会落下哪几个块"摆成一组幽灵视图（见 [PlacementPreview]）。
func show_placement_preview(ids: Array[int], offset: Vector2) -> void:
	_placement.show_existing(ids, offset)


## 调色板拖出时的落点占位块：将要新建的那个块（默认值就是它入图时的取值）。
func show_new_placement_preview(def: BlockDef, top_left: Vector2) -> void:
	_placement.show_new(def, top_left)


## 落点占位块的总高度（"插在中间"时用它给后面的块让位）。
func placement_preview_height() -> float:
	return _placement.height()


func clear_placement_preview() -> void:
	_placement.clear()

#endregion


#region 跳线（Jump 的跳转目标）

## 跳线数据（跳线层只负责画它）。
func link_segments() -> Array[Dictionary]:
	return _segments


## 锁定拖拽的预览线；空字典表示当前没在拖。
func link_preview() -> Dictionary:
	return _preview


## 某块在跳线里的出发/到达锚点：块左侧中点（世界坐标）。
func link_anchor(id: int) -> Vector2:
	return LinkRouter.anchor(layout, id)


## 世界坐标下命中哪一块（判定与「点块开始拖动」同源，返回 0 表示空白）。
## 嵌套时取面积最小的那个，于是点巢里的块不会选到外面的宿主。
func node_at_world(point: Vector2, exclude: Dictionary = {}) -> int:
	var best := 0
	var best_area := INF
	for id in _views:
		if exclude.has(id):
			continue
		var view: BlockView = _views[id]
		if view == null or not is_instance_valid(view) or not view.contains_world_point(point):
			continue
		var area := view.size.x * view.size.y
		if area < best_area:
			best_area = area
			best = id
	return best


## 锁定 / 解除某个引用字段（落地时调用，一次一条撤销记录）。
## [param target_id] 为 0 表示解除锁定。
func set_link(source_id: int, field_id: StringName, target_id: int) -> bool:
	var node := graph.get_node_by_id(source_id)
	if node == null:
		return false
	var value := LogicGraph.make_link_ref(target_id)
	if String(node.get_field(field_id, "")) == value:
		return true
	_applying_field = true
	history.record("锁定跳转目标" if target_id > 0 else "解除跳转目标", func() -> void:
		graph.set_field(source_id, field_id, value))
	_applying_field = false
	var view: BlockView = _views.get(source_id)
	if view != null and is_instance_valid(view):
		view.sync_from_data()
	relayout()
	return true


## 锁定拖拽中：更新预览线与悬停高亮（每帧由 [LinkController] 调）。
func set_link_preview(from: Vector2, to: Vector2, hover_id: int) -> void:
	_preview = {"from": from, "to": to, "valid": hover_id > 0}
	set_link_highlight(hover_id)
	_redraw_links()


func clear_link_preview() -> void:
	_preview = {}
	set_link_highlight(0)
	_redraw_links()


func set_link_highlight(id: int) -> void:
	if _highlight_id == id:
		return
	var previous: BlockView = _views.get(_highlight_id)
	if previous != null and is_instance_valid(previous):
		previous.set_link_highlight(false)
	_highlight_id = id
	var current: BlockView = _views.get(id)
	if current != null and is_instance_valid(current):
		current.set_link_highlight(true)


## 引用字段现在指着哪一块（块视图把它显示在按钮上）。
func _link_label(node_id: int, field_id: StringName) -> String:
	var node := graph.get_node_by_id(node_id)
	if node == null:
		return "未锁定"
	var target := LogicGraph.parse_link_ref(node.get_field(field_id, ""))
	if target <= 0:
		return "未锁定"
	var target_node := graph.get_node_by_id(target)
	return String(target_node.type_id) if target_node != null else "已失效"


## 重算全部跳线。布局一变（块移动、增删、字段改动）就跑一次。
func _refresh_links() -> void:
	_segments = LinkRouter.segments(graph, library, layout)
	_redraw_links()

func _redraw_links() -> void:
	if nLinks != null and is_instance_valid(nLinks):
		nLinks.queue_redraw()



## 目标块被删掉后，指向它的引用一并清掉 —— 否则会留下指向不存在节点的死引用。
## 与删除同处一条撤销记录（快照式撤销，不需要额外的逆操作）。
func _clear_links_to(doomed: Dictionary) -> void:
	if library == null:
		return
	for id in graph.all_ids():
		var node := graph.get_node_by_id(id)
		if node == null:
			continue
		var def := library.by_id(node.type_id)
		if def == null:
			continue
		for field_id in def.reference_fields():
			var target := LogicGraph.parse_link_ref(node.get_field(field_id, ""))
			if target > 0 and doomed.has(target):
				graph.set_field(id, field_id, "")


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
