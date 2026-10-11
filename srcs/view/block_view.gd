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

## 请求开始拖动（画布/拖拽控制器接管）：左键按下 = 搬移，右键按下 = 复制一份。
signal drag_requested(view: BlockView, offset: Vector2)
## 请求复制：右键按下时发出，落地时由画布深拷贝这棵子树（原块不动）。
signal copy_requested(view: BlockView, offset: Vector2)
## 某个字段被用户改动（画布负责写进图与撤销栈）。
signal field_committed(node: LogicNode, field_id: StringName, value: Variant, merge_key: StringName)
## 可见性/尺寸变了，需要重新布局。
signal layout_dirty()
## 请求打开选择器（由编辑器标签页提供浮层，避免依赖 Window/Popup）。
signal picker_requested(element: ElementDef, control: Control)
## 请求把某个块引用字段（Jump 的跳转目标）锁定到画布上的某一块 ——
## 块视图看不到图，锁定会话由编辑器标签页里的 [LinkController] 接管。
signal link_requested(view: BlockView, element: ElementDef, control: Control)
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
## 体（nest 行）左侧那条竖条的宽度：子块就挂在这条竖条右边（从 margin * 4 处开始摆）。
@export var body_bar_width: int = 20

var def: BlockDef
var node: LogicNode
## 样品（调色板里的块）或拖拽幽灵：不在图上，改动不写历史。
var preview: bool = false
## 是否接受鼠标（幽灵不接）。
var interactive: bool = true
## 引用字段的显示文本由画布注入（只有它知道图）：`(节点 id, 字段 id) -> 文本`。
var link_labeler: Callable = Callable()
## 是否正被「锁定跳转目标」的高亮描边圈住。
var _link_highlight: bool = false

var metrics: BlockMetrics = null
## 上一次度量传入的槽位尺寸：主题/字体到位后要原样再量一次，不能把 nest 占位的尺寸丢掉。
var _last_slot_extents: Dictionary[StringName, Vector2] = {}
## 本帧是否已经排过一次「主题到位后的补量」。
var _theme_remeasure_queued: bool = false

var _rows: Array[HBoxContainer] = []
var _row_kind: Array[StringName] = []
var _row_slot: Array[StringName] = []
var _row_widths: Array[float] = []
var _row_heights: Array[float] = []
## 每个可视行对应的定义行（nest / tail 行为 null）
var _row_def: Array[BlockDef.RowDef] = []
## 该行本轮是否整行不参与布局（条件不成立）
var _row_skip: Array[bool] = []
var _nest_controls: Dictionary[StringName, Control] = {}
## 建好的输入控件，逐个元素一条：`{"element": ElementDef, "control": Control}`。
##
## [b]同样是按元素记、不是按字段 id 记[/b]：同一个字段可以在不同条件下出现在不同位置
## （`op` 的一元运算要 `result = not a`、二元要 `result = a add b`，两行的控件都写同一个字段）。
## 按 id 存字典的话，重复的那一个会被覆盖 —— 它的可见性再也没人管，会一直显示。
var _element_entries: Array[Dictionary] = []
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


## 给控件套上块内统一的字体（元素构建器用）。
func apply_font(control: Control) -> void:
	control.add_theme_font_override("font", font())


## 给按钮套上块配色（normal / hover / pressed 三态）。
func style_button(button: Button) -> void:
	apply_font(button)
	var base := block_color()
	button.add_theme_stylebox_override("normal", control_style(base))
	button.add_theme_stylebox_override("hover", control_style(base, true))
	button.add_theme_stylebox_override("pressed", control_style(base, false, true))


## 锁定拖拽悬停时的描边色。
const LINK_HIGHLIGHT: Color = Color(1.0, 0.92, 0.45, 0.95)


func block_color() -> Color:
	return color()


func is_preview() -> bool:
	return preview


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


func request_picker(element: ElementDef, control: Control) -> void:
	picker_requested.emit(element, control)


## 引用字段现在指着哪一块（元素构建器用它显示按钮文字）。
func reference_label(field_id: StringName) -> String:
	if node == null:
		return "未锁定"
	if link_labeler.is_valid():
		return String(link_labeler.call(node.id, field_id))
	return "未锁定"


## 引用字段的按钮被按下：请求开始一次「拖拽锁定」。
func request_link(element: ElementDef, control: Control) -> void:
	if preview or not interactive:
		return
	link_requested.emit(self, element, control)


## 世界坐标是否落在这块上（只认真正画出来的行，与点击判定同源）。
func contains_world_point(point: Vector2) -> bool:
	return visible and _has_point(point - position)


## 锁定拖拽悬停时给整块描一圈边（不改配色、也不动 modulate）。
func set_link_highlight(on: bool) -> void:
	if _link_highlight == on:
		return
	_link_highlight = on
	queue_redraw()


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
	_nest_controls.clear()
	_element_entries.clear()
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
				_element_entries.append({"element": cell, "control": control})
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
	return builder.build(element, self)

func _make_row(kind: StringName, slot: StringName, row_def: BlockDef.RowDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	# 行本身不吃鼠标，点空白处应当落到块上以开始拖动
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	_rows.append(row)
	_row_kind.append(kind)
	_row_slot.append(slot)
	_row_def.append(row_def)
	return row


func _make_nest_row(element: ElementDef, row_def: BlockDef.RowDef) -> void:
	# 占位控件由构建器建（元素种类只在一处认识），尺寸由布局求解灌进来
	var placeholder := _build_element(element)
	if placeholder == null:
		return
	var row := _make_row(ROW_NEST, element.id, row_def)
	placeholder.custom_minimum_size = _empty_nest_size()
	row.add_child(placeholder)
	_nest_controls[element.id] = placeholder


## 空巢的占位尺寸：巢里有子链时由 [method measure] 换成子链的真实尺寸。
func _empty_nest_size() -> Vector2:
	return Vector2(separation * 4, row_height / 2.0)

#endregion


#region 度量与摆放

## 算出本块的几何。[param slot_extents] 是各槽位内子链的总尺寸（自底向上求解传入）。
func measure(slot_extents: Dictionary[StringName, Vector2]) -> BlockMetrics:
	_apply_visibility()
	_last_slot_extents = slot_extents.duplicate()
	for slot_id in _nest_controls:
		var placeholder: Control = _nest_controls[slot_id]
		var extent: Vector2 = slot_extents.get(slot_id, Vector2.ZERO)
		if extent == Vector2.ZERO:
			placeholder.custom_minimum_size = _empty_nest_size()
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
			continue
		row.visible = true
		if kind == ROW_TAIL:
			row.position = Vector2(margin * 2, y)
			row.size = Vector2(row_w, row_h)
		else:
			row.position = Vector2(margin * 2, y + margin / 2.0)
			row.size = Vector2(block_width - margin * 4, maxf(row_h - margin, 1.0))
		# 体（nest）行只在最左边画一条竖条 —— 子块挂在它右边，其余地方保持透明
		var bg_width := float(body_bar_width) if kind == ROW_NEST else block_width
		_bg_rects.append(Rect2(0, y, bg_width, row_h + 1.0))
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


## 被容器拉伸后重新排一次行，避免背景比控件窄；主题到位后补量一次（见下）。
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			if not _row_widths.is_empty():
				var width := maxf(size.x, metrics.size.x if metrics != null else size.x)
				_layout_rows(_row_widths, _row_heights, width)
		NOTIFICATION_THEME_CHANGED:
			# 行内控件的最小尺寸要先拿到主题字体才对，而入树与主题传播都发生在 setup 之后：
			# 不补量这一次，背景会停在按兜底字体算出的宽度上，而行内容已经变宽、溢出块外。
			if def != null and not _theme_remeasure_queued:
				_theme_remeasure_queued = true
				_remeasure_after_theme.call_deferred()


## 推迟到本帧主题传播走完之后再量：此刻子控件的最小尺寸可能还是旧字体的。
func _remeasure_after_theme() -> void:
	_theme_remeasure_queued = false
	if def == null or not is_inside_tree():
		return
	var before := metrics.size if metrics != null else Vector2.ZERO
	measure(_last_slot_extents)
	update_minimum_size()
	if metrics.size != before:
		layout_dirty.emit()


## 行背景：体（nest）行的矩形就是左侧那条竖条（见 [method _layout_rows]），首尾行保留圆角。
func _row_style(index: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color()
	if _row_kind[index] == ROW_NEST:
		return style
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	if index == 0:
		style.corner_radius_top_left = corner_radius
	if index == _rows.size() - 1:
		style.corner_radius_bottom_left = corner_radius
	return style


## 命中判定：只认真正画出来的行。体（nest）行的矩形就是左侧那条竖条，
## 所以点竖条能拖动整块，点体里的留白不会。
func _has_point(point: Vector2) -> bool:
	for i in _bg_rects.size():
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
	# 每个控件按[b]它自己那个元素[/b]的条件判可见性：同一个字段的多个控件条件不同，
	# 所以不能拿 `def.element(id)`（只认第一个）去判。
	for entry in _element_entries:
		var element: ElementDef = entry["element"]
		var control: Control = entry["control"]
		if control != null and is_instance_valid(control):
			control.visible = def.is_element_active(element, value_of)


## 条件求值用的小闭包：取值一律以数据层为准。
func _value_reader() -> Callable:
	if node != null:
		return node.value_reader()
	return func(_field_id: StringName) -> String:
		return ""


## 同步单个字段对应的控件显示（数据为准）。正在输入的 LineEdit 不动，避免光标跳位。
func _sync_control(field_id: StringName) -> void:
	if def == null or node == null:
		return
	# 同一个字段的每个控件都要同步（它们可能在不同的行、带不同的元素条件）
	for entry in _element_entries:
		var element: ElementDef = entry["element"]
		var control: Control = entry["control"]
		if element == null or element.id != field_id or control == null or not is_instance_valid(control):
			continue
		var builder: Variant = ElementRegistry.builder(element.type)
		if builder != null:
			builder.apply_value(element, control, String(field_value(field_id, element.default_value)))


## 由画布把控件状态同步回数据层（撤销/重做后会整体重建，一般不需要）。
func sync_from_data() -> void:
	if def == null or node == null:
		return
	for element in def.elements:
		_sync_control(element.id)
	_apply_visibility()


## 拖拽期间统一禁用/恢复本块里所有可交互控件（输入框 / 下拉 / 开关 / 选择器按钮）——
## 拖拽只搬位置，键鼠不该顺手改数据。
## [param enabled] 是"画布允许操作"：preview（调色板样品 / 幽灵）始终保持禁用。
func set_elements_enabled(enabled: bool) -> void:
	if def == null:
		return
	var want := enabled and not preview
	for entry in _element_entries:
		var element: ElementDef = entry["element"]
		var control: Control = entry["control"]
		if element == null or control == null or not is_instance_valid(control):
			continue
		var builder: Variant = ElementRegistry.builder(element.type)
		if builder != null:
			builder.set_enabled(element, control, want)


func _draw() -> void:
	for i in _bg_rects.size():
		draw_style_box(_styles[i], _bg_rects[i])
	if _link_highlight:
		for rect in _bg_rects:
			draw_rect(rect.grow(1.0), LINK_HIGHLIGHT, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	# 调色板样品（preview）也要能拖出来，因此这里只看 interactive；
	# 拖动幽灵的 interactive 为 false，不会抢输入。
	if not interactive:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if not _has_point(event.position):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		drag_requested.emit(self, event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		copy_requested.emit(self, event.position)
		accept_event()

#endregion
