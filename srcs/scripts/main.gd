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
## 工具栏右侧的退出按钮（不再藏在文件菜单里）。
@onready var nQuitButton: Button = $Quit
## 编辑菜单（撤销 / 重做 / 清空）：弹出前按当前标签页的状态置灰。
@onready var nEditMenu: PopupMenu = $MenuBar/Edit
## 文件菜单：给「导出到剪贴板」挂 F5 快捷键显示。
@onready var nFileMenu: PopupMenu = $MenuBar/File
## 设置窗口（帧率上限 / UI 缩放 / 失焦自动导出）。
@onready var wSettings: SettingsWindow = $SettingsWindow
## 关于窗（版本 / 作者 / 反馈渠道）。
@onready var wAbout: AboutWindow = $AboutWindow

var Editor = preload("res://srcs/scenes/editor.tscn")
## 文档页是标签页系统里的一个页面（不是编辑器），所以是代码实例化而不是场景里的节点。
var Document = preload("res://srcs/controls/document_page.tscn")

var custom_cursor = preload("res://assets/sprites/cursors/cursor.png")
var ibeam_cursor = preload("res://assets/sprites/cursors/ibeam.png")
var hand_cursor = preload("res://assets/sprites/cursors/hand.png")
var hsize_cursor = preload("res://assets/sprites/cursors/hsize.png")
var vsize_cursor = preload("res://assets/sprites/cursors/vsize.png")
var bdiagsize_cursor = preload("res://assets/sprites/cursors/bdiagsize.png")
var fdiagsize_cursor = preload("res://assets/sprites/cursors/fdiagsize.png")

## 文件对话框当前是"保存"还是"打开"。
var _dialog_mode: StringName = &"open"

## 标签条的「就地重命名」：手势与输入框都在 [TabRename] 里，外壳只接「改完写到哪」。
var _rename: TabRename = null
## F5 快捷导出的输入动作名：沿用旧版 project.godot 里的 `compile`（旧版把「导出 mlog」
## 叫 compile）。键位写在 project.godot 的 [input] 段里 —— 换键改那里，代码不用动。
const QUICK_EXPORT_ACTION: StringName = &"compile"
## Ctrl+C 快速复制全部内容到剪贴板（就是导出那件事），## Ctrl+V 把剪贴板内容粘成新链。
## 同样只认这里几个常量 —— 键位在 project.godot。
##
## 这两个不入菜单：菜单项的 accelerator 只有一根，F5 已经占着了；而且 Ctrl+C/V
## 得先让输入框拿到（在 LineEdit 里它们就是普通的复制/粘贴文字），
## 所以走 [method _unhandled_key_input] 兜底刚好。
const QUICK_COPY_ACTION: StringName = &"copy_mlog"
const QUICK_PASTE_ACTION: StringName = &"paste_mlog"

## 应用设置（[AppSettings]）：打开时读盘、改完即时应用、关窗时写盘。
var _settings: AppSettings = null
func _ready() -> void:
	# 设置鼠标指针
	Input.set_custom_mouse_cursor(custom_cursor, Input.CURSOR_ARROW, Vector2(32, 32))
	Input.set_custom_mouse_cursor(ibeam_cursor, Input.CURSOR_IBEAM, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hand_cursor, Input.CURSOR_POINTING_HAND, Vector2(32, 32))
	Input.set_custom_mouse_cursor(vsize_cursor, Input.CURSOR_VSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hsize_cursor, Input.CURSOR_HSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(bdiagsize_cursor, Input.CURSOR_BDIAGSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(fdiagsize_cursor, Input.CURSOR_FDIAGSIZE, Vector2(32, 32))
	# 读设置并应用（帧率 / UI 缩放）；设置窗口只负责改数据，应用在这里
	self._settings = AppSettings.load_from_disk()
	self._apply_settings()
	self.wSettings.setup(self._settings)
	self.wSettings.changed.connect(_on_settings_changed)
	self.wSettings.closed.connect(_on_settings_closed)

	# 给「File → 导出到剪贴板」挂上 F5：菜单里能看见键位，按下去也真的触发
	self.nFileMenu.set_item_accelerator(4, KEY_F5)

	# 创建初始编辑器
	self.new_editor()
	self._setup_tab_rename()


func _on_sort_children() -> void:
	fit_child_in_rect(self.nBackground, Rect2(Vector2.ZERO, Vector2(self.size)))
	# 工具栏一行：左边菜单栏，右边退出按钮（先量行高，再按它的宽度把菜单栏缩回去）
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x, 0)))
	var row_height := self.nMenuBar.size.y
	var quit_width: float = maxf(self.nQuitButton.get_combined_minimum_size().x, 72.0)
	fit_child_in_rect(self.nQuitButton, Rect2(self.size.x - quit_width, 0, quit_width, row_height))
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x - quit_width, row_height)))
	fit_child_in_rect(self.nEditors, Rect2(0, row_height, self.size.x, self.size.y - row_height))


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


## 标签条手势：单击[b]已选中[/b]的标签 / 右键任意标签 = 就地重命名，双击 = 关闭标签页。
## 手势与输入框都在 [TabRename] 里，外壳只接「改完的名字写到哪」（见 [method _on_tab_renamed]）。
func _setup_tab_rename() -> void:
	self.nEditors.tab_changed.connect(_on_tab_changed)
	self._rename = TabRename.new()
	self.add_child(self._rename)
	self._rename.setup(self.nEditors)
	self._rename.name_submitted.connect(_on_tab_renamed)
	self._rename.close_requested.connect(_close_tab)


## 双击已选中的标签：关掉这个标签页；关掉最后一个就补一个空白页。
func _close_tab(index: int) -> void:
	self._rename.close()
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
	self._rename.commit()


## 标签改完名：写进标签页的自定义名（空 = 回落到文件名），再刷一遍标签标题。
func _on_tab_renamed(index: int, value: String) -> void:
	var editor := self._editor_at(index)
	if editor != null:
		editor.set_custom_name(value)
		self._refresh_tab_title(editor)


func _editor_at(index: int) -> LogicEditorTab:
	if index < 0 or index >= self.nEditors.get_tab_count():
		return null
	return self.nEditors.get_tab_control(index) as LogicEditorTab
#endregion

#region 编辑菜单

## 编辑菜单：0 撤销 / 1 重做 / 2 清空 / 3 设置
func _on_edit_id_pressed(id: int) -> void:
	match id:
		0:
			self._undo()
		1:
			self._redo()
		2:
			self._clear_current()
		3:
			self.wSettings.open()


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


#region 设置
## 把设置搬到引擎上：帧率上限与整个 UI 的缩放。
## 编辑器里（@tool）跳过 —— 否则会顺手改掉 Godot 编辑器自己的帧率和界面缩放。
func _apply_settings() -> void:
	if _settings == null or Engine.is_editor_hint():
		return
	Engine.max_fps = _settings.max_fps
	get_tree().root.content_scale_factor = _settings.ui_scale


## 设置窗口里改了值：立刻生效（还没写盘）。
func _on_settings_changed() -> void:
	self._apply_settings()


## 设置窗口关了：写盘。
func _on_settings_closed() -> void:
	self._apply_settings()
	var error := _settings.save_to_disk()
	if error != OK:
		push_warning("设置没能写进 %s（错误码 %d）" % [AppSettings.path, error])


## 切走窗口（切到别的应用）：按设置把当前标签页的 mlog 自动丢进剪贴板。
##
## 只认 APPLICATION_FOCUS_OUT：它在桌面与移动端都实现，语义正好是「焦点离开本程序」——
## 而 WM_WINDOW_FOCUS_OUT 在本程序的两个窗口之间切换时也会发，那时并不该导出
## （所以两个都监听会重复导出）。
## 空程序不写剪贴板（别把用户刚复制的东西清空），当前页不是编辑器（如文档页）也不动。
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or _settings == null:
		return
	if not _settings.export_on_focus_lost:
		return
	var editor := self._current_editor()
	if editor == null:
		return
	var text := editor.copy_mlog_to_clipboard(true)
	if text.strip_edges() == "":
		print("[MVL] 失焦自动导出：当前页没有 mlog，剪贴板保持不变")
		return
	print("[MVL] 失焦自动导出 %d 行 mlog 到剪贴板" % text.count("\n"))


#endregion

#region 文件菜单

## 文件菜单：0 新建 / 1 保存 / 2 另存为 / 3 打开 / 4 导出到剪贴板（F5）/
## 5 从剪贴板导入 / 6 追加导入（撤销、重做、清空在编辑菜单里，退出在工具栏右侧）
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
			self._import_clipboard(false)
		6:
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
## 菜单项、菜单栏的 F5、[method _unhandled_key_input] 三条路都走这里，
## 所以「当前页没有可导出的东西」的提示只需要写一处。
func _export_to_clipboard() -> void:
	var editor := self._current_editor()
	if editor == null:
		print("[MVL] 当前页没有逻辑可导出（导出只对编辑器页有意义）")
		return
	var text := editor.copy_mlog_to_clipboard()
	print("[MVL] 已导出 %d 行 mlog 到剪贴板" % text.count("\n"))

## F5 快捷导出：与「File → Export to clipboard」同一件事，只是不用点菜单。
func _quick_export() -> void:
	self._export_to_clipboard()


## F5 的兜底路径：动作名指向 project.godot 的 [input] 定义（换键位只改那一个文件）。
## 平时事件在菜单栏就被「Export to clipboard」的 accelerator 接走了（菜单里能看见 F5），
## 这里只为“事件没到菜单栏”的焦点情形保留 —— 别到手了才发现 F5 是个哑键。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(QUICK_EXPORT_ACTION):
		self._quick_export()
		self.get_viewport().set_input_as_handled()
		return
	# Ctrl+C / Ctrl+V：只在没人接的时候才当“整页操作”。
	# 输入框有焦点时，这两下会被 LineEdit 自己吃掉（复制/粘贴文字），根本到不了这里 ——
	# 这正是想要的：在块里的输入框上 Ctrl+V，不该突然多出一链块。
	if event.is_action_pressed(QUICK_COPY_ACTION):
		self._export_to_clipboard()
		self.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(QUICK_PASTE_ACTION):
		self._paste_clipboard_as_chain()
		self.get_viewport().set_input_as_handled()


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


## Ctrl+V：读剪贴板 → 转成块 → 放成一条新链（不接到现有块上，摆在它们下面）。
##
## 与 File 菜单里那两个导入项的区别就在“接不接上”：菜单项接进入口块那条链（能导出），
## 这里只是摆在下方当草稿/素材，要接上去得自己拖 —— 所以提示语也分开写。
func _paste_clipboard_as_chain() -> void:
	var editor := self._current_editor()
	if editor == null:
		print("[MVL] 当前页没有逻辑可粘贴（粘贴只对编辑器页有意义）")
		return
	var text := DisplayServer.clipboard_get()
	var count := editor.paste_mlog_new_chain(text)
	if count == 0:
		push_warning("剪贴板里没有可识别的 mlog")
		return
	print("[MVL] 已把剪贴板里的 %d 个块粘到下方（未连接）" % count)
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
			self._open_document()
		1:
			self.wNotice.show()
		2:
			self.wAbout.open()


## 文档页：已经开着就切过去，不重复开（否则每点一次多一个标签页）。
func _open_document() -> void:
	var existing := self._document_page()
	if existing != null:
		self.nEditors.current_tab = existing.get_index()
		return
	# 节点名会自动去重（Manual1/Manual2…），但标签标题给它一个干净的名字
	# （编辑器页的标题由 display_name() 刷成「未命名」，文档页没人刷）
	var page := self.new_page("Manual", self.Document)
	self.nEditors.set_tab_title(page.get_index(), "使用说明")


func _document_page() -> DocumentPage:
	for child in self.nEditors.get_children():
		if child is DocumentPage:
			return child
	return null
#endregion


#region 工具栏

## 工具栏右侧的退出按钮（不藏在文件菜单里，瞄一眼就能点到）。
func _on_quit_pressed() -> void:
	self.get_tree().quit()

#endregion
