class_name SelectorData
extends RefCounted

## 选择器候选集（单位 / 传感器 / …）的数据源。
##
## 旧实现把候选写死在两个巨大的 .tscn 里（unit_select_container 58 个按钮、
## sensor_selector 412 个按钮），加一个候选就要改场景文件。现在候选是纯数据：
## `blocks/selectors/*.json`，条目形如 {"value": "@dagger", "icon": "assets/…png"}。

const DIR: String = "res://blocks/selectors"
const UNITS: StringName = &"units"
const SENSORS: StringName = &"sensors"

static var _cache: Dictionary[StringName, Variant] = {}


## 取平铺候选列表：Array[Dictionary]，元素含 value / icon。
static func options(kind: StringName) -> Array:
	var data := _load(kind)
	var out: Array = []
	if data.has("values"):
		out.assign(data["values"])
	elif data.has("groups"):
		for group_name in data["groups"]:
			out.append_array(data["groups"][group_name])
	return out


## 传感器的分组（Item / Liquid / Payload / More）；非分组数据返回空字典。
static func groups(kind: StringName) -> Dictionary:
	var data := _load(kind)
	return data.get("groups", {})


static func exists(kind: StringName) -> bool:
	return not _load(kind).is_empty()


static func clear_cache() -> void:
	_cache.clear()


static func _load(kind: StringName) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var result: Dictionary = {}
	var path := DIR.path_join("%s.json" % String(kind))
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				result = parsed
			else:
				push_warning("选择器数据格式不正确：%s" % path)
	else:
		push_warning("缺少选择器数据：%s" % path)
	_cache[kind] = result
	return result
