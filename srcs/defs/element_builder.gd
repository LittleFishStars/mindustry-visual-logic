class_name ElementBuilder
extends RefCounted

## 一种[b]元素种类[/b]的行为契约：怎么建控件、控件怎么被回填、默认值是什么、
## 条件里对该字段的取值合不合法。
##
## 契约放在定义层、实现在视图层（[code]view/elements/element_builders.gd[/code]）：
## 于是「新增一种元素类型 = 写一个子类 + 注册」，解析、条件校验、默认值灌入、
## 块视图都不用动 —— 它们只问注册表，不再各自枚举元素种类。
##
## 子类只覆盖自己关心的回调（默认实现是"什么都不做/不承载字段"）。

## 建控件并接线。[param host] 是块视图，见 [ElementBuilders] 里的宿主接口说明。
func build(_element: ElementDef, _host: Object) -> Control:
	return null


## 该元素是否承载一个字段值（字段清单、默认值灌入都问它）。
func is_field() -> bool:
	return false


## 该元素是否是子槽位（`<Nest>`）。
func is_slot() -> bool:
	return false


## 把数据层的值写回控件 —— 控件只是数据层的显示，唯一真相在 [LogicNode]。
## [param force] 为假时跳过"正在输入"的控件（避免光标跳位）；明确的用户动作（如候选回填）传真。
func apply_value(_element: ElementDef, _control: Control, _value: String, _force: bool = false) -> void:
	pass


## 开关本元素里[b]全部可交互控件[/b]（输入框 / 下拉 / 开关按钮 / 组合控件里的按钮）；
## 拖拽期间由块视图统一禁用，不承载交互的元素什么都不做。
func set_enabled(_element: ElementDef, _control: Control, _enabled: bool) -> void:
	pass


## 校验条件里对该字段的取值；返回问题描述（空串 = 合法）。
func validate_value(_element: ElementDef, _value: String) -> String:
	return ""


## 新块入图时该字段的初始值；返回 null 表示不预置。
func default_value(element: ElementDef) -> Variant:
	return element.default_value if element.default_value != "" else null
