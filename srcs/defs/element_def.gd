class_name ElementDef
extends RefCounted

## 一个块定义里的元素（对应 XML 里的一个子标签）。
##
## 「什么时候生效」不再靠"每个选项罗列一遍可见元素 id"，而是元素自己带一个
## [ConditionDef] —— 条件正着存在它影响的东西上，于是不必重复、不会漏、
## 也表达得了"多个字段共同决定"（`find=building & group=enemy`）。
##
## 元素的[b]种类[/b]由 [ElementRegistry] 决定"怎么建控件、怎么读值"，
## 所以新增一种元素类型只需要写一个构建器并注册它 —— 解析器与块视图都不用改。

class OptionItem extends RefCounted:
	## 选项显示文本。
	var text: String = ""
	## 导出进 mlog 的值。为空时等于 [member text]。
	var value: String = ""
	## 解析期：旧格式 `<Item show="…">` 列出的元素 id。
	## 解析结束后会被翻译成那些元素的条件，然后清空。
	var legacy_show: Array[StringName] = []

	func _init(p_text: String = "") -> void:
		text = p_text

	func set_text(p_text: String) -> void:
		text = p_text

	func value_or_text() -> String:
		return value if value != "" else text


## 元素种类（XML 标签名，或注册表里自定义的种类名）。
var type: StringName = &""

## 元素 id：既是可见性引用的名字，也是导出时取值的字段名。
var id: StringName = &""

## 静态文本（`<Text>` 的文本；`<Button>` 的按钮文字）。
var text: String = ""

## 输入框占位文本（`<LineBox placeholder>`）。
var placeholder: String = ""

## `<Option>` 的候选项。
var items: Array[OptionItem] = []

## `<Option default>` 的默认下标。
var default_index: int = 0

## 字段默认值：新块入图时写进节点，避免"没输入就导出 0"丢掉旧版默认行为。
## 未显式声明 default 时用 [member placeholder]（旧版就是把默认值写在输入框里的）。
var default_value: String = ""

## 生效条件（`when="…"`）；null 表示恒真。
var condition: ConditionDef = null

## `<Selector kind="units|sensors">` 的候选集名字。
var selector_kind: StringName = &""

## 原始属性兜底：新元素类型可以自带属性，解析器不必认识它们。
var attrs: Dictionary = {}

var actions: Array[ActionDef] = []

## 解析期：旧格式 `<Pressed show="…">` / `<Released show="…">`（仅 Button 有意义）。
var legacy_pressed: Array[StringName] = []
var legacy_released: Array[StringName] = []


func _init(p_type: StringName = &"", p_id: StringName = &"") -> void:
	type = p_type
	id = p_id


## 这个元素是否承载一个"字段值"（导出时会读写它）。
func is_field() -> bool:
	return type in [&"LineBox", &"Option", &"Button", &"Selector"]


func attr(key: String, fallback: Variant = "") -> Variant:
	return attrs.get(key, fallback)


## 解析器用它写入标签文本（ElementDef / OptionItem / ExportPart 约定同名方法）。
func set_text(value: String) -> void:
	text = value


## 单看元素自身的条件是否成立（不含所在行的条件）。
func is_active_here(value_of: Callable) -> bool:
	return condition == null or condition.matches(value_of)


## 清掉解析期的旧格式残留（翻译完成后调用）。
func clear_legacy() -> void:
	legacy_pressed = []
	legacy_released = []
	for item in items:
		item.legacy_show = []
