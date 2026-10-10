class_name MlogExporter
extends RefCounted

## 逻辑图 → mlog 文本。
##
## 纯函数：只读 [LogicGraph] 与 [BlockLibrary]，不碰任何控件 —— 旧的 `_export()` 长在
## 块节点上、只能把可见性等信息从控件里挖出来，导出结果依赖"控件当前长什么样"。
##
## 遍历顺序：按链顺序深度优先 —— 块自己那一行先输出，再输出它各槽位里的内容，
## 然后才是下一个兄弟。Mindustry 的 mlog 没有块级作用域，嵌套在这里就是顺序展开。
##
## [b]块引用要两趟才导得出[/b]：Jump 的目标是"第几行"，而行号得把整段输出排完才知道。
## 第一趟走 [method _walk] 排出行号表（见 [method line_table]），第二趟用同一个 walk 渲染，
## 把引用字段换成目标块的行号 —— 两趟同源，表与输出必然对得上。
## 导入侧靠同一张表把行号绑回块引用（见 [method MlogImporter.bind_links]）。

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


## 行号表：`{line_of: 节点 id → 行号, fallback: 节点 id → 它之后的第一行, count: 总行数}`。
## 顺序与 [method export] 的输出完全一致，导入侧用它把 mlog 的绝对行号绑回节点。
static func line_table(graph: LogicGraph, library: BlockLibrary) -> Dictionary:
	var discarded: Array[String] = []
	return _table_of(_walk(graph, library, discarded))


## 这张图会输出多少行（追加导入时算行号偏移用）。
static func line_count(graph: LogicGraph, library: BlockLibrary) -> int:
	return int(line_table(graph, library).get("count", 0))


## 渲染单行 mlog（不含换行）。模板为空（如 If 这类纯容器）时返回空串。
## [param resolver] 用来把块引用字段换成行号；不传时引用字段按原值输出。
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


## 遍历顺序表的一项：`{"node": LogicNode, "def": BlockDef}`。
## [b]不输出行的块也在表里[/b]：它虽然不占行号，但当跳转目标时要落到"它之后的第一条指令"。
## 从[b]入口块[/b]（XML `entry="true"`，目前是 Start）开始往下走：它所在的那条链、
## 从它自己开始（它渲染成空行、不占行号，但当跳转目标要有个落点），
## 它前头的块与其他链[b]都不导出[/b] —— 「只导出从 Start 开始的」就是这个意思。
## 入口块被删掉的老存档仍旧按老规矩：所有链都导出。
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
	# 手抄一份带类型的尾巴（Array.slice() 回来的是无类型数组，直接传会类型不符）
	var tail: Array[int] = []
	for i in range(int(where["index"]), siblings.size()):
		tail.append(siblings[i])
	_walk_chain(graph, library, tail, out, warnings)
	return out


## 图里的入口块节点（没有就返回 null）。
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


## 排行号。
##
## [b]数的是指令而不是文本行[/b]：Mindustry 的汇编器会把注释行（`#…`）与标签行（`label:`）
## 直接跳过，它们不占指令下标 —— 所以这两类块只记 fallback（= 它之后的第一条指令）。
static func _table_of(walk: Array[Dictionary]) -> Dictionary:
	var line_of: Dictionary = {}
	var fallback: Dictionary = {}
	var count := 0
	for entry in walk:
		var def: BlockDef = entry["def"]
		var node: LogicNode = entry["node"]
		fallback[node.id] = count
		# 这里不带 resolver：只判「这行会不会成为一条指令」，与取值无关
		if _is_instruction(render_node(def, node)):
			line_of[node.id] = count
			count += 1
	return {"line_of": line_of, "fallback": fallback, "count": count}


## 这一行在汇编器里会不会成为一条指令（即占不占 jump 数的行号）。
## 注释与标签行的判定与导入侧同一套规则，保证「导出→导入」对得上。
static func _is_instruction(text: String) -> bool:
	if text == "" or text.begins_with("#"):
		return false
	return not (text.ends_with(":") and not text.contains(" "))


## 引用字段 → 行号。未锁定或已失效都按 -1 导出（与旧实现一致），并记一条警告。
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
			return _field_text(def, node, part.field, resolver)
		_:
			# 旧语法 %a|b：取第一个此刻生效的候选；都不生效时输出 0
			for field_id in part.fields:
				if def.is_field_active(field_id, value_of):
					return _field_text(def, node, field_id, resolver)
			return "0"


## 取字段的 mlog 文本：块引用先换成行号，其余按原值（空值补 0）。
static func _field_text(def: BlockDef, node: LogicNode, field_id: StringName, resolver: Callable) -> String:
	if def.is_reference_field(field_id) and resolver.is_valid():
		return String(resolver.call(field_id))
	var value := String(node.get_field(field_id, ""))
	return value if value != "" else "0"
