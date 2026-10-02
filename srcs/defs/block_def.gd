class_name BlockDef
extends RefCounted

## 一种逻辑块的定义（对应 XML 里的一个 <Block>）。
##
## 旧实现把块定义散在两处：`block_parse.gd` 解析成裸 Dictionary，`block.gd` 再按
## 字符串键去取；任何扩展都要同时改这两个文件。现在解析结果是有类型、可自检的
## 对象，视图与导出都只依赖本类。

## 一种「开关状态 → 导出模板」的变体。
## 旧版 Print/Format 靠它分别输出 `print "x"` 与 `print x`。
class ExportVariant extends RefCounted:
	var button: StringName = &""
	var pressed: bool = false
	var parts: Array[ExportPart] = []


var id: StringName = &""
var kind: StringName = &""
var color: Color = Color.WHITE
var elements: Array[ElementDef] = []
var export_parts: Array[ExportPart] = []
## 导出模板的可选变体：某个 <Button> 处于某状态时改用它。
var export_variants: Array[ExportVariant] = []
var actions: Array[ActionDef] = []
## 行为脚本路径（可选），用于旧实现里只能硬编码的自定义交互。
var behavior_path: String = ""
var behavior: Script = null
## 在所属类别里的顺序（保持 XML 中的书写顺序）。
var order: int = 0

var _by_id: Dictionary[StringName, ElementDef] = {}
var _slots: Array[StringName] = []
var _fields: Array[StringName] = []
var _indexed: bool = false


func _init(p_id: StringName = &"", p_kind: StringName = &"") -> void:
	id = p_id
	kind = p_kind


## 建立 id 索引。解析结束后调用一次；手工构造 BlockDef 时也要调。
func build_index() -> void:
	_by_id.clear()
	_slots.clear()
	_fields.clear()
	for element in elements:
		if element.id != &"" and not _by_id.has(element.id):
			_by_id[element.id] = element
		match element.type:
			&"Nest":
				if element.id != &"" and not _slots.has(element.id):
					_slots.append(element.id)
			&"LineBox", &"Option", &"Button", &"Selector":
				if element.id != &"" and not _fields.has(element.id):
					_fields.append(element.id)
	_indexed = true


func element(element_id: StringName) -> ElementDef:
	if not _indexed:
		build_index()
	return _by_id.get(element_id)


## 本块声明的子槽位 id（<Nest>），顺序与定义一致。
func slot_ids() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _slots.duplicate()


## 本块可承载字段值的元素 id，顺序与定义一致。
func field_ids() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _fields.duplicate()


func has_slot(slot_id: StringName) -> bool:
	if not _indexed:
		build_index()
	return _slots.has(slot_id)


## 该块会不会产生 mlog 输出（If 这类纯容器不会）。
func produces_output() -> bool:
	return not export_parts.is_empty() or not export_variants.is_empty()


## 按当前开关状态选导出模板：第一个命中的变体优先，否则用默认模板。
func export_parts_for(button_states: Dictionary) -> Array[ExportPart]:
	for variant in export_variants:
		if bool(button_states.get(variant.button, false)) == variant.pressed:
			return variant.parts
	return export_parts


## 按字段值算出可见性规则：各 Option 项的规则与各 Button 各态的规则全部取交集。
## 视图与导出共用这一份实现（旧实现只在视图里算，而且只维护一个 _current_show）。
## [param value_of] 接收元素 id、返回其值字符串。
func visibility_from(value_of: Callable) -> ElementDef.Visibility:
	var rule: ElementDef.Visibility = null
	for element in elements:
		var element_rule: ElementDef.Visibility = null
		match element.type:
			&"Option":
				if not element.items.is_empty():
					var current := String(value_of.call(element.id))
					var index := clampi(element.default_index, 0, element.items.size() - 1)
					if current != "":
						for i in element.items.size():
							if element.items[i].value_or_text() == current:
								index = i
								break
					element_rule = element.items[index].visible
			&"Button":
				var pressed := String(value_of.call(element.id)) == "true"
				element_rule = element.visibility_for(&"pressed" if pressed else &"released")
			_:
				element_rule = element.visible
		if element_rule == null or element_rule.is_unrestricted():
			continue
		rule = element_rule if rule == null else rule.intersect(element_rule)
	return rule


## 触发源为 [param changed_field] 的声明式动作。
func actions_for(changed_field: StringName) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for action in actions:
		if action.matches(changed_field):
			out.append(action)
	return out


## 新块入图时应当预置的字段值（字段 id → 值）。
##
## 旧版把默认值写在输入框里，所以 `wait` 拖出来就是 0.5 秒、`ubind` 就是某个单位；
## 当前 XML 只有 placeholder，不预置的话会导出 `wait 0` 之类的错误指令。
func default_field_values() -> Dictionary:
	var out: Dictionary = {}
	for element in elements:
		if not element.is_field():
			continue
		match element.type:
			&"Option":
				var index := clampi(element.default_index, 0, maxi(element.items.size() - 1, 0))
				if not element.items.is_empty():
					out[element.id] = element.items[index].value_or_text()
			&"Button":
				out[element.id] = element.default_value if element.default_value != "" else "false"
			_:
				if element.default_value != "":
					out[element.id] = element.default_value
	return out
