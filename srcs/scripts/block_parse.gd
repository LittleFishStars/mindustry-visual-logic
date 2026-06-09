class_name BlockParse
extends RefCounted


const DIR = "res://assets/blocks"


func parse() -> Dictionary:
	var data: Dictionary = {}
	for file in DirAccess.open(DIR).get_files():
		_parse_file(DIR.path_join(file), data)
	return data


func _parse_file(path: String, data: Dictionary):
	var xml = XMLParser.new()
	xml.open(path)

	var current_kind: Dictionary
	var current_block: Dictionary
	var current_option: Dictionary
	var pending_text: Dictionary

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name = xml.get_node_name()
				var attrs = _get_attrs(xml)

				match node_name:
					"Kind":
						var name = attrs.get("name", "")
						var color_hex = attrs.get("color", "#FFFFFF")
						current_kind = {"color": _parse_hex_color(color_hex), "blocks": {}}
						data[name] = current_kind

					"Block":
						var bname = attrs.get("name", "")
						current_block = {"export": attrs.get("export", ""), "elements": []}
						current_kind["blocks"][bname] = current_block

					"Text":
						var el = {"type": "Text", "id": attrs.get("id", ""), "text": ""}
						current_block["elements"].append(el)
						pending_text = el

					"LineBox":
						current_block["elements"].append({
							"type": "LineBox",
							"id": attrs.get("id", ""),
							"placeholder": attrs.get("placeholder", "")
						})

					"Option":
						current_option = {
							"type": "Option",
							"id": attrs.get("id", ""),
							"default": attrs.get("default", "0"),
							"items": []
						}
						current_block["elements"].append(current_option)

					"Item":
						var item = {"text": "", "show": attrs.get("show", "")}
						current_option["items"].append(item)
						pending_text = item

					"Button":
						current_block["elements"].append({
							"type": "Button",
							"id": attrs.get("id", ""),
							"text": attrs.get("text", ""),
							"pressed": {"show": ""},
							"released": {"show": ""}
						})

					"Pressed":
						var last = current_block["elements"][-1]
						if last.get("type") == "Button":
							last["pressed"]["show"] = attrs.get("show", "")

					"Released":
						var last = current_block["elements"][-1]
						if last.get("type") == "Button":
							last["released"]["show"] = attrs.get("show", "")

					"Br":
						current_block["elements"].append({"type": "Br"})

					"Nest":
						current_block["elements"].append({
							"type": "Nest",
							"id": attrs.get("id", "")
						})

			XMLParser.NODE_TEXT:
				if not pending_text.is_empty():
					var text = xml.get_node_data()
					if text != "":
						pending_text["text"] = text

			XMLParser.NODE_ELEMENT_END:
				match xml.get_node_name():
					"Text":
						pending_text = {}
					"Item":
						pending_text = {}
					"Option":
						current_option = {}


func _get_attrs(xml: XMLParser) -> Dictionary:
	var d = {}
	for i in xml.get_attribute_count():
		d[xml.get_attribute_name(i)] = xml.get_attribute_value(i)
	return d


func _parse_hex_color(hex: String) -> Color:
	hex = hex.strip_edges().lstrip("#")
	if hex.length() < 6:
		return Color.WHITE
	return Color(
		hex.substr(0, 2).hex_to_int() / 255.0,
		hex.substr(2, 2).hex_to_int() / 255.0,
		hex.substr(4, 2).hex_to_int() / 255.0
	)
