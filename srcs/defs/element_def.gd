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
	## 旧名字（`<Item alias="atan2">`）：导入时认它，但存回去的是一支规范值。
	## 游戏自己的解析器就带这么一张改名表（`LParser.opNameChanges`），
	## 不跟着认的话，旧代码导进来会在下拉里显示成另一个选项（字段值与显示不符）。
	var alias: String = ""
	func _init(p_text: String = "") -> void:
		text = p_text

	func set_text(p_text: String) -> void:
		text = p_text

	func value_or_text() -> String:
		return value if value != "" else text

	## 这个取值是不是本项（规范值或旧名字）。
	func accepts(candidate: String) -> bool:
		return candidate == value_or_text() or (alias != "" and candidate == alias)


## 元素种类（XML 标签名，或注册表里自定义的种类名）。
##
## [b]选项字段[/b]（`<Option>`）顺便提供「取值合法吗 / 旧名字叫什么」两件事：
## 导入时用它挑候选块 —— 多个块的模板结构可能一模一样（`ucontrol` 的十几个变体就是），
## 只有「选项取值是否合法」能把它们分开。
func option_values() -> PackedStringArray:
	var out := PackedStringArray()
	for item in items:
		out.append(item.value_or_text())
	return out


## 规范值：合法值返回自身，旧名字返回它现在的值，都认不出返回 ""。
func canonical_value(candidate: String) -> String:
	for item in items:
		if item.value_or_text() == candidate:
			return candidate
	for item in items:
		if item.alias != "" and item.alias == candidate:
			return item.value_or_text()
	return ""


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


func _init(p_type: StringName = &"", p_id: StringName = &"") -> void:
	type = p_type
	id = p_id


## 这个元素是否承载一个"字段值"（由注册表里的构建器自报，本层不枚举元素种类）。
func is_field() -> bool:
	return ElementRegistry.is_field(type)


## 这个元素是否是子槽位（<Nest>）：槽位里可以挂子块。
func is_slot() -> bool:
	return ElementRegistry.is_slot(type)


func set_text(value: String) -> void:
	text = value


## 单看元素自身的条件是否成立（不含所在行的条件）。
func is_active_here(value_of: Callable) -> bool:
	return condition == null or condition.matches(value_of)
