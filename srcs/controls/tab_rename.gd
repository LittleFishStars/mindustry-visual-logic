class_name TabRename
extends Node

## 标签条的「就地重命名」：单击[b]已选中[/b]的标签或右键任意标签时，
## 在标签上浮一个输入框直接改名（不弹窗、不新开页面）。
##
## 它只认识 [TabContainer] 与标签下标，不认识编辑器页 —— 「改完这个名字要写到哪」
## 由 [signal name_submitted] 交给外壳处理（见 [Main]）。
##
## 两个手势细节：
## [br]- 单击要延迟一个双击间隔才开输入框，否则双击关标签时会先闪出一个重命名框；
## [br]- 按住拖走（重排标签）就取消排队中的改名。

## 名字提交了：[param index] 是标签下标，[param value] 是用户输入的内容（空 = 回落默认）。
signal name_submitted(index: int, value: String)
## 双击某个标签 = 关掉它（关掉最后一个要补一个空白页，那是外壳的事）。
signal close_requested(index: int)

## 单击后等多久才开重命名框（毫秒）：与引擎判定双击用的间隔取同一个值（Godot 的 Viewport
## 里是这个字面量，没有暴露成项目设置），于是双击时永远不会先闪出一个重命名框。
const RENAME_DELAY_MS: int = 400
## 按下后鼠标挪动超过这么多像素，就当「在拖动重排标签」，不再弹重命名框。
const DRAG_CANCEL_PX: float = 4.0

var _tabs: TabContainer = null
## 标签条上的就地重命名输入框（TabBar 的子节点，不占标签页）。
var _edit: LineEdit = null
## 正在重命名的标签下标（-1 = 没在重命名）。
var _index: int = -1
## 等待中的重命名：单击后要等过一个双击间隔再开输入框。
var _pending_index: int = -1
var _pending_token: int = 0
## 标签上按下时的位置：按住后拖走（重排标签）就取消排队中的改名。
var _press_pos: Vector2 = Vector2.ZERO


## 接管一个标签容器的标签条（在它和它的标签条都进树之后调用）。
func setup(tabs: TabContainer) -> void:
	_tabs = tabs
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return
	# 用 gui_input 而不是 tab_clicked 信号：信号是在内建处理[b]之后[/b]才发的，那时当前页已经
	# 切过去了（分不出「切页」与「点已选中的页」），也拿不到引擎判定的 double_click。
	bar.gui_input.connect(_on_tab_gui_input)
	bar.tab_rmb_clicked.connect(open)
	_edit = LineEdit.new()
	_edit.hide()
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.text_submitted.connect(func(_text: String) -> void: commit())
	_edit.focus_exited.connect(commit)
	_edit.gui_input.connect(_on_rename_input)
	bar.add_child(_edit)


## 在某个标签上就地编辑它的名字（鼠标右键或单击已选中标签时调用）。
func open(index: int) -> void:
	if _edit == null or index < 0 or index >= _tabs.get_tab_count():
		return
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return
	if _index == index and _edit.visible:
		# 已经在改这个名字了：不要把正在输入的内容重置回标签标题
		_edit.grab_focus()
		return
	_index = index
	var rect := bar.get_tab_rect(index)
	_edit.text = _tabs.get_tab_title(index)
	_edit.position = rect.position
	_edit.size = Vector2(maxf(rect.size.x, 96.0), rect.size.y)
	_edit.show()
	_edit.grab_focus()
	_edit.select_all()


## 提交：把输入框里的内容发出去（空名字由外壳回落到文件名），并收起输入框。
func commit() -> void:
	if _index < 0 or _edit == null:
		return
	var index := _index
	var value := _edit.text
	close()
	name_submitted.emit(index, value)


## 收起输入框。先清下标再放焦点：release_focus 会发 focus_exited，
## 不这样做会递归回到 [method commit]。
func close() -> void:
	_index = -1
	if _edit != null:
		_edit.hide()
		_edit.release_focus()


## 标签条上的鼠标按下：单击[b]已选中[/b]的标签 = 重命名，双击任意标签 = 关闭它。
##
## [param event] 的位置是 TabBar 局部坐标；这里拿到的事件早于内建处理，
## 所以既能看到「点击前的当前页」（用来区分切页与重命名），也能用引擎给的 double_click。
func _on_tab_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 按住左键拖走 = 在拖动重排标签（不是要改名）：取消排队中的改名
		# （没按着键的鼠标移动不算：单击后随手挪开鼠标不应该把改名吞掉）
		if _pending_index >= 0 \
				and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
				and (event.position - _press_pos).length() > DRAG_CANCEL_PX:
			_cancel_pending()
		return
	if not (event is InputEventMouseButton) or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	_press_pos = event.position
	var index := _tab_at(event.position)
	if index < 0:
		return
	if event.double_click:
		# 双击：第一下已经把页切过来了，所以双击任意标签都是「关掉它」
		_cancel_pending()
		close_requested.emit(index)
		return
	if index != _tabs.current_tab:
		# 点别的标签 = 切页（内建处理会做），不改名
		return
	queue(index)


## 单击后不立刻开输入框：等过一个双击间隔，期间来了第二次点击（双击关了标签）就取消。
func queue(index: int) -> void:
	_pending_index = index
	_pending_token += 1
	var token := _pending_token
	await get_tree().create_timer(RENAME_DELAY_MS / 1000.0).timeout
	if token != _pending_token or _pending_index != index:
		return
	_pending_index = -1
	open(index)


func _cancel_pending() -> void:
	_pending_index = -1
	_pending_token += 1


## 点在哪个标签上（[param point] 是 TabBar 局部坐标）；没命中返回 -1。
func _tab_at(point: Vector2) -> int:
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return -1
	for i in _tabs.get_tab_count():
		if bar.get_tab_rect(i).has_point(point):
			return i
	return -1


func _on_rename_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		_edit.accept_event()
