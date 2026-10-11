class_name LogicEditorTab
extends Control

## 编辑器标签页：左侧块调色板 + 右侧自由画布。
##
## 视图层由 [EditorCanvas]（SubViewport）承担，拖拽由 [DragController] 统一处理，
## 选择器浮层由 [SelectorPanel] 提供。本脚本只做「拼装 + 接线」。

## Ctrl+V 粘贴出来的新链与现有内容之间留的空隙（像素）。
const PASTE_GAP := 56.0

@export var list_separation: int = 10

@onready var nBlockKindList: VBoxContainer = $Split/BlockKindList
@onready var nBlockArea: ScrollContainer = $Split/EditorSplit/BlockArea
@onready var nEditArea: SubViewportContainer = $Split/EditorSplit/EditArea
@onready var nCanvas: EditorCanvas = $Split/EditorSplit/EditArea/EditSpace
@onready var nDrag: DragController = $Drag
## 拖拽锁定跳转目标的会话（与 DragController 并列、互不干扰）。
@onready var nLink: LinkController = $Link

var library: BlockLibrary

var _current_kind: StringName = &""
var _picker: SelectorPanel = null
## 谁请求的选择器：选中后由这个块视图刷控件 + 提交数据层（见 [method BlockView.apply_picker_value]）。
var _picker_view: BlockView = null
var _picker_target: Control = null
var _picker_element: ElementDef = null


func _ready() -> void:
	library = BlockLibrary.load_localized()
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


## 两个指针会话（搬块 / 锁定跳转目标）用同一块画布区域、同一组「拖到这里就删」的区域。
## 接线只写在这一处 —— 以后多一个会话也不会漏配。
func _setup_pointer_sessions() -> void:
	var sessions: Array[CanvasPointerSession] = [nDrag, nLink]
	for session in sessions:
		session.canvas = nCanvas
		session.area = nEditArea
		# 拖到左侧块列表（分类按钮列 + 块列表）松手 = 删掉搬的块 / 解除锁定
		session.delete_zones.assign([nBlockKindList, nBlockArea])
#region 调色板

func _build_palette() -> void:
	for kind in library.kinds:
		# hidden 的类别不进列表（Special：里面只有自动放的入口块这种内部块）
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
	# 默认展开第一个[b]可见[/b]的类别（hidden 的类别没有按钮，不能选它）
	for kind in library.kinds:
		if not kind.hidden:
			_show_kind(kind.id)
			break



## 新页的起点：把入口块（XML 里 `entry="true"`，目前是 Start）放在画布左上。
## 它[b]不进撤销栈[/b] —— 这是文档的初始状态，不是用户做的某一步操作。
func _place_entry_block() -> void:
	var def := library.entry_def() if library != null else null
	if def == null:
		return
	var node := nCanvas.graph.new_node(def.id)
	def.apply_defaults(node)
	var chain := nCanvas.graph.create_chain(Vector2(40, 40))
	nCanvas.graph.insert_node(node, LogicGraph.ROOT, chain, -1)


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


## 画布上的块按下右键：拖出一份副本（原块留在原地；拖到左侧块列表松手 = 取消）。
func _on_canvas_copy_requested(view: BlockView, offset: Vector2) -> void:
	_close_picker()
	nDrag.start_copy_from_view(view, offset)


## 块上的「跳转目标」按钮被按下：交给锁定控制器接管拖拽。
func _on_canvas_link_requested(view: BlockView, element: ElementDef, control: Control) -> void:
	_close_picker()
	nLink.start(view, element, control)


func _on_picker_requested(view: BlockView, element: ElementDef, control: Control) -> void:
	if element == null or control == null or not is_instance_valid(control):
		return
	_picker_view = view
	_picker_target = control
	_picker_element = element
	# 居中弹窗：不再贴在那颗 ▾ 按钮旁边（传 control 只是为了让回填知道写给谁）
	_picker.open(element, control)


func _on_picker_picked(value: String) -> void:
	# 交给块视图：它先刷控件、再提交数据层（程序化赋值不会触发 text_changed，必须显式提交）
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

## 当前文件的绝对路径（空 = 尚未保存过）。
var file_path: String = ""

## 标签页标题变了（保存 / 读档 / 手动重命名）。
signal name_changed(display: String)

## 用户手动起的名字（点标签条就地重命名）；空 = 跟随文件名。
var custom_name: String = ""


## 标签页标题：手动命名优先，否则跟随文件名。
func display_name() -> String:
	if custom_name != "":
		return custom_name
	return file_path.get_file().get_basename() if file_path != "" else "未命名"


## 手动重命名标签页。[param value] 为空（或全空白）时回落到「跟随文件名」。
func set_custom_name(value: String) -> void:
	var wanted := value.strip_edges()
	if custom_name == wanted:
		return
	custom_name = wanted
	name_changed.emit(display_name())


## 换成一张全新的空图：撤销栈也一并丢掉（文件名重置，相当于另一个文档）。
func new_project() -> void:
	nCanvas.history.clear()
	nCanvas.graph.clear()
	_place_entry_block()
	file_path = ""
	name_changed.emit(display_name())


## 清空当前项目里的所有块。与 [method new_project] 不同：文件名与撤销栈都保留，
## 而且清空本身算一条[b]可撤销[/b]的记录 —— 误清空可以直接撤销回来。
## 清空后回到「新页」的样子：[b]入口块重新放回来[/b]（Special 类别在调色板里是隐藏的，
## 不放回来这个文档就再也加不出入口块了）。
func clear_graph() -> void:
	if self.is_empty():
		return
	nCanvas.history.record("清空", func() -> void:
		nCanvas.graph.clear()
		_place_entry_block())


## 画布上有没有用户搭的东西（编辑菜单用它决定「清空」能不能点）。
## [b]入口块不算[/b]：每个新页都自带一个，算进去的话「清空」永远不会置灰。
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


## 导出为 mlog 文本（纯函数，不改动任何数据）。
## [param warnings] 收集导出期的问题（未锁定的跳转目标等），由调用方负责提示。
func export_mlog(warnings: Array[String] = []) -> String:
	return MlogExporter.export(nCanvas.graph, library, warnings)


## 导出到系统剪贴板，返回写进去的文本。
## [param skip_empty] 为真时，程序为空就不动剪贴板 —— 自动导出（切走窗口）用得上：
## 空程序也照写的话，会把用户刚复制的东西清成空字符串。
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


## 从 mlog 文本导入块。[param append] 为假时先清空当前项目。
## 整个动作（清空 + 插入）算一条撤销记录 —— 快照式撤销让这件事不需要额外的逆操作。
func import_mlog(text: String, append: bool = false) -> int:
	var warnings: Array[String] = []
	var src_lines: Array[int] = []
	var nodes := MlogImporter.parse(text, library, nCanvas.graph, warnings, src_lines)
	if nodes.is_empty():
		for message in warnings:
			push_warning(message)
		return 0
	# 追加时，导入块的整体行号要加上「已有程序占掉的行数」：mlog 的 jump 用的是绝对行号
	var line_offset := MlogExporter.line_count(nCanvas.graph, library) if append else 0
	nCanvas.history.record("导入 %d 个块" % nodes.size(), func() -> void:
		if not append:
			# 换掉当前程序：入口块跟着回来（Special 在调色板里是隐藏的，不回来就再也加不出）
			nCanvas.graph.clear()
			_place_entry_block()
		var target := self._import_target(Vector2(40, 40))
		for node in nodes:
			nCanvas.graph.insert_node(node, int(target["owner_id"]), StringName(target["slot"]), -1)
		# 块都入图了，现在才谈得上「第 N 行是哪一块」
		MlogImporter.bind_links(nodes, src_lines, line_offset, nCanvas.graph, library, warnings))
	for message in warnings:
		push_warning(message)
	return nodes.size()


## Ctrl+V：把 mlog 转成块，放进一条[b]新链[/b]摆在现有内容下方 —— 与现有块不连接，中间留一段空隙。
##
## 与 [method import_mlog] 的区别就在「接不接上」：那两个菜单项是接进入口块那条链（能导出）；
## 这个是另起一条，拿去当草稿或拼装素材，要接上去自己拖。
## 行号偏移取 0：粘贴进来的片段自成一体，jump 的行号就是它自己的行号。
func paste_mlog_new_chain(text: String) -> int:
	var warnings: Array[String] = []
	var src_lines: Array[int] = []
	var nodes := MlogImporter.parse(text, library, nCanvas.graph, warnings, src_lines)
	if nodes.is_empty():
		for message in warnings:
			push_warning(message)
		return 0
	var pos := _paste_position()
	nCanvas.history.record("粘贴 %d 个块" % nodes.size(), func() -> void:
		var chain := nCanvas.graph.create_chain(pos)
		for node in nodes:
			nCanvas.graph.insert_node(node, LogicGraph.ROOT, chain, -1)
		# 块都入图了，现在才谈得上「第 N 行是哪一块」
		MlogImporter.bind_links(nodes, src_lines, 0, nCanvas.graph, library, warnings))
	for message in warnings:
		push_warning(message)
	return nodes.size()


## 粘贴位置：现有内容正下方，留 [constant PASTE_GAP] 的空隙。
## 没有内容（理论上不会：新页总有一个入口块）时从固定点开始。
func _paste_position() -> Vector2:
	var rect := nCanvas.content_rect()
	if rect.size == Vector2.ZERO:
		return Vector2(40, 40)
	return Vector2(rect.position.x, rect.end.y + PASTE_GAP)


## 导入的块往哪里插：入口块所在的那条链（导出只走它 —— 插到别的链上等于导不出来）。
## 没有入口块、或入口块被塞进某个巢里时，退回主链。
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
