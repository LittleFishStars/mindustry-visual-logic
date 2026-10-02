class_name ElementRegistry
extends RefCounted

## 元素种类 → 构建器 的注册表。
##
## 构建器是视图层的对象（见 srcs/view/elements/），契约是两个方法：
## [codeblock]
## func build(element: ElementDef, host: Object) -> Control     # 建控件并接线
## func read_value(element: ElementDef, control: Control) -> String  # 导出时取值
## [/codeblock]
## host 是块视图，提供 commit_field / refresh_visibility / invalidate_layout 等回调。
##
## 因此[b]新增一种元素类型 = 写一个构建器 + 注册[/b]，解析器（本目录）与块视图
## 都不需要改动；引擎外的扩展也可以自己调 register()。

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
