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
	if node != null and node.has_signal(&"name_changed"):
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


func _on_editor_name_changed(_display: String, editor: LogicEditorTab) -> void:
	_refresh_tab_title(editor)

#endregion


#region 文件菜单

## 文件菜单：0 新建 / 1 保存 / 2 另存为 / 3 打开 / 4 导出到剪贴板 / 5 撤销 / 6 重做 / 7 退出
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
			self._undo()
		6:
			self._redo()
		7:
			self.get_tree().quit()
		8:
			self._import_clipboard(false)
		9:
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
