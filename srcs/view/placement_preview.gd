class_name PlacementPreview
extends RefCounted

## 落点占位块：拖拽时把「如果现在放下会落下哪几个块」摆成一组半透明幽灵视图。
##
## 视图只在目标集合变化时重建，之后每帧只更新位置 —— 拖拽是每帧调用的，
## 每帧重建几十个块视图是不可接受的。
##
## 它只向 [EditorCanvas] 要两样东西：造幽灵视图（[method EditorCanvas.make_ghost]）
## 与真实布局里的位置（[member EditorCanvas.layout]）。预览状态全部在这里，
## 画布只留一层转发 —— 于是「占位块现在摆的是哪几块」这个问题只有一个答案。

var _canvas: EditorCanvas
## 当前摆出来的幽灵视图与它们各自的原始位置（第 i 个与第 i 个对应）。
var _views: Array[BlockView] = []
var _origins: Array[Vector2] = []
## 当前预览的节点集合（从图上搬移时用）与块类型（从调色板新建时用）。
var _ids: Array[int] = []
var _def_id: StringName = &""


func _init(canvas: EditorCanvas) -> void:
	_canvas = canvas


## 摆出「这些已存在的块会落到哪」：它们的相对布局不变，整体平移 [param offset]。
func show_existing(ids: Array[int], offset: Vector2) -> void:
	if ids != _ids or _def_id != &"":
		clear()
		_ids = ids.duplicate()
		_origins.clear()
		for id in ids:
			var node := _canvas.graph.get_node_by_id(id)
			if node == null:
				continue
			# make_ghost(source) 已经带着真实字段值、不吃鼠标，并按本体布局量过巢的尺寸
			var ghost := _canvas.make_ghost(node.type_id, null, node)
			if ghost == null:
				continue
			ghost.modulate = Color(1, 1, 1, 0.5)
			_views.append(ghost)
			_origins.append(_canvas.layout.rect_of(id).position if _canvas.layout != null else Vector2.ZERO)
	for i in _views.size():
		if i < _origins.size():
			_views[i].position = _origins[i] + offset


## 摆出「从调色板拖出的新块会落到哪」：占位块就是将要新建的那个块（默认值）。
func show_new(def: BlockDef, top_left: Vector2) -> void:
	if def == null:
		clear()
		return
	if _def_id != def.id:
		clear()
		_def_id = def.id
		var ghost := _canvas.make_ghost(def.id)
		if ghost != null:
			ghost.modulate = Color(1, 1, 1, 0.5)
			_views.append(ghost)
	for view in _views:
		if is_instance_valid(view):
			view.position = top_left


## 占位块的总高度（"插在中间"时用它给后面的块让位）。
func height() -> float:
	var total := 0.0
	for view in _views:
		if is_instance_valid(view):
			total += maxf(view.metrics.size.y if view.metrics != null else view.size.y, 1.0)
	return total


func clear() -> void:
	for view in _views:
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	_origins.clear()
	_ids.clear()
	_def_id = &""


## 当前摆着的幽灵视图（仅供验证/调试；位置一律以本类为真相）。
func views() -> Array[BlockView]:
	return _views
