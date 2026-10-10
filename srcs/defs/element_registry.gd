class_name ElementRegistry
extends RefCounted

## 元素种类 → 构建器 的注册表。
##
## 构建器是 [ElementBuilder] 的子类（内置实现在 [code]view/elements/element_builders.gd[/code]）：
## 一种元素种类的全部行为都长在它自己身上 —— 建控件、回填、默认值、取值校验。
##
## 因此[b]新增一种元素类型 = 写一个子类 + 注册[/b]：解析、条件校验、默认值灌入、
## 块视图都不用改；引擎外的扩展也可以自己调 register()。

static var _builders: Dictionary[StringName, Variant] = {}
static var _defaults_installed: bool = false

const DEFAULT_INSTALLER: String = "res://srcs/view/elements/element_builders.gd"


static func register(type: StringName, builder: Variant) -> void:
	_builders[type] = builder


static func unregister(type: StringName) -> void:
	_builders.erase(type)


static func has(type: StringName) -> bool:
	ensure_defaults()
	return _builders.has(type)


## 取构建器；未注册返回 null。
static func builder(type: StringName) -> Variant:
	ensure_defaults()
	return _builders.get(type)


## 该元素种类是否承载字段值。
static func is_field(type: StringName) -> bool:
	var builder: Variant = ElementRegistry.builder(type)
	return builder != null and builder.is_field()


## 该元素种类是否是子槽位（<Nest>）。
static func is_slot(type: StringName) -> bool:
	var builder: Variant = ElementRegistry.builder(type)
	return builder != null and builder.is_slot()


## 该元素种类对 [param value] 的合法性检查；返回问题描述（空串 = 合法）。
static func validate_value(element: ElementDef, value: String) -> String:
	var builder: Variant = ElementRegistry.builder(element.type)
	return String(builder.validate_value(element, value)) if builder != null else ""


## 该元素种类在 [param element] 上的初始值；null 表示不预置。
static func default_value(element: ElementDef) -> Variant:
	var builder: Variant = ElementRegistry.builder(element.type)
	return builder.default_value(element) if builder != null else null


static func types() -> Array[StringName]:
	ensure_defaults()
	var out: Array[StringName] = []
	out.assign(_builders.keys())
	return out


## 注册内置元素构建器（懒加载，避免 defs/ 反过来依赖 view/）。
static func ensure_defaults() -> void:
	if _defaults_installed:
		return
	_defaults_installed = true
	if not ResourceLoader.exists(DEFAULT_INSTALLER):
		push_warning("找不到内置元素构建器：%s" % DEFAULT_INSTALLER)
		return
	var installer: Script = load(DEFAULT_INSTALLER)
	if installer == null:
		push_warning("内置元素构建器加载失败：%s" % DEFAULT_INSTALLER)
		return
	installer.call(&"install")
