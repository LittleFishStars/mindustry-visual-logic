class_name DragController
extends Node

## 拖拽会话：调色板出块、画布内搬移、吸附提示与落地。
##
## 本节点挂在编辑器标签页根下（[b]不在[/b] SubViewport 里），所以 [_input] 能收到
## 画布之外（包括左侧调色板）的鼠标事件 —— 这是旧实现把 Dragger 放在根节点下的原因。
## 根本差别是：它[b]不再 reparent 任何节点[/b]，拖拽期间图与视图树都保持原样 ——
## 只有幽灵（新建）或被拖块及其子树（搬移）在动，落地时才产生一条撤销记录。
## 于是「拖到画布外松手」等价于取消，绝不会像旧实现那样连带删掉下游逻辑。

signal drag_started()
signal drag_finished()

## 吸附判定半径（像素，世界坐标）。
@export var capture_radius: float = 22.0

var canvas: EditorCanvas
var area: SubViewportContainer

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


func _ready() -> void:
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
	_subtree_positions.clear()
	_exclude.clear()
	for id in canvas.graph.subtree_ids(_source_node.id):
		_exclude[id] = true
		_subtree_positions[id] = canvas.layout.rect_of(id).position if canvas.layout != null else Vector2.ZERO
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
	_ghost = canvas.make_ghost(_type_id)
	if _ghost != null:
		_ghost.position = _world_mouse() - _offset
	_begin()


func _begin() -> void:
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_finish()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
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
	var origin := world - _offset
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.position = origin
	elif _source_node != null and not _subtree_positions.is_empty():
		var base: Vector2 = _subtree_positions.get(_source_node.id, origin)
		var delta := origin - base
		for id in _subtree_positions:
			var view: BlockView = canvas.view_of(id)
			if view != null and is_instance_valid(view):
				view.position = (_subtree_positions[id] as Vector2) + delta
	if not _inside_canvas():
		_target = {}
		canvas.clear_overlay()
		return
	_target = canvas.find_anchor(world, capture_radius, _exclude)
	canvas.set_overlay(true, _target)


func _finish() -> void:
	if not _active:
		return
	var world := _world_mouse()
	var origin := world - _offset
	var target := _target
	var inside := _inside_canvas()
	var source := _source_node
	var type_id := _type_id
	_cleanup()
	if not inside:
		# 落在画布外 = 取消：不动数据（旧实现这里会 queue_free 掉整块及其下游）
		canvas.relayout()
		return
	if not target.is_empty():
		var owner_id: int = target["owner_id"]
		var slot: StringName = target["slot"]
		var index: int = target["index"]
		if source == null:
			canvas.insert_new_node(type_id, owner_id, slot, index)
		else:
			canvas.move_node(source.id, owner_id, slot, index)
	elif source == null:
		canvas.insert_new_chain(type_id, origin)
	else:
		canvas.move_node_to_new_chain(source.id, origin)


## 右键 / Esc：取消拖拽，位置复原。
func cancel() -> void:
	if not _active:
		return
	_cleanup()
	canvas.relayout()


func is_active() -> bool:
	return _active


func _cleanup() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_active = false
	_source_node = null
	_type_id = &""
	_type_def = null
	_subtree_positions.clear()
	_exclude.clear()
	_target = {}
	set_process(false)
	if canvas != null:
		canvas.clear_overlay()
	drag_finished.emit()


func _inside_canvas() -> bool:
	if area == null or not is_instance_valid(area):
		return false
	return area.get_global_rect().has_point(get_viewport().get_mouse_position())


func _world_mouse() -> Vector2:
	return canvas.world_from_screen(area.get_global_rect(), get_viewport().get_mouse_position())

#endregion
