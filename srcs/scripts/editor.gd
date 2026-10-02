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


func _ready() -> void:
	library = BlockLibrary.load_localized()
	nCanvas.setup(library)
	nCanvas.drag_requested.connect(_on_canvas_drag_requested)
	nCanvas.picker_requested.connect(_on_picker_requested)
	nDrag.canvas = nCanvas
	nDrag.area = nEditArea
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
	for field_id in block.default_field_values():
		temp.fields[field_id] = block.default_field_values()[field_id]
	var view := BlockView.new()
	view.name = "Sample_%s" % block.id
	view.setup(block, temp, true)
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
	_picker.open(element, control, control.get_global_rect().position + Vector2(0, control.size.y))


func _on_picker_picked(value: String) -> void:
	if _picker_target != null and is_instance_valid(_picker_target):
		var edit: Variant = _picker_target.get_meta(&"value_control", null)
		if edit is LineEdit:
			(edit as LineEdit).text = value
			# text_changed 会带着新值走一遍 commit_field
	_close_picker()


func _close_picker() -> void:
	_picker_target = null
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


func can_undo() -> bool:
	return nCanvas.history.can_undo()


func can_redo() -> bool:
	return nCanvas.history.can_redo()

#endregion
