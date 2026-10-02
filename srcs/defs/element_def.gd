class_name ElementDef
extends RefCounted

## 一个块定义里的元素（对应 XML 里的一个子标签）。
##
## 元素的[b]种类[/b]由 [ElementRegistry] 决定"怎么建控件、怎么读值"，
## 所以新增一种元素类型只需要：写一个构建器并注册它 —— 不必改解析器，
## 也不必改块视图。这是旧实现"加一种元素要同时改 block_parse.gd 与 block.gd"的解法。

## 一条可见性规则：白名单 ∩ 非黑名单。
##
## 旧实现只有一个空格分隔的 id 白名单，于是"除了这几个之外都显示"根本没法表达
## （只能把所有其它 id 全列一遍，新增元素就会漏）。黑名单用 `!id` 书写。
class Visibility extends RefCounted:
	var visible_ids: Array[StringName] = []
	var hidden_ids: Array[StringName] = []

	func is_unrestricted() -> bool:
		return visible_ids.is_empty() and hidden_ids.is_empty()

	func allows(id: StringName) -> bool:
		if hidden_ids.has(id):
			return false
		return visible_ids.is_empty() or visible_ids.has(id)

	## 与另一条规则取交集（用于 Option 的 show ∩ Button 的 show）。
	func intersect(other: Visibility) -> Visibility:
		if other == null or other.is_unrestricted():
			return self
		if is_unrestricted():
			return other
		var out := Visibility.new()
		for id in visible_ids:
			if other.visible_ids.has(id):
				out.visible_ids.append(id)
		out.hidden_ids = hidden_ids.duplicate()
		for id in other.hidden_ids:
			if not out.hidden_ids.has(id):
				out.hidden_ids.append(id)
		return out

	func _to_string() -> String:
		var parts: PackedStringArray = []
		for id in visible_ids:
			parts.append(String(id))
		for id in hidden_ids:
			parts.append("!" + String(id))
		return " ".join(parts)


class OptionItem extends RefCounted:
	## 选项显示文本。
	var text: String = ""
	## 导出进 mlog 的值。为空时等于 [member text]。
	##
	## 旧版是「显示 + 导出 add」，当前 XML 做不到 —— 而 PrintChar 需要显示字符、导出字符码。
	var value: String = ""
	## 该选项被选中时哪些元素可见。
	var visible: Visibility = null

	func _init(p_text: String = "", p_visible: Visibility = null) -> void:
		text = p_text
		visible = p_visible if p_visible != null else Visibility.new()

	func set_text(p_text: String) -> void:
		text = p_text


	func value_or_text() -> String:
		return value if value != "" else text


## 元素种类（XML 标签名，或注册表里自定义的种类名）。
var type: StringName = &""

## 元素 id：既是可见性引用的名字，也是导出时取值的字段名。
var id: StringName = &""

## 静态文本（<Text> 的文本；<Button> 的按钮文字）。
var text: String = ""

## 输入框占位文本（<LineBox placeholder>）。
var placeholder: String = ""

## <Option> 的候选项。
var items: Array[OptionItem] = []

## <Option default> 的默认下标。
var default_index: int = 0

## 字段默认值：新块入图时写进节点，避免“没输入就导出 0”丢掉旧版默认行为。
## 未显式声明 default 时用 [member placeholder]（旧版就是把默认值写在输入框里的）。
var default_value: String = ""

## <Option> 的 Item 选中时可见的规则（<Button> 则为 Released 态）。
var visible: Visibility = null

## <Button> 的 Pressed 态可见规则。
var pressed_visible: Visibility = null

## <Selector kind="units|sensors"> 的候选集名字。
var selector_kind: StringName = &""

## 原始属性兜底：新元素类型可以自带属性，解析器不必认识它们。
var attrs: Dictionary = {}

var actions: Array[ActionDef] = []


func _init(p_type: StringName = &"", p_id: StringName = &"") -> void:
	type = p_type
	id = p_id
	visible = Visibility.new()
	pressed_visible = Visibility.new()


## 这个元素是否承载一个"字段值"（导出时会读写它）。
func is_field() -> bool:
	return type in [&"LineBox", &"Option", &"Button", &"Selector"]


## 解析器用它写入标签文本（ElementDef / OptionItem / ExportPart 三者约定同名方法）。
func set_text(value: String) -> void:
	text = value


func attr(key: String, fallback: Variant = "") -> Variant:
	return attrs.get(key, fallback)


## 该元素在某状态下可见的规则。
func visibility_for(state: StringName = &"released") -> Visibility:
	if type == &"Button" and state == &"pressed":
		return pressed_visible
	return visible
