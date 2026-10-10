class_name BlockDef
extends RefCounted

## 一种逻辑块的定义（对应 XML 里的一个 `<Block>`）。
##
## 布局的存储方式：**行是显式的**（[RowDef]），条件（[ConditionDef]）挂在行与元素上。
## 旧格式的 `<Item show="一串元素 id">` 与 `<Pressed>/<Released>` 在解析时被
## 翻译成同样的条件，所以内部只有一种机制 —— 不会出现"哪种写法优先"的问题。

## 一种「导出模板 + 生效条件」的组合。
## 旧写法 `<Pressed>/<Released>` 会带上 button/pressed 提示，供 mlog 反向导入回填开关状态。
class ExportVariant extends RefCounted:
	var condition: ConditionDef = null
	var parts: Array[ExportPart] = []
	var button: StringName = &""
	var pressed: bool = false

	## 条件是否恰好形如 `开关=true/false`：是的话顺带记下按钮与状态。
	func derive_button_from_condition() -> void:
		if condition == null or condition.kind != ConditionDef.Kind.COMPARE:
			return
		if condition.values.size() != 1 or condition.negated:
			return
		var value := condition.values[0]
		if value != "true" and value != "false":
			return
		button = condition.field
		pressed = value == "true"


## 一行：一个条件 + 若干单元格。
class RowDef extends RefCounted:
	var condition: ConditionDef = null
	var cells: Array[ElementDef] = []

	func is_active(value_of: Callable) -> bool:
		return condition == null or condition.matches(value_of)


var id: StringName = &""
var kind: StringName = &""
var color: Color = Color.WHITE

## 扁平的全部元素（按出现顺序）—— 导出与字段查询用它。
var elements: Array[ElementDef] = []
## 行的分组与行级条件 —— 布局用它。
var rows: Array[RowDef] = []

var export_parts: Array[ExportPart] = []
## 条件化的导出模板：第一个条件成立的优先，都不成立时用 [member export_parts]。
var export_variants: Array[ExportVariant] = []
## 解析期收集的条件（整块解析完再统一校验字段与取值）
var pending_conditions: Array[Dictionary] = []
## 在所属类别里的顺序（保持 XML 中的书写顺序）。
var order: int = 0

var _by_id: Dictionary[StringName, ElementDef] = {}
var _row_of: Dictionary[StringName, RowDef] = {}
var _slots: Array[StringName] = []
var _fields: Array[StringName] = []
var _indexed: bool = false


func _init(p_id: StringName = &"", p_kind: StringName = &"") -> void:
	id = p_id
	kind = p_kind


## 建立 id 索引。解析结束后调用一次；手工构造 BlockDef 时也要调。
func build_index() -> void:
	_by_id.clear()
	_row_of.clear()
	_slots.clear()
	_fields.clear()
	for row in rows:
		for cell in row.cells:
			_row_of[cell.id] = row
	for element in elements:
		if element.id == &"":
			continue
		if not _by_id.has(element.id):
			_by_id[element.id] = element
		# 「承载字段值 / 是子槽位」由构建器自报，本层不枚举元素种类
		if element.is_slot():
			if not _slots.has(element.id):
				_slots.append(element.id)
		elif element.is_field():
			if not _fields.has(element.id):
				_fields.append(element.id)
	_indexed = true


func element(element_id: StringName) -> ElementDef:
	if not _indexed:
		build_index()
	return _by_id.get(element_id)


## 本块声明的子槽位 id（`<Nest>`），顺序与定义一致。
func slot_ids() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _slots.duplicate()


## 本块可承载字段值的元素 id，顺序与定义一致。
func field_ids() -> Array[StringName]:
	if not _indexed:
		build_index()
	return _fields.duplicate()


func row_of(element_id: StringName) -> RowDef:
	if not _indexed:
		build_index()
	return _row_of.get(element_id)


## 行条件与元素条件都成立，这个元素才生效。
func is_element_active(element: ElementDef, value_of: Callable) -> bool:
	if element == null:
		return false
	var row := row_of(element.id)
	if row != null and not row.is_active(value_of):
		return false
	return element.is_active_here(value_of)


func is_field_active(field_id: StringName, value_of: Callable) -> bool:
	return is_element_active(element(field_id), value_of)


func export_parts_for(value_of: Callable) -> Array[ExportPart]:
	for variant in export_variants:
		if variant.condition == null or variant.condition.matches(value_of):
			return variant.parts
	return export_parts


## 新块入图时应当预置的字段值（字段 id → 值）。
##
## 旧版把默认值写在输入框里，所以 `wait` 拖出来就是 0.5 秒、`ubind` 就是某个单位；
## 没有默认值的话会导出 `wait 0` 之类的错误指令。
func default_field_values() -> Dictionary:
	var out: Dictionary = {}
	for element in elements:
		if not element.is_field():
			continue
		# 每种元素的默认值规则长在它自己的构建器上
		var value: Variant = ElementRegistry.default_value(element)
		if value != null:
			out[element.id] = value
	return out
