class_name MlogExporter
extends RefCounted

## 逻辑图 → mlog 文本。
##
## 纯函数：只读 [LogicGraph] 与 [BlockLibrary]，不碰任何控件 —— 旧的 `_export()` 长在
## 块节点上、只能把可见性等信息从控件里挖出来，导出结果依赖"控件当前长什么样"。
##
## 遍历顺序：按链顺序深度优先 —— 块自己那一行先输出，再输出它各槽位里的内容，
## 然后才是下一个兄弟。Mindustry 的 mlog 没有块级作用域，嵌套在这里就是顺序展开。

## 导出整张图。[param warnings] 收集无法处理的块（未知类型等）。
static func export(graph: LogicGraph, library: BlockLibrary, warnings: Array[String] = []) -> String:
	if graph == null or library == null:
		return ""
	var lines := PackedStringArray()
	for chain_id in graph.chain_ids():
		_emit_chain(graph, library, graph.slot_items(LogicGraph.ROOT, chain_id), lines, warnings)
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


## 渲染单行 mlog（不含换行）。模板为空（如 If 这类纯容器）时返回空串。
static func render_node(def: BlockDef, node: LogicNode) -> String:
	var value_of := node.value_reader()
	var parts := def.export_parts_for(value_of)
	if parts.is_empty():
		return ""
	var out := ""
	for part in parts:
		var text := _render_part(def, node, part, value_of)
		if text == "":
			continue
		if part.space_before and out != "":
			out += " "
		out += text
	return out


static func _emit_chain(
	graph: LogicGraph,
	library: BlockLibrary,
	ids: Array[int],
	lines: PackedStringArray,
	warnings: Array[String]
) -> void:
	for id in ids:
		_emit_node(graph, library, id, lines, warnings)


static func _emit_node(
	graph: LogicGraph,
	library: BlockLibrary,
	id: int,
	lines: PackedStringArray,
	warnings: Array[String]
) -> void:
	var node := graph.get_node_by_id(id)
	if node == null:
		return
	var def := library.by_id(node.type_id)
	if def == null:
		warnings.append("未知块类型：%s" % node.type_id)
		return
	var line := render_node(def, node)
	if line != "":
		lines.append(line)
	for slot_id in def.slot_ids():
		_emit_chain(graph, library, graph.slot_items(id, slot_id), lines, warnings)


static func _render_part(
	def: BlockDef,
	node: LogicNode,
	part: ExportPart,
	value_of: Callable
) -> String:
	match part.kind:
		ExportPart.Kind.LITERAL:
			return part.literal
		ExportPart.Kind.FIELD:
			return _value_of(node, part.field)
		_:
			# 旧语法 %a|b：取第一个此刻生效的候选；都不生效时输出 0
			for field_id in part.fields:
				if def.is_field_active(field_id, value_of):
					return _value_of(node, field_id)
			return "0"


static func _value_of(node: LogicNode, field_id: StringName) -> String:
	var value := String(node.get_field(field_id, ""))
	return value if value != "" else "0"
