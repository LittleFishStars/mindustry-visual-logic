class_name CanvasPointerSession
extends Node

## 画布上的「指针会话」公共部分：搬块（[DragController]）与拖跳转目标（[LinkController]）
## 都长在这个基类上。
##
## 两者同构：挂在编辑器标签页根下（[b]不在[/b] SubViewport 里，所以拖到画布之外也收得到
## 事件）、开始时记下鼠标位置、每帧更新、松手时落地、右键 / Esc / 窗口失焦时取消。
## 差异只有三处，由子类用钩子回答：
##
## [br]- [method _finish_button]：哪个键松开算落地（搬块是「开始拖拽的那个键」）；
## [br]- [method _is_cancel_button]：哪个键按下算取消；
## [br]- [method _consumes_release]：松开事件要不要消费。
##
## 会话本身的状态（拿起了哪串块、要落在哪）留在子类里 —— 基类只认识「一次指针会话」。

## 画布，以及会话覆盖的区域（SubViewportContainer，用来把屏幕坐标换算成世界坐标）。
var canvas: EditorCanvas
var area: SubViewportContainer
## 拖到这里松手 = 删掉搬的块 / 解除锁定（左侧块列表：分类按钮 + 块列表）。
var delete_zones: Array[Control] = []

## 按下后鼠标挪动超过这么多像素才算「真的搬动了」；原地松手 = 什么都没搬。
const MOVE_THRESHOLD: float = 4.0

var _active: bool = false
## 按下时的鼠标位置：用来判断「原地松手」。
var _start_mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_process(false)


func is_active() -> bool:
	return _active


## 取消这次会话（右键 / Esc / 失焦）：本身不改任何数据。
## 需要把画布上的临时位置复原的子类覆写它（搬块就覆写了）。
func cancel() -> void:
	if not _active:
		return
	_close_session()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var button: MouseButton = (event as InputEventMouseButton).button_index
	if event.pressed:
		# 另一个键按下 = 取消（左键搬移时按右键、右键复制时按左键……）
		if _is_cancel_button(button):
			cancel()
			get_viewport().set_input_as_handled()
	elif button == _finish_button():
		_finish_session()
		# [b]默认不消费松开事件[/b]：画布是 SubViewport，而 SubViewportContainer 正是靠
		# is_input_handled() 决定要不要把事件转发进去 —— 一口吞掉 mouse-up，画布里那层
		# GUI 的鼠标焦点与按键掩码就清不掉，之后的左键按下会被发到残留的那个块上
		# （鼠标不在它身上时 _has_point 为假，于是「拖不动块」，要点一下空白才恢复）。
		if _consumes_release():
			get_viewport().set_input_as_handled()


## 拖拽期间窗口失焦（切窗口 / 在窗口外松手）：收尾的 mouse-up 多半收不到了，主动取消 ——
## 否则会话一直挂着，切回来之后会「拖不动任何块」，要点一下别处才恢复。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _active:
		cancel()


func _process(_delta: float) -> void:
	if _active:
		_update_session()


## 会话开始：子类把自己的状态摆好之后调用（它不负责那次拖拽的初始化）。
func _begin_session() -> void:
	_start_mouse = _world_mouse()
	_active = true
	# 会话期间画布不该被相机平移抢走（左键既是平移也是搬块）
	if canvas != null and canvas.nCamera != null:
		canvas.nCamera.stop_panning()
	_on_session_started()
	set_process(true)
	_update_session()


## 鼠标在画布世界坐标下的位置。
func _world_mouse() -> Vector2:
	return canvas.world_from_screen(area.get_global_rect(), get_viewport().get_mouse_position())


## 鼠标是否停在「拖到这里就删掉」的区域（左侧块列表）。
func _over_delete_zone() -> bool:
	var mouse := get_viewport().get_mouse_position()
	for zone in delete_zones:
		if is_instance_valid(zone) and zone.is_visible_in_tree() and zone.get_global_rect().has_point(mouse):
			return true
	return false


## 鼠标是否还在画布区域内（在外面松手 = 取消）。
func _inside_canvas() -> bool:
	if area == null or not is_instance_valid(area):
		return false
	return area.get_global_rect().has_point(get_viewport().get_mouse_position())


## 与按下点相比，鼠标是不是真的挪动过。
func _moved(world: Vector2) -> bool:
	return (world - _start_mouse).length() > MOVE_THRESHOLD


#region 子类钩子

## 哪个键松开算落地。
func _finish_button() -> MouseButton:
	return MOUSE_BUTTON_LEFT


## 哪个键按下算取消（默认：不是落地键的那个）。
func _is_cancel_button(button: MouseButton) -> bool:
	return button != _finish_button()


## 松开事件要不要消费（默认不消费，理由见 [method _input] 的注释）。
func _consumes_release() -> bool:
	return false


## 会话状态摆好之后、进入每帧更新之前的一次性动作。
func _on_session_started() -> void:
	pass


## 每帧更新（子类实现）。
func _update_session() -> void:
	pass


## 松手落地（子类实现；收尾请自行调 [method _close_session]）。
func _finish_session() -> void:
	pass


## 清掉这次会话的状态与画布上的临时效果（子类实现，取消与落地都会走到）。
func _close_session() -> void:
	pass

#endregion
