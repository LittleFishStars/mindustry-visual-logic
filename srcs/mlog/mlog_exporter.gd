class_name MlogExporter
extends RefCounted

## 逻辑图 → mlog 文本（纯函数：只读图与块库，不碰控件）。遍历按链顺序深度优先：块自己一行，再是各槽位内容，最后下一个兄弟。
## 块引用是「第几行」，行号得排完整段才知道 —— 第一趟 [_walk] 排行号表，第二趟渲染时用同一份 walk 把引用换成行号（表与输出必然对得上）。

## 导出整张图。[param warnings] 收集无法处理的块与失效的跳转目标。
static func export(graph: LogicGraph, library: BlockLibrary, warnings: Array[String] = []) -> String:
	if graph == null or library == null:
		return ""
	var walk := _walk(graph, library, warnings)
	var table := _table_of(walk)
	var lines := PackedStringArray()
	for entry in walk:
		var def: BlockDef = entry["def"]
		var node: LogicNode = entry["node"]
		var line := render_node(def, node, _resolver(node, table, warnings))
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


## 行号表：`{line_of, fallback, count}`，顺序与 [method export] 的输出一致。
static func line_table(graph: LogicGraph, library: BlockLibrary) -> Dictionary:
	var discarded: Array[String] = []
	return _table_of(_walk(graph, library, discarded))


## 这张图会输出多少行（追加导入时算行号偏移用）。
static func line_count(graph: LogicGraph, library: BlockLibrary) -> int:
	return int(line_table(graph, library).get("count", 0))


static func render_node(def: BlockDef, node: LogicNode, resolver: Callable = Callable()) -> String:
	var value_of := node.value_reader()
	var parts := def.export_parts_for(value_of)
	if parts.is_empty():
		return ""
	var out := ""
	for part in parts:
		var text := _render_part(def, node, part, value_of, resolver)
		if text == "":
			continue
		if part.space_before and out != "":
			out += " "
		out += text
	return out


## 遍历顺序表。不输出行的块也在表里（不占行号，但跳转落到它之后的第一条指令）；导出只走入口块那条链、从它开始。
static func _walk(graph: LogicGraph, library: BlockLibrary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry := _entry_node(graph, library)
	if entry == null:
		for chain_id in graph.chain_ids():
			_walk_chain(graph, library, graph.slot_items(LogicGraph.ROOT, chain_id), out, warnings)
		return out
	var where := graph.locate(entry.id)
	if where.is_empty():
		return out
	var siblings := graph.slot_items(int(where["owner_id"]), StringName(where["slot"]))
	var tail: Array[int] = []
	tail.assign(siblings.slice(int(where["index"])))
	_walk_chain(graph, library, tail, out, warnings)
	return out


static func _entry_node(graph: LogicGraph, library: BlockLibrary) -> LogicNode:
	if library == null:
		return null
	var def := library.entry_def()
	if def == null:
		return null
	for id in graph.all_ids():
		var node := graph.get_node_by_id(id)
		if node != null and node.type_id == def.id:
			return node
	return null


static func _walk_chain(
	graph: LogicGraph,
	library: BlockLibrary,
	ids: Array[int],
	out: Array[Dictionary],
	warnings: Array[String]
) -> void:
	for id in ids:
		var node := graph.get_node_by_id(id)
		if node == null:
			continue
		var def := library.by_id(node.type_id)
		if def == null:
			warnings.append("未知块类型：%s" % node.type_id)
			continue
		out.append({"node": node, "def": def})
		for slot_id in def.slot_ids():
			_walk_chain(graph, library, graph.slot_items(id, slot_id), out, warnings)


## 排行号：[b]数的是指令而不是文本行[/b] —— 注释行与标签行不占行号，只记 fallback。
static func _table_of(walk: Array[Dictionary]) -> Dictionary:
	var line_of: Dictionary = {}
	var fallback: Dictionary = {}
	var count := 0
	for entry in walk:
		var def: BlockDef = entry["def"]
		var node: LogicNode = entry["node"]
		fallback[node.id] = count
		if _is_instruction(render_node(def, node)):
			line_of[node.id] = count
			count += 1
	return {"line_of": line_of, "fallback": fallback, "count": count}


## 这一行会不会成为一条指令（判定与导入侧同一套规则）。
static func _is_instruction(text: String) -> bool:
	if text == "" or text.begins_with("#"):
		return false
	return not (text.ends_with(":") and not text.contains(" "))


## 引用字段 → 行号；未锁定或目标已失效都按 -1 导出并记一条警告。
static func _resolver(node: LogicNode, table: Dictionary, warnings: Array[String]) -> Callable:
	var line_of: Dictionary = table["line_of"]
	var fallback: Dictionary = table["fallback"]
	return func(field_id: StringName) -> String:
		var target := LogicGraph.parse_link_ref(node.get_field(field_id, ""))
		if target <= 0:
			warnings.append("Jump 没有锁定跳转目标（按 -1 导出）")
			return "-1"
		if line_of.has(target):
			return str(line_of[target])
		if fallback.has(target):
			return str(fallback[target])
		warnings.append("Jump 的跳转目标已失效（按 -1 导出）")
		return "-1"


static func _render_part(
	def: BlockDef,
	node: LogicNode,
	part: ExportPart,
	value_of: Callable,
	resolver: Callable
) -> String:
	match part.kind:
		ExportPart.Kind.LITERAL:
			return part.literal
		ExportPart.Kind.FIELD:
			var text := _field_text(def, node, part.field, resolver, part.allow_empty)
			# 字符串字段：引号在这里加并转义 —— 否则用户打一个引号就会把整行写坏
			return _quoted(text) if part.as_string else text
		_:
			for field_id in part.fields:
				if def.is_field_active(field_id, value_of):
					return _field_text(def, node, field_id, resolver)
			return "0"


## 取字段的 mlog 文本：块引用换成行号，其余按原值；[param allow_empty] 时空值不补 0。
static func _field_text(def: BlockDef, node: LogicNode, field_id: StringName, resolver: Callable,
		allow_empty: bool = false) -> String:
	if def.is_reference_field(field_id) and resolver.is_valid():
		return String(resolver.call(field_id))
	var value := String(node.get_field(field_id, ""))
	if value != "" or allow_empty:
		return value
	return "0"


static func _quoted(text: String) -> String:
	return "\"" + MlogText.escape(text) + "\""
