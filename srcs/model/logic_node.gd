class_name LogicNode
extends RefCounted

## 逻辑块实例的纯数据表示：只有「是什么块 / 字段值 / 子槽位顺序」。
##
## 坐标、控件与场景树都不在这里 —— 画布坐标属于 [LogicGraph] 的根位置，
## 具体位置由视图层的布局求解算出（见 view/layout_solver.gd）。

## 稳定 id，由 [LogicGraph] 分配，撤销/重做与存读档后保持不变。
var id: int = 0

## 指向块定义（对应 XML 的 <Block name="..."/>）。
var type_id: StringName = &""

## 字段值：字段 id → 值（字符串 / 数值 / 布尔）。
var fields: Dictionary[StringName, Variant] = {}

## 子槽位：槽位 id → 子节点 id 的有序数组（对应 XML 的 <Nest id="..."/>）。
## 槽位不存在与槽位为空是同一件事，不要用空数组当"占位"。
var slots: Dictionary[StringName, Array] = {}


func _init(p_id: int = 0, p_type_id: StringName = &"") -> void:
	id = p_id
	type_id = p_type_id


## 读字段值；未设置时返回 [param fallback]。
func get_field(field_id: StringName, fallback: Variant = "") -> Variant:
	return fields.get(field_id, fallback)


## 条件求值 / 导出取值用的小闭包：字段 id → 当前值的字符串形式（数据层为准）。
func value_reader() -> Callable:
	return func(field_id: StringName) -> String:
		return String(get_field(field_id, ""))


## 直接写字段（值为 null 表示删除该字段）。
## 需要进撤销栈时请走 [method LogicGraph.set_field]。
func put_field(field_id: StringName, value: Variant) -> void:
	if value == null:
		fields.erase(field_id)
	else:
		fields[field_id] = value


## 批量写字段（新块入图时灌默认值用）。
func apply_fields(values: Dictionary) -> void:
	for field_id in values:
		put_field(field_id, values[field_id])


## 取子槽位的 id 数组副本；槽位不存在时返回空数组，且不会建立槽位。
func peek_slot(slot_id: StringName) -> Array[int]:
	var out: Array[int] = []
	out.assign(slots.get(slot_id, []))
	return out


## 取子槽位的 id 数组本体，槽位不存在时按需建立。视图层只读，不要改写。
func slot(slot_id: StringName) -> Array[int]:
	if not slots.has(slot_id):
		var empty: Array[int] = []
		slots[slot_id] = empty
	return slots[slot_id]


func to_dict() -> Dictionary:
	var fields_out: Dictionary = {}
	for key in fields:
		fields_out[String(key)] = fields[key]
	var slots_out: Dictionary = {}
	for key in slots:
		var ids_out: Array = []
		ids_out.assign(peek_slot(key))
		slots_out[String(key)] = ids_out
	return {
		"id": id,
		"type": String(type_id),
		"fields": fields_out,
		"slots": slots_out,
	}


static func from_dict(data: Dictionary) -> LogicNode:
	var node := LogicNode.new(int(data.get("id", 0)), StringName(data.get("type", "")))
	var raw_fields: Dictionary = data.get("fields", {})
	for key in raw_fields:
		node.fields[StringName(key)] = raw_fields[key]
	var raw_slots: Dictionary = data.get("slots", {})
	for key in raw_slots:
		var ids: Array[int] = []
		ids.assign(raw_slots[key])
		node.slots[StringName(key)] = ids
	return node
