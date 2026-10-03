class_name ActionDef
extends RefCounted

## 块定义里声明的「事件」。
##
## 旧实现完全没有事件概念：任何非声明式的交互（单位选择器、传感器选择器、
## 字段联动）都只能硬编码进核心 GDScript。这里提供两级扩展：
## [br]① 本类 —— 声明式动作，覆盖「字段变了就改另一个字段 / 切显隐」这类常见需求；
## [br]② [member BlockDef.behavior] —— 挂一个脚本，覆盖需要自定义控件或复杂逻辑的场合。
## 两者都不需要改核心代码。

enum Trigger {
	## 任意字段变化。
	FIELD_CHANGED,
	## <Option> 选中项变化。
	OPTION_SELECTED,
	## <Button> 按下状态变化。
	TOGGLED,
	## 块被创建时。
	READY,
}

enum Do {
	## 把另一个字段写成固定值。
	SET_FIELD,
	## 切换一组元素的可见性（追加白名单）。
	SET_VISIBLE,
	## 调用行为脚本上的约定方法。
	CALL_BEHAVIOR,
}

var trigger: Trigger = Trigger.FIELD_CHANGED
## 触发源字段 id（为空表示不限字段）。
var field: StringName = &""
var do: Do = Do.SET_FIELD
## SET_FIELD 的目标字段 / CALL_BEHAVIOR 的方法名。
var target: StringName = &""
## SET_FIELD 的目标值。
var value: Variant = ""
## SET_VISIBLE 的目标元素 id。
var ids: Array[StringName] = []


## 该动作是否由 [param changed_field] 的变化触发。
func matches(changed_field: StringName) -> bool:
	return field == &"" or field == changed_field


static func trigger_from(token: String) -> Trigger:
	match token:
		"option_selected":
			return Trigger.OPTION_SELECTED
		"toggled":
			return Trigger.TOGGLED
		"ready":
			return Trigger.READY
		_:
			return Trigger.FIELD_CHANGED


const TRIGGER_NAMES: Array[String] = ["field_changed", "option_selected", "toggled", "ready"]
const DO_NAMES: Array[String] = ["set_field", "set_visible", "call_behavior"]


func describe() -> String:
	var when := TRIGGER_NAMES[trigger]
	var what := DO_NAMES[do]
	return "%s(%s) → %s %s" % [when, String(field), what, String(target)]
