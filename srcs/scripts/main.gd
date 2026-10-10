@tool
extends Container

## 应用外壳：菜单栏、多标签编辑器、文件对话框、公告窗、自定义光标。
##
## 编辑器标签页（[LogicEditorTab]）只负责画布与调色板；文件读写、mlog 导出都通过它的公开方法，
## 这里只做菜单分发 —— 旧实现把保存/加载/导出的细节和节点树打包在一起，加一个功能要动好几处。

@onready var nMenuBar: Control = $MenuBar
@onready var nEditors: TabContainer = $Editors
@onready var nBackground: Panel = $Panel
@onready var wNotice: Window = $NoticeWindow
@onready var wProject: FileDialog = $ProjectDialog
## 编辑菜单（撤销 / 重做 / 清空）：弹出前按当前标签页的状态置灰。
@onready var nEditMenu: PopupMenu = $MenuBar/Edit

var Editor = preload("res://srcs/scenes/editor.tscn")

var custom_cursor = preload("res://assets/sprites/cursors/cursor.png")
var ibeam_cursor = preload("res://assets/sprites/cursors/ibeam.png")
var hand_cursor = preload("res://assets/sprites/cursors/hand.png")
var hsize_cursor = preload("res://assets/sprites/cursors/hsize.png")
var vsize_cursor = preload("res://assets/sprites/cursors/vsize.png")
var bdiagsize_cursor = preload("res://assets/sprites/cursors/bdiagsize.png")
var fdiagsize_cursor = preload("res://assets/sprites/cursors/fdiagsize.png")

## 文件对话框当前是"保存"还是"打开"。
var _dialog_mode: StringName = &"open"

## 标签条上的就地重命名输入框（TabBar 的子节点，不占标签页）。
var _rename_edit: LineEdit = null
## 正在重命名的标签下标（-1 = 没在重命名）。
var _rename_index: int = -1
## 等待中的重命名：单击后要等过一个双击间隔再开输入框，否则双击关标签时会闪一下。
var _pending_rename_tab: int = -1
var _pending_rename_token: int = 0
## 标签上按下时的位置：按住后拖走（重排标签）就取消排队中的改名。
var _press_pos: Vector2 = Vector2.ZERO
## 单击后等多久才开重命名框（毫秒）：与引擎判定双击用的间隔取同一个值（Godot 的 Viewport
## 里是这个字面量，没有暴露成项目设置），于是双击时永远不会先闪出一个重命名框。
const RENAME_DELAY_MS: int = 400
## 按下后鼠标挪动超过这么多像素，就当“在拖动重排标签”，不再弹重命名框。
const DRAG_CANCEL_PX: float = 4.0

func _ready() -> void:
	# 设置鼠标指针
	Input.set_custom_mouse_cursor(custom_cursor, Input.CURSOR_ARROW, Vector2(32, 32))
	Input.set_custom_mouse_cursor(ibeam_cursor, Input.CURSOR_IBEAM, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hand_cursor, Input.CURSOR_POINTING_HAND, Vector2(32, 32))
	Input.set_custom_mouse_cursor(vsize_cursor, Input.CURSOR_VSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hsize_cursor, Input.CURSOR_HSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(bdiagsize_cursor, Input.CURSOR_BDIAGSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(fdiagsize_cursor, Input.CURSOR_FDIAGSIZE, Vector2(32, 32))

	# 创建初始编辑器
	self.new_editor()
	self._setup_tab_rename()


func _on_sort_children() -> void:
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x, 0)))
	fit_child_in_rect(self.nEditors, Rect2(0, self.nMenuBar.size.y, self.size.x, self.size.y - self.nMenuBar.size.y))
	fit_child_in_rect(self.nBackground, Rect2(Vector2.ZERO, self.size))


#region 标签页

## 新建页面: 将 [param scn] 添加到标签页，默认名称为 [param title] 。
func new_page(title: StringName, scn: Resource) -> Node:
	var node = scn.instantiate()
	var count = 1
	self.nEditors.add_child(node)
	self.nEditors.current_tab = node.get_index()
	while self.nEditors.has_node(title + str(count)):
		count += 1
	node.name = title + str(count)
	return node


## 新建编辑器页面
func new_editor() -> LogicEditorTab:
	var node := self.new_page(tr("File", "main"), self.Editor) as LogicEditorTab
	if node != null:
		node.name_changed.connect(_on_editor_name_changed.bind(node))
		_refresh_tab_title(node)
	return node


func _current_editor() -> LogicEditorTab:
	return self.nEditors.get_current_tab_control() as LogicEditorTab


func _refresh_tab_title(editor: LogicEditorTab) -> void:
	if editor == null or not is_instance_valid(editor):
		return
	var index := editor.get_index()
	if index >= 0 and index < self.nEditors.get_tab_count():
		self.nEditors.set_tab_title(index, editor.display_name())
		self.nEditors.set_tab_tooltip(index, "双击关闭 · 右键重命名")


func _on_editor_name_changed(_display: String, editor: LogicEditorTab) -> void:
	_refresh_tab_title(editor)


## 标签条手势：单击[b]已选中[/b]的标签 = 就地重命名，双击任意标签 = 关闭它，
## 右键任意标签 = 重命名。回车/失焦/切页提交，Esc 取消；空名字 = 回落到跟随文件名。
## 单击要延迟一个双击间隔才开输入框 —— 否则双击关标签时会先闪出一个重命名框。
func _setup_tab_rename() -> void:
	var bar := self.nEditors.get_tab_bar()
	if bar == null:
		return
	# 用 gui_input 而不是 tab_clicked 信号：信号是在内建处理[b]之后[/b]才发的，那时当前页已经切过去了，
	# 也拿不到引擎判定的 double_click（见下方注释）。
	bar.gui_input.connect(_on_tab_gui_input)
	bar.tab_rmb_clicked.connect(_open_rename)
	self.nEditors.tab_changed.connect(_on_tab_changed)
	self._rename_edit = LineEdit.new()
	self._rename_edit.hide()
	self._rename_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	self._rename_edit.text_submitted.connect(func(_text: String) -> void:
		self._commit_rename())
	self._rename_edit.focus_exited.connect(_commit_rename)
	self._rename_edit.gui_input.connect(_on_rename_input)
	bar.add_child(self._rename_edit)


## 标签条上的鼠标按下：单击[b]已选中[/b]的标签 = 重命名，双击任意标签 = 关闭它。
##
## [param event] 的位置是 TabBar 局部坐标；这里拿到的事件早于内建处理，
## 所以既能看到「点击前的当前页」（用来区分切页与重命名），也能用引擎给的 double_click。
func _on_tab_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 按住左键拖走 = 在拖动重排标签（不是要改名）：取消排队中的改名
		# （没按着键的鼠标移动不算：单击后随手挪开鼠标不应该把改名吞掉）
		if self._pending_rename_tab >= 0 \
				and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
				and (event.position - self._press_pos).length() > DRAG_CANCEL_PX:
			self._cancel_pending_rename()
		return
	if not (event is InputEventMouseButton) or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	self._press_pos = event.position
	var index := self._tab_at(event.position)
	if index < 0:
		return
	if event.double_click:
		# 双击：第一下已经把页切过来了，所以双击任意标签都是「关掉它」
		self._cancel_pending_rename()
		self._close_tab(index)
		return
	if index != self.nEditors.current_tab:
		# 点别的标签 = 切页（内建处理会做），不改名
		return
	self._queue_rename(index)


## 点在哪个标签上（[param point] 是 TabBar 局部坐标）；没命中返回 -1。
func _tab_at(point: Vector2) -> int:
	var bar := self.nEditors.get_tab_bar()
	if bar == null:
		return -1
	for i in self.nEditors.get_tab_count():
		if bar.get_tab_rect(i).has_point(point):
			return i
	return -1


## 单击后不立刻开输入框：等过一个双击间隔，期间来了第二次点击（双击关了标签）就取消。
func _queue_rename(index: int) -> void:
	self._pending_rename_tab = index
	self._pending_rename_token += 1
	var token := self._pending_rename_token
	await self.get_tree().create_timer(RENAME_DELAY_MS / 1000.0).timeout
	if token != self._pending_rename_token or self._pending_rename_tab != index:
		return
	self._pending_rename_tab = -1
	self._open_rename(index)


func _cancel_pending_rename() -> void:
	self._pending_rename_tab = -1
	self._pending_rename_token += 1


## 双击已选中的标签：关掉这个标签页；关掉最后一个就补一个空白页。
func _close_tab(index: int) -> void:
	self._close_rename()
	if index < 0 or index >= self.nEditors.get_tab_count():
		return
	var page := self.nEditors.get_tab_control(index)
	if page != null:
		self.nEditors.remove_child(page)
		page.queue_free()
	if self.nEditors.get_tab_count() == 0:
		self.new_editor()


func _on_tab_changed(_tab: int) -> void:
	# 切页/新增页时先把没提交的名字落下去，免得输入框留在旧标签的位置上
	self._commit_rename()


## 把输入框摆在那个标签上就地编辑（不另弹窗）。
func _open_rename(index: int) -> void:
	if self._rename_edit == null or index < 0 or index >= self.nEditors.get_tab_count():
		return
	var bar := self.nEditors.get_tab_bar()
	if bar == null:
		return
	if self._rename_index == index and self._rename_edit.visible:
		# 已经在改这个名字了：不要把正在输入的内容重置回标签标题
		self._rename_edit.grab_focus()
		return
	self._rename_index = index
	var rect := bar.get_tab_rect(index)
	self._rename_edit.text = self.nEditors.get_tab_title(index)
	self._rename_edit.position = rect.position
	self._rename_edit.size = Vector2(maxf(rect.size.x, 96.0), rect.size.y)
	self._rename_edit.show()
	self._rename_edit.grab_focus()
	self._rename_edit.select_all()


func _on_rename_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		self._close_rename()
		self._rename_edit.accept_event()


## 提交：写进标签页的自定义名（空 = 回落到文件名）。
func _commit_rename() -> void:
	if self._rename_index < 0 or self._rename_edit == null:
		return
	var index := self._rename_index
	var value := self._rename_edit.text
	self._close_rename()
	var editor := self._editor_at(index)
	if editor != null:
		editor.set_custom_name(value)
		self._refresh_tab_title(editor)


## 收起输入框。先清下标再放焦点：release_focus 会发 focus_exited，
## 不这样做会递归回到 [_commit_rename]。
func _close_rename() -> void:
	self._rename_index = -1
	if self._rename_edit != null:
		self._rename_edit.hide()
		self._rename_edit.release_focus()


func _editor_at(index: int) -> LogicEditorTab:
	if index < 0 or index >= self.nEditors.get_tab_count():
		return null
	return self.nEditors.get_tab_control(index) as LogicEditorTab
#endregion

#region 编辑菜单

## 编辑菜单：0 撤销 / 1 重做 / 2 清空
func _on_edit_id_pressed(id: int) -> void:
	match id:
		0:
			self._undo()
		1:
			self._redo()
		2:
			self._clear_current()


## 菜单弹出来之前刷一下可用性：没得撤销/重做、画布本来就空，就置灰。
func _on_edit_about_to_popup() -> void:
	var editor := self._current_editor()
	self.nEditMenu.set_item_disabled(0, editor == null or not editor.can_undo())
	self.nEditMenu.set_item_disabled(1, editor == null or not editor.can_redo())
	self.nEditMenu.set_item_disabled(2, editor == null or editor.is_empty())


## 清空当前项目的所有块（[method LogicEditorTab.clear_graph] 会记一条可撤销的记录）。
func _clear_current() -> void:
	var editor := self._current_editor()
	if editor != null:
		editor.clear_graph()


#endregion


#region 文件菜单

## 文件菜单：0 新建 / 1 保存 / 2 另存为 / 3 打开 / 4 导出到剪贴板 / 5 退出 /
## 6 从剪贴板导入 / 7 追加导入（撤销、重做、清空都在编辑菜单里）
func _on_file_id_pressed(id: int) -> void:
	match id:
		0:
			self.new_editor()
		1:
			self._save_current(false)
		2:
			self._save_current(true)
		3:
			self._open_project()
		4:
			self._export_to_clipboard()
		5:
			self.get_tree().quit()
		6:
			self._import_clipboard(false)
		7:
			self._import_clipboard(true)


func _save_current(force_dialog: bool) -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	if not force_dialog and editor.file_path != "":
		var error := editor.save_to(editor.file_path)
		if error != OK:
			push_warning(GraphSerializer.last_error())
		return
	_dialog_mode = &"save"
	self.wProject.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	self.wProject.title = "保存项目"
	self.wProject.current_file = editor.display_name() + GraphSerializer.FILE_EXTENSION
	self.wProject.popup_centered()


func _open_project() -> void:
	_dialog_mode = &"open"
	self.wProject.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	self.wProject.title = "打开项目"
	self.wProject.popup_centered()


func _on_project_dialog_file_selected(path: String) -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	if _dialog_mode == &"save":
		var error := editor.save_to(path)
		if error != OK:
			push_warning(GraphSerializer.last_error())
		return
	if path.get_extension() == "":
		path += GraphSerializer.FILE_EXTENSION
	if not editor.load_from(path):
		push_warning(GraphSerializer.last_error())


## 导出当前编辑器的 mlog 到系统剪贴板（旧版的「快捷导出」行为）。
func _export_to_clipboard() -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	var text := editor.copy_mlog_to_clipboard()
	print("[MVL] 已导出 %d 行 mlog 到剪贴板" % text.count("\n"))


func _undo() -> void:
	var editor := self._current_editor()
	if editor != null:
		editor.undo()


## 从系统剪贴板读取 mlog 并导入。[param append] 为真时追加到当前项目。
func _import_clipboard(append: bool) -> void:
	var editor := self._current_editor()
	if editor == null:
		return
	var text := DisplayServer.clipboard_get()
	var count := editor.import_mlog(text, append)
	if count == 0:
		push_warning("剪贴板里没有可识别的 mlog")
	return


func _redo() -> void:
	var editor := self._current_editor()
	if editor != null:
		editor.redo()

#endregion


#region 帮助菜单

## 帮助菜单：0 文档 / 1 公告 / 2 关于
func _on_help_id_pressed(id: int) -> void:
	match id:
		0:
			# 文档
			pass
		1:
			self.wNotice.show()
		2:
			# 关于
			pass

#endregion
