class_name DragController
extends Node

## 拖拽会话：调色板出块、画布内搬移、吸附提示与落地。
##
## 本节点挂在编辑器标签页根下（[b]不在[/b] SubViewport 里），所以 [_input] 能收到
## 画布之外（包括左侧调色板）的鼠标事件 —— 这是旧实现把 Dragger 放在根节点下的原因。
## 根本差别是：它[b]不再 reparent 任何节点[/b]，拖拽期间图与视图树都保持原样 ——
## 只有幽灵（新建）或被拖块及其子树（搬移）在动，落地时才产生一条撤销记录。
## 于是「拖到画布外松手」等价于取消；唯一删数据的是[b]拖到左侧块列表上松手[/b]——
## 那是有意为之的删除入口（一次撤销记录，拿起的整串一起删），不像旧实现那样「甩出画布就没了」。

signal drag_started()
signal drag_finished()

## 吸附判定半径（像素，世界坐标）。
@export var capture_radius: float = 22.0

var canvas: EditorCanvas
var area: SubViewportContainer
## 拖到这里松手 = 删掉搬的块（左侧块列表：分类按钮 + 块列表）。
## 从调色板拖出的新块不算（本来就不在图上）。
var delete_zones: Array[Control] = []

var _active: bool = false
## 非空表示「从图上搬移」，为空表示「从调色板新建」。
var _source_node: LogicNode = null
var _type_id: StringName = &""
var _type_def: BlockDef = null
var _ghost: BlockView = null
## 鼠标相对块左上角的偏移（屏幕上按下时的位置）。
var _offset: Vector2 = Vector2.ZERO
## 搬移时：子树各节点 → 拖拽开始时的位置。
var _subtree_positions: Dictionary[int, Vector2] = {}
var _exclude: Dictionary[int, bool] = {}
var _target: Dictionary = {}
## 本次搬移的块：拿起的那块 + 它后面的所有块（同一容器里的后续兄弟）
var _carried: Array[int] = []
## 为落点占位块让位而被临时下移的块（松手/换目标时按布局结果还原）
var _pushed: Array[int] = []
## 悬停提示：当前是否停在删除区（用来给拖动副本压暗红）。
var _delete_hover: bool = false
## 拖动中的块改用顶层覆盖层（SubViewport 之外）的副本显示 —— 画布里的块永远盖不过
## 兄弟控件（比如左侧的块列表），所以副本必须挂在这一层
var _overlay: Control = null
var _floats: Array[BlockView] = []
var _float_offsets: Array[Vector2] = []
## 被副本顶替而临时隐藏的原块（松手时还原可见性）
var _hidden: Dictionary[int, bool] = {}


## 按下时的鼠标位置：用来判断"原地松手"（没有真正搬动）
var _start_mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	# 顶层覆盖层：画布是 SubViewport，拖动的块要画在整个界面之上才不会被块列表挡住
	_overlay = get_parent().get_node_or_null(^"DragLayer") as Control
	set_process(false)


#region 开始拖拽

## 从画布上的块开始搬移。
func start_from_view(view: BlockView, offset: Vector2) -> void:
	if _active or canvas == null or view == null or view.node == null:
		return
	if not canvas.graph.has(view.node.id):
		return
	_active = true
	_source_node = view.node
	_type_id = view.node.type_id
	_type_def = canvas.library.by_id(_type_id)
	_offset = offset
	# 拿起一个块时，它"后面的所有块"一起走（Mindustry 的操作直觉：后面的跟着走，顺序不乱）
	_carried = canvas.graph.tail_ids(_source_node.id)
	_subtree_positions.clear()
	_exclude.clear()
	for carried_id in _carried:
		for id in canvas.graph.subtree_ids(carried_id):
			_exclude[id] = true
			_subtree_positions[id] = canvas.layout.rect_of(id).position if canvas.layout != null else Vector2.ZERO
	# 原块先隐藏，改用覆盖层里的副本跟手 —— 否则拖到左侧块列表上方时会被裁掉
	_floats.clear()
	_float_offsets.clear()
	_hidden.clear()
	if _overlay != null:
		var head: Vector2 = _subtree_positions.get(_source_node.id, Vector2.ZERO)
		for id in _subtree_positions:
			var carried_node := canvas.graph.get_node_by_id(id)
			if carried_node == null:
				continue
			var carried_view := canvas.view_of(id)
			if carried_view != null and is_instance_valid(carried_view):
				_hidden[id] = carried_view.visible
				carried_view.visible = false
			var float_view := canvas.make_ghost(carried_node.type_id, _overlay, carried_node)
			if float_view != null:
				_floats.append(float_view)
				_float_offsets.append((_subtree_positions[id] as Vector2) - head)
	_begin()


## 从左侧调色板开始新建（[param offset] 是点击点在块内的位置）。
func start_from_palette(block: BlockDef, offset: Vector2) -> void:
	if _active or canvas == null or block == null:
		return
	_active = true
	_source_node = null
	_type_id = block.id
	_type_def = block
	_offset = offset
	_subtree_positions.clear()
	_exclude.clear()
	# 新建块没有"要一起搬的块"，这里必须清掉上一次拖拽留下的 _carried，
	# 否则落点会摆出上一次那几个块的占位视图
	_carried.clear()
	_ghost = canvas.make_ghost(_type_id, _overlay)
	if _ghost != null:
		_ghost.position = _layer_mouse() - _offset * _zoom()
	_begin()


func _begin() -> void:
	_start_mouse = _world_mouse()
	if not _active:
		return
	if canvas.nCamera != null:
		canvas.nCamera.stop_panning()
	_target = {}
	set_process(true)
	drag_started.emit()
	_update()


#endregion


#region 跟踪与落地

func _input(event: InputEvent) -> void:
	if not _active:
		return
	# 按下鼠标拿起、松开放下：左键松开即落地；右键/Esc 仍然是取消
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_finish()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _active:
		_update()


func _update() -> void:
	if not _active:
		return
	var world := _world_mouse()
	var layer := _layer_mouse()
	var zoom := _zoom()
	# 悬停到左侧块列表上：不找吸附点，只提示「松手就删」
	var deleting := _source_node != null and _over_delete_zone()
	if deleting != _delete_hover:
		_delete_hover = deleting
		_apply_delete_hint(deleting)
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.position = layer - _offset * zoom
		_ghost.scale = Vector2(zoom, zoom)
	elif not _floats.is_empty():
		# 覆盖层是屏幕空间：位置按鼠标 + 各块相对"头块"的布局偏移 × 缩放
		var origin := layer - _offset * zoom
		for i in _floats.size():
			var float_view := _floats[i]
			if is_instance_valid(float_view):
				float_view.position = origin + _float_offsets[i] * zoom
				float_view.scale = Vector2(zoom, zoom)
	elif _source_node != null and not _subtree_positions.is_empty():
		# 没有覆盖层时的兜底：仍在画布坐标系里直接移动原块
		var base: Vector2 = _subtree_positions.get(_source_node.id, world - _offset)
		var delta := world - _offset - base
		for id in _subtree_positions:
			var view: BlockView = canvas.view_of(id)
			if view != null and is_instance_valid(view):
				view.position = (_subtree_positions[id] as Vector2) + delta
	if _delete_hover:
		_target = {}
		_release_shift()
		canvas.clear_placement_preview()
		return
	if not _inside_canvas():
		_target = {}
		_release_shift()
		canvas.clear_placement_preview()
		return
	_target = canvas.find_anchor(world, capture_radius, _exclude)
	_update_placement_preview()


## 在落点摆出占位块：指示"现在放下会落到哪、长什么样"。
func _update_placement_preview() -> void:
	_release_shift()
	if _target.is_empty() or canvas.layout == null:
		canvas.clear_placement_preview()
		return
	var at := Vector2(_target.get("position", Vector2.ZERO))
	if _source_node == null:
		# 从调色板拖出：占位块就是将要新建的那个块（默认值），左上角落在吸附点上
		canvas.show_new_placement_preview(_type_def, at)
		_apply_insert_shift(at)
		return
	if _carried.is_empty():
		canvas.clear_placement_preview()
		return
	canvas.show_placement_preview(_carried, at - canvas.layout.rect_of(_carried[0]).position)
	_apply_insert_shift(at)


## 插在中间时给占位块腾位置：把插入点之后的块（及其子树）整体下移一个占位块的高度。
## 每帧都"先还原、再重算"，所以换目标不会有累积偏移；松手后会重新求解布局，自然归位。
func _apply_insert_shift(_at: Vector2) -> void:
	var index: int = int(_target.get("index", -1))
	var height := canvas.placement_preview_height()
	if index < 0 or height <= 0.0:
		return
	var owner_id: int = int(_target.get("owner_id", LogicGraph.ROOT))
	var slot: StringName = _target.get("slot", &"")
	for item in canvas.graph.slot_items(owner_id, slot).slice(index):
		for id in canvas.graph.subtree_ids(item):
			var view := canvas.view_of(id)
			if view != null and is_instance_valid(view):
				view.position += Vector2(0, height)
				_pushed.append(id)


## 把让位造成的临时偏移还原（布局结果才是真相）。
func _release_shift() -> void:
	for id in _pushed:
		var view := canvas.view_of(id)
		if view != null and is_instance_valid(view) and canvas.layout != null:
			view.position = canvas.layout.rect_of(id).position
	_pushed.clear()


func _finish() -> void:
	if not _active:
		return
	var world := _world_mouse()
	var origin := world - _offset
	var target := _target
	var inside := _inside_canvas()
	var source := _source_node
	var type_id := _type_id
	var moved := (world - _start_mouse).length() > 4.0
	# 拖到左侧块列表松手 = 删除（要在 _cleanup() 清掉 _source_node / _carried 之前判断）
	var carried := _carried.duplicate()
	var deleting := source != null and moved and _over_delete_zone()
	_cleanup()
	if deleting and not carried.is_empty():
		canvas.remove_tail(carried)
		return
	if not inside or not moved:
		# 画布外松手 = 取消；原地松手 = 没搬动，都不动数据
		# （旧实现落在画布外就把整块及其下游 queue_free 掉；现在只有左侧块列表是有意的删除区）
		canvas.relayout()
		return
	if not target.is_empty():
		var owner_id: int = target["owner_id"]
		var slot: StringName = target["slot"]
		var index: int = target["index"]
		if source == null:
			canvas.insert_new_node(type_id, owner_id, slot, index)
		else:
			canvas.move_tail(_carried, owner_id, slot, index)
	elif source == null:
		canvas.insert_new_chain(type_id, origin)
	else:
		canvas.move_tail_to_new_chain(_carried, origin)


## 右键 / Esc：取消拖拽，位置复原。
func cancel() -> void:
	if not _active:
		return
	_cleanup()
	canvas.relayout()


func is_active() -> bool:
	return _active


func _cleanup() -> void:
	for float_view in _floats:
		if is_instance_valid(float_view):
			float_view.queue_free()
	_floats.clear()
	_float_offsets.clear()
	for id in _hidden:
		var hidden_view := canvas.view_of(id)
		if hidden_view != null and is_instance_valid(hidden_view):
			hidden_view.visible = _hidden[id]
	_hidden.clear()
	_release_shift()
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_active = false
	_delete_hover = false
	_source_node = null
	_type_id = &""
	_type_def = null
	_subtree_positions.clear()
	_exclude.clear()
	_target = {}
	set_process(false)
	if canvas != null:
		canvas.clear_placement_preview()
	drag_finished.emit()


## 覆盖层坐标下的鼠标位置；没有覆盖层时退回画布世界坐标（保持旧行为）。
func _layer_mouse() -> Vector2:
	if _overlay != null:
		return _overlay.get_global_mouse_position()
	return _world_mouse()


## 相机缩放：覆盖层是屏幕空间，副本的位置与大小都要按它换算。
func _zoom() -> float:
	if _overlay != null and canvas != null and canvas.nCamera != null:
		return canvas.nCamera.zoom.x
	return 1.0


## 鼠标是否停在「拖到这里就删掉」的区域（左侧块列表）。
func _over_delete_zone() -> bool:
	var mouse := get_viewport().get_mouse_position()
	for zone in delete_zones:
		if is_instance_valid(zone) and zone.is_visible_in_tree() and zone.get_global_rect().has_point(mouse):
			return true
	return false


## 给拖动副本压一层暗红，提示「松手就删」；离开时恢复本色。
func _apply_delete_hint(on: bool) -> void:
	var tint := Color(1.0, 0.45, 0.45, 0.85) if on else Color.WHITE
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.modulate = tint
	for float_view in _floats:
		if is_instance_valid(float_view):
			float_view.modulate = tint


func _inside_canvas() -> bool:
	if area == null or not is_instance_valid(area):
		return false
	return area.get_global_rect().has_point(get_viewport().get_mouse_position())

func _world_mouse() -> Vector2:
	return canvas.world_from_screen(area.get_global_rect(), get_viewport().get_mouse_position())

#endregion
