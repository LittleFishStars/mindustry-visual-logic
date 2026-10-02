class_name ElementBuilders
extends RefCounted

## 内置元素构建器 + 注册。
##
## 每个构建器只需两个方法：
## [codeblock]
## func build(element: ElementDef, host: Object) -> Control
## func read_value(element: ElementDef, control: Control) -> String
## [/codeblock]
## host 是 [BlockView]，它提供 font() / control_style() / field_value() / commit_field()
## 等回调（见 BlockView 的「元素构建器需要的宿主接口」一节）。
##
## [b]新增一种元素类型[/b]：在这里加一个内部类并在 [method install] 里注册即可，
## 解析器（srcs/defs/）与 BlockView 都不用改 —— 这就是「给每个块加事件/加控件不再麻烦」的落点。


static func install() -> void:
	ElementRegistry.register(&"Text", TextBuilder.new())
	ElementRegistry.register(&"LineBox", InputBuilder.new())
	ElementRegistry.register(&"Option", OptionBuilder.new())
	ElementRegistry.register(&"Button", ToggleBuilder.new())
	ElementRegistry.register(&"Selector", SelectorBuilder.new())
	ElementRegistry.register(&"Nest", NestBuilder.new())
	ElementRegistry.register(&"Br", RowBreakBuilder.new())


## 静态文本：不吃鼠标，保证从标签上按下也能拖动整块。
class TextBuilder extends RefCounted:
	func build(element: ElementDef, host: Object) -> Control:
		var label := Label.new()
		label.text = element.text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", host.font())
		return label

	func read_value(_element: ElementDef, _control: Control) -> String:
		return ""


## 文本输入框。连续输入会按 merge_key 合并成一条撤销记录。
class InputBuilder extends RefCounted:
	func build(element: ElementDef, host: Object) -> Control:
		var edit := LineEdit.new()
		edit.placeholder_text = element.placeholder
		edit.text = String(host.field_value(element.id, element.default_value))
		edit.add_theme_font_override("font", host.font())
		edit.custom_minimum_size = Vector2(64, 0)
		if host.is_preview():
			edit.editable = false
			edit.focus_mode = Control.FOCUS_NONE
		else:
			edit.text_changed.connect(func(text: String) -> void:
				host.commit_field(element.id, text, true))
			edit.focus_exited.connect(func() -> void:
				host.flush_history_group())
		return edit

	func read_value(_element: ElementDef, control: Control) -> String:
		return (control as LineEdit).text if control is LineEdit else ""


## 下拉选项：显示文本与导出值可以不同（<Item value="33">!</Item>）。
class OptionBuilder extends RefCounted:
	func build(element: ElementDef, host: Object) -> Control:
		var option := OptionButton.new()
		var index := 0
		var current := String(host.field_value(element.id, ""))
		for i in element.items.size():
			option.add_item(element.items[i].text)
			if element.items[i].value_or_text() == current:
				index = i
		if current == "" and not element.items.is_empty():
			index = clampi(element.default_index, 0, element.items.size() - 1)
		option.selected = index
		option.add_theme_font_override("font", host.font())
		_apply_style(option, host)
		if host.is_preview():
			option.disabled = true
		else:
			option.item_selected.connect(func(selected: int) -> void:
				if selected < element.items.size():
					host.commit_field(element.id, element.items[selected].value_or_text(), false)
				host.refresh_visibility())
		return option

	func read_value(element: ElementDef, control: Control) -> String:
		if control is OptionButton and not element.items.is_empty():
			var option := control as OptionButton
			return element.items[clampi(option.selected, 0, element.items.size() - 1)].value_or_text()
		return ""

	func _apply_style(option: OptionButton, host: Object) -> void:
		var base: Color = host.block_color()
		option.add_theme_stylebox_override("normal", host.control_style(base))
		option.add_theme_stylebox_override("hover", host.control_style(base, true))
		option.add_theme_stylebox_override("pressed", host.control_style(base, false, true))


## 开关按钮：按下/松开各有一套可见性规则，导出模板也可以按状态切换。
class ToggleBuilder extends RefCounted:
	func build(element: ElementDef, host: Object) -> Control:
		var button := Button.new()
		button.text = element.text
		button.toggle_mode = true
		button.add_theme_font_override("font", host.font())
		var base: Color = host.block_color()
		button.add_theme_stylebox_override("normal", host.control_style(base))
		button.add_theme_stylebox_override("hover", host.control_style(base, true))
		button.add_theme_stylebox_override("pressed", host.control_style(base, false, true))
		if host.is_preview():
			button.disabled = true
		else:
			button.toggled.connect(func(pressed: bool) -> void:
				host.commit_field(element.id, "true" if pressed else "false", false)
				host.refresh_visibility())
		return button

	func read_value(_element: ElementDef, control: Control) -> String:
		if control is BaseButton:
			return "true" if (control as BaseButton).button_pressed else "false"
		return "false"


## 选择器：文本框 + 弹出候选（单位 / 传感器 …）。
## 候选取自 blocks/selectors/*.json，浮层由编辑器标签页提供（不依赖 Window）。
class SelectorBuilder extends RefCounted:
	func build(element: ElementDef, host: Object) -> Control:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var edit := LineEdit.new()
		edit.placeholder_text = element.placeholder
		edit.text = String(host.field_value(element.id, element.default_value))
		edit.add_theme_font_override("font", host.font())
		edit.custom_minimum_size = Vector2(72, 0)
		box.add_child(edit)
		box.set_meta(&"value_control", edit)
		var pick := Button.new()
		pick.text = "▾"
		pick.custom_minimum_size = Vector2(26, 0)
		pick.add_theme_font_override("font", host.font())
		pick.add_theme_stylebox_override("normal", host.control_style(host.block_color()))
		pick.add_theme_stylebox_override("hover", host.control_style(host.block_color(), true))
		pick.add_theme_stylebox_override("pressed", host.control_style(host.block_color(), false, true))
		box.add_child(pick)
		if host.is_preview():
			edit.editable = false
			edit.focus_mode = Control.FOCUS_NONE
			pick.disabled = true
		else:
			edit.text_changed.connect(func(text: String) -> void:
				host.commit_field(element.id, text, true))
			edit.focus_exited.connect(func() -> void:
				host.flush_history_group())
			pick.pressed.connect(func() -> void:
				host.request_picker(element, box))
		return box

	func read_value(_element: ElementDef, control: Control) -> String:
		if control == null:
			return ""
		var edit: Variant = control if control is LineEdit else control.get_meta(&"value_control", null)
		return (edit as LineEdit).text if edit is LineEdit else ""


## 子槽位占位：尺寸由布局求解灌进来，槽内的块是画布的直接子级（不在本节点里）。
class NestBuilder extends RefCounted:
	func build(_element: ElementDef, _host: Object) -> Control:
		var placeholder := Control.new()
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return placeholder

	func read_value(_element: ElementDef, _control: Control) -> String:
		return ""


## 换行标记：本身不产生控件（行结构由 BlockView 处理）。
class RowBreakBuilder extends RefCounted:
	func build(_element: ElementDef, _host: Object) -> Control:
		return null

	func read_value(_element: ElementDef, _control: Control) -> String:
		return ""
