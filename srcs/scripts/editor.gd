class_name LogicEditorTab
extends Control

## 编辑器标签页：左侧块调色板 + 右侧自由画布。
##
## 视图层由 [EditorCanvas]（SubViewport）承担，拖拽由 [DragController] 统一处理，
## 选择器浮层由 [SelectorPanel] 提供。本脚本只做「拼装 + 接线」。

@export var list_separation: int = 10

@onready var nBlockKindList: VBoxContainer = $Split/BlockKindList
@onready var nBlockArea: ScrollContainer = $Split/EditorSplit/BlockArea
@onready var nEditArea: SubViewportContainer = $Split/EditorSplit/EditArea
@onready var nCanvas: EditorCanvas = $Split/EditorSplit/EditArea/EditSpace
@onready var nDrag: DragController = $Drag

var library: BlockLibrary

var _current_kind: StringName = &""
var _picker: SelectorPanel = null
var _picker_target: Control = null
var _picker_element: ElementDef = null


func _ready() -> void:
	library = BlockLibrary.load_localized()
	nCanvas.setup(library)
	nCanvas.drag_requested.connect(_on_canvas_drag_requested)
	nCanvas.picker_requested.connect(_on_picker_requested)
	nDrag.canvas = nCanvas
	nDrag.area = nEditArea
	# 拖到左侧块列表（分类按钮列 + 块列表）松手 = 删掉搬的块
	nDrag.delete_zones.assign([nBlockKindList, nBlockArea])
	_picker = SelectorPanel.new()
	_picker.picked.connect(_on_picker_picked)
	add_child(_picker)
	_build_palette()


#region 调色板

func _build_palette() -> void:
	for kind in library.kinds:
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
	if not library.kinds.is_empty():
		_show_kind(library.kinds[0].id)


## 调色板里的一块样品：绑定一个临时节点（带默认值），拖动时才在画布上建真节点。
func _make_sample(block: BlockDef) -> BlockView:
	var temp := LogicNode.new(0, block.id)
	block.apply_defaults(temp)
	var view := BlockView.new()
	view.name = "Sample_%s" % block.id
	view.setup(block, temp, true)
	# 列表里保持块自己的宽度：不参与容器的横向拉伸（否则会被拉满整列），
	# 并先量一次，让它的最小宽度来自块本身的布局而不是兜底值
	view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	view.measure({})
	view.drag_requested.connect(func(_view: BlockView, offset: Vector2) -> void:
		nDrag.start_from_palette(block, offset))
	return view


func _show_kind(kind: StringName) -> void:
	if kind == _current_kind:
		return
	if _current_kind != &"" and nBlockArea.has_node(String(_current_kind)):
		nBlockArea.get_node(String(_current_kind)).hide()
	_current_kind = kind
	if nBlockArea.has_node(String(kind)):
		nBlockArea.get_node(String(kind)).show()

#endregion


#region 画布交互

## 画布上的块按下：开始搬移（画布外松手 = 取消，不再有「拖出去就删掉」的行为）。
func _on_canvas_drag_requested(view: BlockView, offset: Vector2) -> void:
	_close_picker()
	nDrag.start_from_view(view, offset)


func _on_picker_requested(element: ElementDef, control: Control) -> void:
	if element == null or control == null or not is_instance_valid(control):
		return
	_picker_target = control
	_picker_element = element
	_picker.open(element, control, control.get_global_rect().position + Vector2(0, control.size.y))


func _on_picker_picked(value: String) -> void:
	if _picker_target != null and is_instance_valid(_picker_target) and _picker_element != null:
		# 回填走元素构建器：编辑器不需要知道"值存在组合控件里的哪个子控件"
		# force = true：这是明确的用户动作，即使输入框还拿着焦点也要写进去
		var builder: Variant = ElementRegistry.builder(_picker_element.type)
		if builder != null:
			builder.apply_value(_picker_element, _picker_target, value, true)
		# 输入框的 text_changed 会带着新值走一遍 commit_field
	_close_picker()


func _close_picker() -> void:
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

## 当前文件的绝对路径（空 = 尚未保存过）。
var file_path: String = ""

## 标签页标题跟着文件名变。
signal name_changed(display: String)


func display_name() -> String:
	return file_path.get_file().get_basename() if file_path != "" else "未命名"


func new_project() -> void:
	nCanvas.history.clear()
	nCanvas.graph.clear()
	file_path = ""
	name_changed.emit(display_name())


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


## 导出为 mlog 文本（纯函数，不改动任何数据）。
func export_mlog() -> String:
	return MlogExporter.export(nCanvas.graph, library)


## 导出到系统剪贴板，返回写进去的文本。
func copy_mlog_to_clipboard() -> String:
	var text := export_mlog()
	DisplayServer.clipboard_set(text)
	return text


func undo() -> bool:
	return nCanvas.undo()


func redo() -> bool:
	return nCanvas.redo()


## 从 mlog 文本导入块。[param append] 为假时先清空当前项目。
## 整个动作（清空 + 插入）算一条撤销记录 —— 快照式撤销让这件事不需要额外的逆操作。
func import_mlog(text: String, append: bool = false) -> int:
	var warnings: Array[String] = []
	var nodes := MlogImporter.parse(text, library, nCanvas.graph, warnings)
	for message in warnings:
		push_warning(message)
	if nodes.is_empty():
		return 0
	nCanvas.history.record("导入 %d 个块" % nodes.size(), func() -> void:
		var chain: StringName
		if append:
			chain = nCanvas.graph.primary_chain(Vector2(40, 40))
		else:
			nCanvas.graph.clear()
			chain = nCanvas.graph.create_chain(Vector2(40, 40))
		for node in nodes:
			nCanvas.graph.insert_node(node, LogicGraph.ROOT, chain, -1))
	return nodes.size()


func can_undo() -> bool:
	return nCanvas.history.can_undo()


func can_redo() -> bool:
	return nCanvas.history.can_redo()

#endregion
