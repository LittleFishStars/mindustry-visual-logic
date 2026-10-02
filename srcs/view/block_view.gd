class_name BlockView
extends Control

## 一个逻辑块的视图：按 [BlockDef] 建出各行控件、算自己的几何、画自己的背景。
##
## 与旧实现（BlockLayout extends Container）的三个根本差别：
## [br]1. 不再是 [Container]，行的位置由本类显式给出 —— 不再出现「引擎布局」与
##    「手写绝对坐标」两套规则打架，也不需要 `-1/+2` 这类魔法数字来对齐；
## [br]2. 尺寸由 [method measure] 主动算出并返回 [BlockMetrics]，**不再从绘制缓存反读**，
##    所以任何时刻调用都得到一致结果；
## [br]3. 嵌套子块不是本节点的子节点：它们与父块一样是画布的直接子级，
##    位置由布局求解给出 —— 于是「拖拽时 reparent 整条链」这件事彻底不存在了。

## 请求开始拖动（画布/拖拽控制器接管）。
signal drag_requested(view: BlockView, offset: Vector2)
## 某个字段被用户改动（画布负责写进图与撤销栈）。
signal field_committed(node: LogicNode, field_id: StringName, value: Variant, merge_key: StringName)
## 可见性/尺寸变了，需要重新布局。
signal layout_dirty()
## 请求打开选择器（由编辑器标签页提供浮层，避免依赖 Window/Popup）。
signal picker_requested(element: ElementDef, control: Control)
## 输入框失焦等场合：结束当前撤销合并段。
signal history_group_closed()

const FONT: FontFile = preload("res://assets/fonts/font.woff")

const ROW_NORMAL: StringName = &""
const ROW_NEST: StringName = &"nest"
const ROW_TAIL: StringName = &"tail"

@export var margin: int = 6
@export var separation: int = 10
@export var row_height: int = 40
@export var corner_radius: int = 10

var def: BlockDef
var node: LogicNode
## 样品（调色板里的块）或拖拽幽灵：不在图上，改动不写历史。
var preview: bool = false
## 是否接受鼠标（幽灵不接）。
var interactive: bool = true

var metrics: BlockMetrics = null

var _rows: Array[HBoxContainer] = []
var _row_kind: Array[StringName] = []
var _row_slot: Array[StringName] = []
var _row_size: Array[Vector2] = []
var _row_widths: Array[float] = []
var _row_heights: Array[float] = []
## 每个可视行对应的定义行（nest / tail 行为 null）
var _row_def: Array[BlockDef.RowDef] = []
## 该行本轮是否整行不参与布局（条件不成立）
var _row_skip: Array[bool] = []
var _nest_controls: Dictionary[StringName, Control] = {}
var _elements: Dictionary[StringName, Control] = {}
var _element_defs: Dictionary[StringName, ElementDef] = {}
var _button_state: Dictionary[StringName, bool] = {}
var _bg_rects: Array[Rect2] = []
var _styles: Array[StyleBoxFlat] = []


func setup(p_def: BlockDef, p_node: LogicNode, p_preview: bool = false) -> void:
	def = p_def
	node = p_node
	preview = p_preview
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_visibility()
	# 先量一次：调色板样品需要最小尺寸，画布上的块稍后会由求解器重算
	measure({})


func color() -> Color:
	return def.color if def != null else Color.WHITE


#region 元素构建器需要的宿主接口

func font() -> Font:
	return FONT


func block_color() -> Color:
	return color()


func is_preview() -> bool:
	return preview


func node_id() -> int:
	return node.id if node != null else 0


## 取字段当前值（以数据层为准，控件只是显示）。
func field_value(field_id: StringName, fallback: Variant = "") -> Variant:
	if node == null:
		return fallback
	return node.get_field(field_id, fallback)


## 写字段：样品/幽灵直接改临时数据，正式块交给画布走撤销栈。
func commit_field(field_id: StringName, value: Variant, grouped: bool = false) -> void:
	if node == null:
		return
	if preview:
		node.put_field(field_id, value)
		refresh_visibility()
		return
	var merge_key: StringName = &""
	if grouped:
		merge_key = StringName("field:%d:%s" % [node.id, String(field_id)])
	field_committed.emit(node, field_id, value, merge_key)
	# 用户点选时控件本来就对；程序化写入（行为脚本、批量修改）时把它拉回来
	_sync_control(field_id)


## 按钮当前是否按下（供可见性判定）。
func toggle_state(element_id: StringName) -> bool:
	return _button_state.get(element_id, false)


func set_toggle_state(element_id: StringName, pressed: bool) -> void:
	_button_state[element_id] = pressed
	var control: Control = _elements.get(element_id)
	if control is BaseButton:
		(control as BaseButton).set_pressed_no_signal(pressed)


## Option 当前选中的导出值。
func option_value(element: ElementDef) -> String:
	var control: Control = _elements.get(element.id)
	if control is OptionButton and not element.items.is_empty():
		var index := clampi((control as OptionButton).selected, 0, element.items.size() - 1)
		return element.items[index].value_or_text()
	return ""


## 元素当前是否可见（自检/调试用）。
func is_element_visible(element_id: StringName) -> bool:
	var control: Control = _elements.get(element_id)
	return control != null and control.visible


## 元素当前的值字符串（供控件显示与自检使用）。
func element_value(element_id: StringName) -> String:
	var element := def.element(element_id) if def != null else null
	if element == null:
		return ""
	match element.type:
		&"Option":
			return option_value(element)
		&"Button":
			return "true" if toggle_state(element.id) else "false"
		_:
			var control: Control = _elements.get(element_id)
			if control is LineEdit:
				return (control as LineEdit).text
			if control != null and control.has_meta(&"value_control"):
				var inner: Variant = control.get_meta(&"value_control")
				if inner is LineEdit:
					return (inner as LineEdit).text
			return String(field_value(element_id, element.default_value))


func request_picker(element: ElementDef, control: Control) -> void:
	picker_requested.emit(element, control)


func flush_history_group() -> void:
	history_group_closed.emit()

## 控件样式：与旧实现同一套观感（圆角 + 内边距 + 按块配色）。
func control_style(base: Color, hover: bool = false, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var color := base
	if pressed:
		color = base.darkened(0.1)
	elif hover:
		color = base.lightened(0.15)
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style

#endregion


#region 构建

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_row_kind.clear()
	_row_slot.clear()
	_row_size.clear()
	_nest_controls.clear()
	_elements.clear()
	_element_defs.clear()
	_button_state.clear()
	_bg_rects.clear()
	_styles.clear()
	_row_def.clear()
	_row_skip.clear()
	if def == null:
		return
	# 控件一次性建齐并常驻，切换条件只改可见性 —— 不会重建、也不会打断正在输入的控件
	for row_def in def.rows:
		var row: HBoxContainer = null
		for cell in row_def.cells:
			if cell.type == &"Nest":
				# Nest 独占一行（槽里的块是画布的直接子级，这里只作占位）
				row = null
				_make_nest_row(cell, row_def)
				continue
			if row == null:
				row = _make_row(ROW_NORMAL, &"", row_def)
			var control := _build_element(cell)
			if control != null:
				row.add_child(control)
				_elements[cell.id] = control
				_element_defs[cell.id] = cell
	# 没有任何元素的块（如 None）也要有一行，否则它在画布上是不可见也不可点的
	if _rows.is_empty():
		_make_row(ROW_NORMAL, &"", null)
	if not def.elements.is_empty() and def.elements[-1].type == &"Nest":
		_make_row(ROW_TAIL, &"", null)


func _build_element(element: ElementDef) -> Control:
	var builder: Variant = ElementRegistry.builder(element.type)
	if builder == null:
		push_warning("元素种类未注册，已跳过：%s（块 %s）" % [element.type, def.id])
		return null
	var control: Control = builder.build(element, self)
	if control == null:
		return null
	if control is Button:
		button_setup(control as Button, element)
	return control


func button_setup(button: Button, element: ElementDef) -> void:
	var pressed := String(field_value(element.id, "false")) == "true"
	_button_state[element.id] = pressed
	button.set_pressed_no_signal(pressed)


func _make_row(kind: StringName, slot: StringName, row_def: BlockDef.RowDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	# 行本身不吃鼠标，点空白处应当落到块上以开始拖动
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	_rows.append(row)
	_row_kind.append(kind)
	_row_slot.append(slot)
	_row_size.append(Vector2.ZERO)
	_row_def.append(row_def)
	return row


func _make_nest_row(element: ElementDef, row_def: BlockDef.RowDef) -> void:
	var row := _make_row(ROW_NEST, element.id, row_def)
	var placeholder := Control.new()
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.custom_minimum_size = Vector2(separation * 4, row_height / 2.0)
	row.add_child(placeholder)
	_nest_controls[element.id] = placeholder

#endregion


#region 度量与摆放

## 算出本块的几何。[param slot_extents] 是各槽位内子链的总尺寸（自底向上求解传入）。
func measure(slot_extents: Dictionary[StringName, Vector2]) -> BlockMetrics:
	_apply_visibility()
	for slot_id in _nest_controls:
		var placeholder: Control = _nest_controls[slot_id]
		var extent: Vector2 = slot_extents.get(slot_id, Vector2.ZERO)
		if extent == Vector2.ZERO:
			placeholder.custom_minimum_size = Vector2(separation * 4, row_height / 2.0)
		else:
			placeholder.custom_minimum_size = extent
	var value_of := _value_reader()
	var block_width := 0.0
	var total_height := 0.0
	var widths: Array[float] = []
	var heights: Array[float] = []
	_row_skip.clear()
	for i in _rows.size():
		var kind := _row_kind[i]
		var row: Control = _rows[i]
		# 条件不成立的行整行不参与布局（不是"藏起来"，而是不存在）
		var skip := kind == ROW_NORMAL and _row_def[i] != null and not _row_def[i].is_active(value_of)
		_row_skip.append(skip)
		if skip:
			widths.append(0.0)
			heights.append(0.0)
			continue
		var row_w := row.get_combined_minimum_size().x
		var row_h := float(row_height)
		match kind:
			ROW_NEST:
				row_h = maxf(_nest_controls[_row_slot[i]].custom_minimum_size.y, row_height / 2.0)
			ROW_TAIL:
				row_w = separation * 8
				row_h = row_height / 4.0
		widths.append(row_w)
		heights.append(row_h)
		block_width = maxf(block_width, row_w)
		total_height += row_h
	block_width += margin * 4
	_layout_rows(widths, heights, block_width)
	var result := BlockMetrics.new()
	result.size = Vector2(block_width, total_height)
	result.tail_offset = Vector2(0, total_height)
	result.tail_width = block_width
	var y := 0.0
	for i in _rows.size():
		if _row_skip[i]:
			continue
		if _row_kind[i] == ROW_NEST:
			var slot: StringName = _row_slot[i]
			result.slot_offsets[slot] = Vector2(margin * 4, y)
			result.slot_widths[slot] = maxf(block_width - margin * 4, widths[i])
		y += heights[i]
	metrics = result
	return result


## 按行矩形摆好行控件与背景（只在求解时调用，不做任何"改邻居位置"的事）。
func _layout_rows(widths: Array[float], heights: Array[float], block_width: float) -> void:
	_bg_rects.clear()
	_styles.clear()
	var y := 0.0
	for i in _rows.size():
		var kind := _row_kind[i]
		var row: Control = _rows[i]
		var row_w := widths[i]
		var row_h := heights[i]
		if i < _row_skip.size() and _row_skip[i]:
			row.visible = false
			_row_size[i] = Vector2.ZERO
			continue
		row.visible = true
		if kind == ROW_TAIL:
			row.position = Vector2(margin * 2, y)
			row.size = Vector2(row_w, row_h)
		else:
			row.position = Vector2(margin * 2, y + margin / 2.0)
			row.size = Vector2(block_width - margin * 4, maxf(row_h - margin, 1.0))
		_row_size[i] = Vector2(row_w, row_h)
		_bg_rects.append(Rect2(0, y, block_width, row_h + 1.0))
		_styles.append(_row_style(i))
		y += row_h
	_row_widths = widths.duplicate()
	_row_heights = heights.duplicate()
	var target_size := Vector2(block_width, y)
	if size != target_size:
		size = target_size
	queue_redraw()


## 调色板里由容器排版时用得上；画布上的块位置尺寸由求解器直接给。
func _get_minimum_size() -> Vector2:
	return metrics.size if metrics != null else Vector2(120, row_height)


## 被容器拉伸后重新排一次行，避免背景比控件窄。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _row_widths.is_empty():
		var width := maxf(size.x, metrics.size.x if metrics != null else size.x)
		_layout_rows(_row_widths, _row_heights, width)
## 行背景：nest 行不画（旧实现同样是透明，让子块自己显形），首尾行保留圆角。
func _row_style(index: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color()
	if _row_kind[index] == ROW_NEST:
		style.bg_color = Color(0, 0, 0, 0)
		return style
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	if index == 0:
		style.corner_radius_top_left = corner_radius
	if index == _rows.size() - 1:
		style.corner_radius_bottom_left = corner_radius
	return style


## 命中判定：只认真正画出来的行，nest 留白不算（否则点空白也会拖动整块）。
func _has_point(point: Vector2) -> bool:
	for i in _bg_rects.size():
		if _row_kind[i] == ROW_NEST:
			continue
		if _bg_rects[i].has_point(point):
			return true
	return false

#endregion


#region 可见性与交互

## 重新计算可见性：各 Option 的规则与各 Button 的规则全部取交集。
##
## 旧实现只维护一个 `_current_show`，多个 Option 各带 show 时会互相覆盖；
## 这里每个元素各出一份规则再求交，互不干扰。
func refresh_visibility() -> void:
	_apply_visibility()
	layout_dirty.emit()


## 把 [BlockDef.visibility_from] 算出的规则应用到控件上。
## 值以数据层为准（控件只是显示），这样导出与视图对可见性的判断必然一致。
func _apply_visibility() -> void:
	if def == null:
		return
	var value_of := _value_reader()
	for id in _elements:
		_elements[id].visible = def.is_element_active(def.element(id), value_of)


## 条件求值用的小闭包：取值一律以数据层为准。
func _value_reader() -> Callable:
	return func(field_id: StringName) -> String:
		return String(field_value(field_id, &""))


## 同步单个字段对应的控件显示（数据为准）。正在输入的 LineEdit 不动，避免光标跳位。
func _sync_control(field_id: StringName) -> void:
	if def == null or node == null:
		return
	var element := def.element(field_id)
	if element == null:
		return
	var control: Control = _elements.get(field_id)
	if control == null:
		return
	match element.type:
		&"LineBox":
			if control is LineEdit and not (control as LineEdit).has_focus():
				(control as LineEdit).text = String(field_value(field_id, element.default_value))
		&"Option":
			if control is OptionButton and not element.items.is_empty():
				var current := String(field_value(field_id, ""))
				var index := clampi(element.default_index, 0, element.items.size() - 1)
				if current != "":
					for i in element.items.size():
						if element.items[i].value_or_text() == current:
							index = i
							break
				(control as OptionButton).select(index)
		&"Button":
			set_toggle_state(field_id, String(field_value(field_id, "false")) == "true")
		&"Selector":
			var edit: LineEdit = null
			if control is LineEdit:
				edit = control
			elif control.has_meta(&"value_control"):
				var inner: Variant = control.get_meta(&"value_control")
				if inner is LineEdit:
					edit = inner
			if edit != null and not edit.has_focus():
				edit.text = String(field_value(field_id, element.default_value))


## 由画布把控件状态同步回数据层（撤销/重做后会整体重建，一般不需要）。
func sync_from_data() -> void:
	if def == null or node == null:
		return
	for element in def.elements:
		_sync_control(element.id)
	_apply_visibility()


func _draw() -> void:
	for i in _bg_rects.size():
		draw_style_box(_styles[i], _bg_rects[i])


func _gui_input(event: InputEvent) -> void:
	# 调色板样品（preview）也要能拖出来，因此这里只看 interactive；
	# 拖动幽灵的 interactive 为 false，不会抢输入。
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _has_point(event.position):
			drag_requested.emit(self, event.position)
			accept_event()

#endregion
