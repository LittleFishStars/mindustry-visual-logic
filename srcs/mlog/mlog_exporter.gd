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
	var context := _make_context(graph, library, warnings)
	_pre_export(graph, library, context)
	var lines := PackedStringArray()
	for chain_id in graph.chain_ids():
		_emit_chain(graph, library, graph.slot_items(LogicGraph.ROOT, chain_id), lines, warnings, context)
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


## 只导出某一个块（含其子树），用于块级预览/单独复制。
static func export_node(graph: LogicGraph, library: BlockLibrary, id: int, warnings: Array[String] = []) -> String:
	var context := _make_context(graph, library, warnings)
	_pre_export_chain(graph, library, [id] as Array[int], context)
	var lines := PackedStringArray()
	_emit_node(graph, library, id, lines, warnings, context)
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


## 渲染单行 mlog（不含换行；行为脚本可以返回含 \n 的多行）。模板为空时返回空串。
##
## 块可以挂行为脚本接管这一行：脚本实现 [code]export_line(node, def, render, context)[/code]，
## 返回字符串就覆盖模板；返回 null（或非字符串）表示"用模板"。
## [param render] 是可调用的模板渲染器，所以脚本既能完全自己拼一行，
## 也能只对模板结果做后处理（[code]render.call() + " always"[/code]）。
static func render_node(def: BlockDef, node: LogicNode, context: Dictionary = {}) -> String:
	var value_of := _reader_of(node)
	var render_template := func() -> String:
		return _render_template(def, node, value_of)
	if def.behavior != null and def.behavior.has_method(&"export_line"):
		var custom: Variant = def.behavior.call(&"export_line", node, def, render_template, context)
		if custom is String:
			return String(custom)
	return render_template.call()


## 按块定义里的模板渲染（默认路径）。
static func _render_template(def: BlockDef, node: LogicNode, value_of: Callable) -> String:
	var parts := def.export_parts_for(value_of)
	if parts.is_empty():
		return ""
	var out := ""
	for part in parts:
		var text := _render_part(def, node, part, value_of)
		if text == "":
			continue
		# 模板字符串解析出来的段落 space_before 一律为 false（空格已写进字面量）；
		# 旧的分段写法则靠 space_before 决定要不要补空格
		if part.space_before and out != "":
			out += " "
		out += text
	return out


## 导出上下文：行为脚本可以在"导出前的准备"里往 [code]scratch[/code] 放整图级别的信息
## （例如给 If 分配跳转标签），渲染每一行时再读出来。
static func _make_context(graph: LogicGraph, library: BlockLibrary, warnings: Array[String]) -> Dictionary:
	return {"graph": graph, "library": library, "warnings": warnings, "scratch": {}}


## 导出前的整图准备：按遍历顺序给每个块一次机会（可选钩子 [code]pre_export(node, context)[/code]）。
static func _pre_export(graph: LogicGraph, library: BlockLibrary, context: Dictionary) -> void:
	for chain_id in graph.chain_ids():
		_pre_export_chain(graph, library, graph.slot_items(LogicGraph.ROOT, chain_id), context)


static func _pre_export_chain(
	graph: LogicGraph,
	library: BlockLibrary,
	ids: Array[int],
	context: Dictionary
) -> void:
	for id in ids:
		var node := graph.get_node_by_id(id)
		if node == null:
			continue
		var def := library.by_id(node.type_id)
		if def == null:
			continue
		if def.behavior != null and def.behavior.has_method(&"pre_export"):
			def.behavior.call(&"pre_export", node, context)
		for slot_id in def.slot_ids():
			_pre_export_chain(graph, library, graph.slot_items(id, slot_id), context)


static func _emit_chain(
	graph: LogicGraph,
	library: BlockLibrary,
	ids: Array[int],
	lines: PackedStringArray,
	warnings: Array[String],
	context: Dictionary
) -> void:
	for id in ids:
		_emit_node(graph, library, id, lines, warnings, context)


static func _emit_node(
	graph: LogicGraph,
	library: BlockLibrary,
	id: int,
	lines: PackedStringArray,
	warnings: Array[String],
	context: Dictionary
) -> void:
	var node := graph.get_node_by_id(id)
	if node == null:
		return
	var def := library.by_id(node.type_id)
	if def == null:
		warnings.append("未知块类型：%s" % node.type_id)
		return
	var line := render_node(def, node, context)
	if line != "":
		lines.append(line)
	for slot_id in def.slot_ids():
		_emit_chain(graph, library, graph.slot_items(id, slot_id), lines, warnings, context)


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


## 从数据层取值的小闭包（条件求值用）。
static func _reader_of(node: LogicNode) -> Callable:
	return func(field_id: StringName) -> String:
		return String(node.get_field(field_id, ""))
