class_name ElementBuilders
extends RefCounted

## 内置元素构建器 + 注册。
##
## 每个构建器是 [ElementBuilder] 的子类，只覆盖自己关心的回调：
## [codeblock]
## func build(element: ElementDef, host: Object) -> Control   # 建控件并接线
## func is_field() -> bool                                    # 是否承载字段值
## func is_slot() -> bool                                     # 是否是子槽位（<Nest>）
## func apply_value(element, control, value)                  # 数据层 → 控件（回填）
## func validate_value(element, value) -> String              # when 里的取值是否合法
## func default_value(element) -> Variant                     # 新块的初始值（null = 不预置）
## func set_enabled(element, control, enabled)               # 元素内的可交互控件能否用（拖拽期间禁用）
## [/codeblock]
## host 是 [BlockView]，它提供 font() / apply_font() / style_button() / field_value() /
## commit_field() / refresh_visibility() / flush_history_group() / request_picker() 等回调
## （见 BlockView 的「元素构建器需要的宿主接口」一节）。
##
## [b]新增一种元素类型[/b]：在这里加一个子类并在 [method install] 里注册即可 ——
## 解析、条件校验、默认值灌入、块视图都不用改。

static func install() -> void:
	ElementRegistry.register(&"Text", TextBuilder.new())
	ElementRegistry.register(&"LineBox", InputBuilder.new())
	ElementRegistry.register(&"Option", OptionBuilder.new())
	ElementRegistry.register(&"Button", ToggleBuilder.new())
	ElementRegistry.register(&"Selector", SelectorBuilder.new())
	ElementRegistry.register(&"Nest", NestBuilder.new())
	ElementRegistry.register(&"JumpTarget", JumpTargetBuilder.new())


## 输入框（含 Selector 里那个文本框）的建造与回填：两个构建器共用这一份。
static func make_edit(element: ElementDef, host: Object, min_width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = element.placeholder
	edit.text = String(host.field_value(element.id, element.default_value))
	edit.custom_minimum_size = Vector2(min_width, 0)
	host.apply_font(edit)
	if host.is_preview():
		edit.editable = false
		edit.focus_mode = Control.FOCUS_NONE
	else:
		edit.text_changed.connect(func(text: String) -> void:
			host.commit_field(element.id, text, true))
		edit.focus_exited.connect(func() -> void:
			host.flush_history_group())
	return edit


## 回填输入框：正在输入的控件不动，避免光标跳位。
static func apply_edit_value(control: Control, value: String, force: bool = false) -> void:
	var edit := resolve_edit(control)
	if edit == null:
		return
	# 默认不打断正在输入的控件（避免光标跳位）；picker 回填这类明确动作传 force = true
	if force or not edit.has_focus():
		edit.text = value


## 组合控件（Selector）里真正存值的那个输入框。
static func resolve_edit(control: Control) -> LineEdit:
	if control is LineEdit:
		return control
	if control != null and control.has_meta(&"value_control"):
		var inner: Variant = control.get_meta(&"value_control")
		if inner is LineEdit:
			return inner
	return null


## 开关一个元素控件：输入框改成只读并交出焦点，控件自身与其中的按钮置为 disabled。
## 用 disabled（而不是 mouse_filter）是为了连键盘也不响应；实测它不会重置开关的按下状态，
## 也不会发出 toggled/item_selected —— 所以拖拽期间不会顺手改数据。
static func set_control_enabled(control: Control, enabled: bool) -> void:
	var edit := resolve_edit(control)
	if edit != null:
		edit.editable = enabled
		edit.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		if not enabled and edit.has_focus():
			edit.release_focus()
	_set_buttons_disabled(control, not enabled)


static func _set_buttons_disabled(node: Node, disabled: bool) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = disabled
	for child in node.get_children():
		_set_buttons_disabled(child, disabled)


## 静态文本：不吃鼠标，保证从标签上按下也能拖动整块。
class TextBuilder extends ElementBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var label := Label.new()
		label.text = element.text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.apply_font(label)
		return label


## 文本输入框。连续输入会按 merge_key 合并成一条撤销记录。
class InputBuilder extends ElementBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		return ElementBuilders.make_edit(element, host, 64.0)

	func is_field() -> bool:
		return true

	func apply_value(_element: ElementDef, control: Control, value: String, force: bool = false) -> void:
		ElementBuilders.apply_edit_value(control, value, force)

	func set_enabled(_element: ElementDef, control: Control, enabled: bool) -> void:
		ElementBuilders.set_control_enabled(control, enabled)


## 下拉选项：显示文本与导出值可以不同（<Item value="33">!</Item>）。
class OptionBuilder extends ElementBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var option := OptionButton.new()
		for item in element.items:
			option.add_item(item.text)
		host.style_button(option)
		apply_value(element, option, String(host.field_value(element.id, "")))
		if host.is_preview():
			option.disabled = true
		else:
			option.item_selected.connect(func(selected: int) -> void:
				if selected < element.items.size():
					host.commit_field(element.id, element.items[selected].value_or_text(), false)
				host.refresh_visibility())
		return option

	func is_field() -> bool:
		return true

	func apply_value(element: ElementDef, control: Control, value: String, _force: bool = false) -> void:
		if control is OptionButton and not element.items.is_empty():
			(control as OptionButton).select(index_of(element, value))

	func set_enabled(_element: ElementDef, control: Control, enabled: bool) -> void:
		ElementBuilders.set_control_enabled(control, enabled)

	func validate_value(element: ElementDef, value: String) -> String:
		if element.items.is_empty():
			return ""
		var legal := PackedStringArray()
		for item in element.items:
			legal.append(item.value_or_text())
		if legal.has(value):
			return ""
		return "字段 %s 没有取值 `%s`（合法值：%s）" % [element.id, value, ", ".join(legal)]

	func default_value(element: ElementDef) -> Variant:
		if element.items.is_empty():
			return null
		return element.items[index_of(element, "")].value_or_text()

	## 导出值 → 候选项下标；认不出来时回落到 default（建控件与回填共用这一份）。
	func index_of(element: ElementDef, value: String) -> int:
		var fallback := clampi(element.default_index, 0, maxi(element.items.size() - 1, 0))
		if value == "":
			return fallback
		for i in element.items.size():
			if element.items[i].value_or_text() == value:
				return i
		return fallback


## 开关按钮：按下/松开各有一套可见性规则，导出模板也可以按状态切换。
class ToggleBuilder extends ElementBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var button := Button.new()
		button.text = element.text
		button.toggle_mode = true
		host.style_button(button)
		apply_value(element, button, String(host.field_value(element.id, "false")))
		if host.is_preview():
			button.disabled = true
		else:
			button.toggled.connect(func(pressed: bool) -> void:
				host.commit_field(element.id, "true" if pressed else "false", false)
				host.refresh_visibility())
		return button

	func is_field() -> bool:
		return true

	func apply_value(_element: ElementDef, control: Control, value: String, _force: bool = false) -> void:
		if control is BaseButton:
			(control as BaseButton).set_pressed_no_signal(value == "true")

	func set_enabled(_element: ElementDef, control: Control, enabled: bool) -> void:
		ElementBuilders.set_control_enabled(control, enabled)

	func validate_value(element: ElementDef, value: String) -> String:
		if value == "true" or value == "false":
			return ""
		return "开关 %s 只能与 true / false 比较（实际 `%s`）" % [element.id, value]

	func default_value(element: ElementDef) -> Variant:
		return element.default_value if element.default_value != "" else "false"


## 选择器：文本框 + 弹出候选（单位 / 传感器 …）。
## 候选取自 blocks/selectors/*.json，浮层由编辑器标签页提供（不依赖 Window）。
class SelectorBuilder extends ElementBuilder:
	func build(element: ElementDef, host: Object) -> Control:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var edit := ElementBuilders.make_edit(element, host, 72.0)
		box.add_child(edit)
		box.set_meta(&"value_control", edit)
		var pick := Button.new()
		pick.text = "▾"
		pick.custom_minimum_size = Vector2(26, 0)
		host.style_button(pick)
		box.add_child(pick)
		if host.is_preview():
			pick.disabled = true
		else:
			pick.pressed.connect(func() -> void:
				host.request_picker(element, box))
		return box

	func is_field() -> bool:
		return true

	func apply_value(_element: ElementDef, control: Control, value: String, force: bool = false) -> void:
		ElementBuilders.apply_edit_value(control, value, force)

	func set_enabled(_element: ElementDef, control: Control, enabled: bool) -> void:
		ElementBuilders.set_control_enabled(control, enabled)


## 子槽位：本类只建一个占位控件（槽里的块是画布的直接子级）；占位尺寸由布局求解灌进来。
class NestBuilder extends ElementBuilder:
	func build(_element: ElementDef, _host: Object) -> Control:
		var placeholder := Control.new()
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return placeholder

	func is_slot() -> bool:
		return true


## 块引用（Jump 的跳转目标）：不是文本框，而是一个「锁定到了哪一块」的按钮。
##
## 在按钮上按下并拖到画布上的某一块松手 = 把跳转锁定到那块（见 [LinkController]）；
## 拖到自己或左侧块列表 = 解除锁定。字段里存的是块引用（`#<节点 id>`），
## 具体是谁由画布告诉它（[method BlockView.reference_label]）—— 元素自己看不到图。
class JumpTargetBuilder extends ElementBuilder:
	const MIN_WIDTH: float = 84.0

	func build(element: ElementDef, host: Object) -> Control:
		var button := Button.new()
		button.custom_minimum_size = Vector2(MIN_WIDTH, 0)
		host.style_button(button)
		# apply_value 拿不到宿主，把宿主挂在控件上（与 Selector 的 value_control 同一手法）
		button.set_meta(&"link_host", host)
		apply_value(element, button, String(host.field_value(element.id, "")))
		if host.is_preview():
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
		else:
			button.button_down.connect(func() -> void:
				host.request_link(element, button))
		return button

	func is_field() -> bool:
		return true

	func apply_value(element: ElementDef, control: Control, value: String, _force: bool = false) -> void:
		if not (control is Button):
			return
		var host: Object = control.get_meta(&"link_host", null)
		var label := "未锁定"
		if host != null:
			label = String(host.reference_label(element.id))
		(control as Button).text = label

	func set_enabled(_element: ElementDef, control: Control, enabled: bool) -> void:
		ElementBuilders.set_control_enabled(control, enabled)
