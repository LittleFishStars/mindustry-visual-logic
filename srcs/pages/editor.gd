class_name LogicEditorTab
extends Control

## 编辑器标签页：左侧块调色板 + 右侧自由画布；本脚本只做「拼装 + 接线」。

const PASTE_GAP := 56.0

@export var list_separation: int = 10

@onready var nBlockKindList: VBoxContainer = $Split/BlockKindList
@onready var nBlockArea: ScrollContainer = $Split/EditorSplit/BlockArea
@onready var nEditArea: SubViewportContainer = $Split/EditorSplit/EditArea
@onready var nCanvas: EditorCanvas = $Split/EditorSplit/EditArea/EditSpace
@onready var nDrag: DragController = $Drag
@onready var nLink: LinkController = $Link

var library: BlockLibrary

var _current_kind: StringName = &""
var _kind_lists: Dictionary[StringName, Control] = {}
var _picker: SelectorPanel = null
var _picker_view: BlockView = null
var _picker_target: Control = null
var _picker_element: ElementDef = null


func _ready() -> void:
	library = BlockLibrary.load_localized(TranslationServer.get_locale())
	nCanvas.setup(library)
	nCanvas.drag_requested.connect(_on_canvas_drag_requested)
	nCanvas.picker_requested.connect(_on_picker_requested)
	nCanvas.link_requested.connect(_on_canvas_link_requested)
	nCanvas.copy_requested.connect(_on_canvas_copy_requested)
	_setup_pointer_sessions()
	_picker = SelectorPanel.new()
	_picker.picked.connect(_on_picker_picked)
	add_child(_picker)
	_build_palette()
	_place_entry_block()


## 语言变了（由 [Main] 调）：按新语言重载块定义，重建调色板与画布上的块视图；
## 图与撤销栈不动 —— 换的只是显示文本。
func reload_language() -> void:
	library = BlockLibrary.load_localized(TranslationServer.get_locale())
	nCanvas.library = library
	nCanvas.rebuild()
	for child in nBlockKindList.get_children():
		nBlockKindList.remove_child(child)
		child.queue_free()
	for child in nBlockArea.get_children():
		nBlockArea.remove_child(child)
		child.queue_free()
	_kind_lists.clear()
	_current_kind = &""
	_build_palette()


## 两个指针会话（搬块 / 锁定跳转目标）用同一块画布区域、同一组「拖到这里就删」的区域。
func _setup_pointer_sessions() -> void:
	var sessions: Array[CanvasPointerSession] = [nDrag, nLink]
	for session in sessions:
		session.canvas = nCanvas
		session.area = nEditArea
		# 拖到左侧块列表（分类按钮列 + 块列表）松手 = 删块 / 解除锁定
		session.delete_zones.assign([nBlockKindList, nBlockArea])
#region 调色板

func _build_palette() -> void:
	var first_visible: StringName = &""
	for kind in library.kinds:
		if kind.hidden:
			continue
		var button := Button.new()
		button.text = String(kind.id)
		button.pressed.connect(func() -> void: _show_kind(kind.id))
		nBlockKindList.add_child(button)
		var kind_list := VBoxContainer.new()
		kind_list.name = String(kind.id)
		kind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		kind_list.add_theme_constant_override("separation", list_separation)
		kind_list.hide()
		for block in kind.blocks:
			kind_list.add_child(_make_sample(block))
		nBlockArea.add_child(kind_list)
		_kind_lists[kind.id] = kind_list
		if first_visible == &"":
			first_visible = kind.id
	_show_kind(first_visible)



func _place_entry_block() -> void:
	var def := library.entry_def() if library != null else null
	if def == null:
		return
	var node := nCanvas.graph.new_node(def.id)
	def.apply_defaults(node)
	var chain := nCanvas.graph.create_chain(Vector2(40, 40))
	nCanvas.graph.insert_node(node, LogicGraph.ROOT, chain, -1)


func _make_sample(block: BlockDef) -> BlockView:
	var temp := LogicNode.new(0, block.id)
	block.apply_defaults(temp)
	var view := BlockView.new()
	view.name = "Sample_%s" % block.id
	view.setup(block, temp, true)
	view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	view.measure({})
	view.drag_requested.connect(func(_view: BlockView, offset: Vector2) -> void:
		nDrag.start_from_palette(block, offset))
	return view


func _show_kind(kind: StringName) -> void:
	if kind == _current_kind or not _kind_lists.has(kind):
		return
	if _kind_lists.has(_current_kind):
		_kind_lists[_current_kind].hide()
	_current_kind = kind
	_kind_lists[kind].show()

#endregion


#region 画布交互

## 画布上的块按下：开始搬移（画布外松手 = 取消）。
func _on_canvas_drag_requested(view: BlockView, offset: Vector2) -> void:
	_close_picker()
	nDrag.start_from_view(view, offset)


## 右键块：拖出一份副本（原块留原地；拖到左侧列表松手 = 取消）。
func _on_canvas_copy_requested(view: BlockView, offset: Vector2) -> void:
	_close_picker()
	nDrag.start_copy_from_view(view, offset)


func _on_canvas_link_requested(view: BlockView, element: ElementDef, control: Control) -> void:
	_close_picker()
	nLink.start(view, element, control)


func _on_picker_requested(view: BlockView, element: ElementDef, control: Control) -> void:
	if element == null or control == null or not is_instance_valid(control):
		return
	_picker_view = view
	_picker_target = control
	_picker_element = element
	_picker.open(element)


func _on_picker_picked(value: String) -> void:
	# 交给块视图：先刷控件再提交数据层（程序化赋值不触发 text_changed，必须显式提交）
	if _picker_view != null and is_instance_valid(_picker_view):
		_picker_view.apply_picker_value(_picker_element, _picker_target, value)
	_close_picker()


func _close_picker() -> void:
	_picker_view = null
	_picker_target = null
	_picker_element = null
	if _picker != null:
		_picker.close()


func _unhandled_input(event: InputEvent) -> void:
	if _picker == null or not _picker.is_open():
		return
	if event is InputEventMouseButton and event.pressed:
		if not _picker.get_global_rect().has_point(event.global_position):
			_close_picker()

#endregion


#region 项目操作（保存 / 打开 / 导出；菜单都走这些方法）

var file_path: String = ""

signal name_changed(display: String)

var custom_name: String = ""


func display_name() -> String:
	if custom_name != "":
		return custom_name
	return file_path.get_file().get_basename() if file_path != "" else tr("TAB_UNTITLED")


## 手动重命名标签页（空值回落到跟随文件名）。
func set_custom_name(value: String) -> void:
	var wanted := value.strip_edges()
	if custom_name == wanted:
		return
	custom_name = wanted
	name_changed.emit(display_name())


## 换成全新的空图：撤销栈一并丢掉（文件名重置，相当于另一个文档）。
func new_project() -> void:
	nCanvas.history.clear()
	nCanvas.graph.clear()
	_place_entry_block()
	file_path = ""
	name_changed.emit(display_name())


## 清空所有块：记一条可撤销记录，并把入口块放回来。
func clear_graph() -> void:
	if self.is_empty():
		return
	nCanvas.history.record("清空", func() -> void:
		nCanvas.graph.clear()
		_place_entry_block())


## 有没有用户搭的东西（入口块不算，否则「清空」永远不置灰）。
func is_empty() -> bool:
	for id in nCanvas.graph.all_ids():
		var node := nCanvas.graph.get_node_by_id(id)
		if node != null and not self.is_entry(node):
			return false
	return true


## 这个节点是不是入口块（XML `entry="true"`，目前是 Start）。真相在 [EditorCanvas]。
func is_entry(node: LogicNode) -> bool:
	return nCanvas.is_entry(node)

func save_to(path: String) -> Error:
	var error := GraphSerializer.save_to_file(nCanvas.graph, path, display_name())
	if error == OK:
		file_path = path
		name_changed.emit(display_name())
	return error


func load_from(path: String) -> bool:
	var loaded := GraphSerializer.load_from_file(path)
	if loaded == null:
		return false
	nCanvas.adopt_graph(loaded)
	file_path = path
	name_changed.emit(display_name())
	return true


func export_mlog(warnings: Array[String] = []) -> String:
	return MlogExporter.export(nCanvas.graph, library, warnings)


## 导出到剪贴板；[param skip_empty] 空程序不动剪贴板（失焦自动导出用）。
func copy_mlog_to_clipboard(skip_empty: bool = false) -> String:
	var warnings: Array[String] = []
	var text := export_mlog(warnings)
	for message in warnings:
		push_warning(message)
	if skip_empty and text.strip_edges() == "":
		return text
	DisplayServer.clipboard_set(text)
	return text


func undo() -> bool:
	return nCanvas.undo()


func redo() -> bool:
	return nCanvas.redo()


## 从 mlog 文本导入块；[param append] 为假时先清空，整个动作算一条撤销记录。
func import_mlog(text: String, append: bool = false) -> int:
	var warnings: Array[String] = []
	var nodes := MlogImporter.parse(text, library, nCanvas.graph, warnings)
	if nodes.is_empty():
		for message in warnings:
			push_warning(message)
		return 0
	nCanvas.history.record("导入 %d 个块" % nodes.size(), func() -> void:
		if not append:
			# 换掉当前程序：入口块跟着回来（Special 在调色板里是隐藏的）
			nCanvas.graph.clear()
			_place_entry_block()
		var target := self._import_target(Vector2(40, 40))
		# 结构块还原后子节点已经挂在它的巢里，所以按子树整体入图（逐个插会把子节点也塞进链里）
		for group in MlogImporter.subtrees(nodes):
			var subtree: Array[LogicNode] = group
			nCanvas.graph.insert_subtree(subtree, int(target["owner_id"]), StringName(target["slot"]), -1))
	for message in warnings:
		push_warning(message)
	return nodes.size()


## Ctrl+V：把 mlog 转成块，另起一条新链摆在现有内容下方（不接入口块那条链）。
## jump 的行号按这段文本自己重新分析，所以片段内部的跳转照样连得上。
func paste_mlog_new_chain(text: String) -> int:
	var warnings: Array[String] = []
	var nodes := MlogImporter.parse(text, library, nCanvas.graph, warnings)
	if nodes.is_empty():
		for message in warnings:
			push_warning(message)
		return 0
	var pos := _paste_position()
	nCanvas.history.record("粘贴 %d 个块" % nodes.size(), func() -> void:
		var chain := nCanvas.graph.create_chain(pos)
		for group in MlogImporter.subtrees(nodes):
			var subtree: Array[LogicNode] = group
			nCanvas.graph.insert_subtree(subtree, LogicGraph.ROOT, chain, -1))
	for message in warnings:
		push_warning(message)
	return nodes.size()


## 粘贴位置：现有内容正下方，留 [constant PASTE_GAP] 空隙；没有内容时从固定点开始。
func _paste_position() -> Vector2:
	var rect := nCanvas.content_rect()
	if rect.size == Vector2.ZERO:
		return Vector2(40, 40)
	return Vector2(rect.position.x, rect.end.y + PASTE_GAP)


## 导入的块插进入口块那条链（插到别的链等于导不出来），没有入口块时退回主链。
func _import_target(fallback_pos: Vector2) -> Dictionary:
	var def := library.entry_def() if library != null else null
	if def != null:
		for id in nCanvas.graph.all_ids():
			var node := nCanvas.graph.get_node_by_id(id)
			if node == null or node.type_id != def.id:
				continue
			var where := nCanvas.graph.locate(id)
			if not where.is_empty() and int(where["owner_id"]) == LogicGraph.ROOT:
				return {"owner_id": LogicGraph.ROOT, "slot": StringName(where["slot"])}
	return {"owner_id": LogicGraph.ROOT, "slot": nCanvas.graph.primary_chain(fallback_pos)}

func can_undo() -> bool:
	return nCanvas.history.can_undo()


func can_redo() -> bool:
	return nCanvas.history.can_redo()

#endregion
