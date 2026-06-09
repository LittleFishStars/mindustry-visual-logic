class_name BlockData
extends RefCounted


var SORTS       = [tr("any"),tr("enemy"),tr("ally"),tr("player"),tr("attacker"),tr("flying"),tr("boss"),tr("ground")]
var COMPS       = [tr("=="),tr("not"),tr("<"),tr("<="),tr(">"),tr(">="),tr("==="),tr("always")]
var RADAR_KEYS  = [tr("distance"),tr("health"),tr("shield"),tr("armor"),tr("maxHealth")]
var OPS         = [tr("+"),tr("-"),tr("*"),tr("/"),tr("//"),tr("%"),tr("^"),tr("=="),tr("!="),tr("&&"),tr("<"),
				   tr("<="),tr(">"),tr(">="),tr("==="),tr("<<"),tr(">>"),tr(">>>"),tr("or"),tr("b-and"),tr("xor"),
				   tr("flip"),tr("max"),tr("min"),tr("angle"),tr("angle-diff"),tr("len"),tr("noise"),tr("abs"),
				   tr("sign"),tr("log"),tr("logn"),tr("log10"),tr("floor"),tr("ceil"),tr("round"),tr("sqrt"),
				   tr("rand"),tr("sin"),tr("cos"),tr("tan"),tr("asin"),tr("acos"),tr("atan")]
var DRAW_MODES  = [tr("clear"),tr("color"),tr("col"),tr("stroke"),tr("line"),tr("rect"),tr("lineRect"),
				   tr("polfoundy"),tr("linePoly"),tr("triangle"),tr("image"),tr("print"),tr("translate"),
				   tr("scale"),tr("rotate"),tr("reset")]
var   ASCII:      = (" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
					 "[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~").split()


const COLORS: Dictionary = {
	"Controls":   Color(0.63,  0.347, 0),
	"Logics":     Color(0.257, 0.6,   0.66),
	"Operations": Color(0.391, 0.301, 0.64),
	"PutInOut":   Color(0.6,   0.555, 0.432),
	"Units":      Color(0.72,  0.637, 0.41),
}


static func _stub() -> void: pass


var BLOCKS: Dictionary[String, Dictionary] = {
	"Controls": {
		"Drawflush": {
			template = tr("Drawflush to %in.display"),
			options  = { display = { placeholder = "display1" } },
			export   = _stub,
		},
		"Printflush": {
			template = tr("Printflush to %in.message"),
			options  = { message = { placeholder = "message1" } },
			export   = _stub,
		},
		"GetLink": {
			template = tr("GetLink %in.result = link# %in.link"),
			options  = { result = { placeholder = "result" }, 
						 link   = { placeholder = "0" } },
			export   = _stub,
		},
		"Control": {
			template = tr("Control %op.mode of %in.block to %in.index"),
			variants = {
				"mode": {
					tr("enabled"): tr("Control %op.mode of %in.block to %in.index"),
					tr("shoot"):   tr("Control %op.mode of %in.block x %in.x y %in.y shoot %in.shoot"),
					tr("shootp"):  tr("Control %op.mode of %in.block unit %in.unit shoot %in.shoot"),
					tr("config"):  tr("Control %op.mode of %in.block to %in.index"),
					tr("color"):   tr("Control %op.mode of %in.block to %in.index"),
				}
			},
			options  = { mode  = { items = [tr("enabled"), tr("shoot"), tr("shootp"), tr("config"), tr("color")] },
						 block = { placeholder = "block1" },
						 x     = { placeholder = "0" },
						 y     = { placeholder = "0" },
						 shoot = { placeholder = "0" },
						 unit  = { placeholder = "0" },
						 index = { placeholder = "0" } },
			export   = _stub,
		},
		"Radar": {
			template = tr("Radar from %in.turret %op.s1 %op.s2 %op.s3\norder %in.num sort %op.radar %in.result"),
			options  = { turret = { placeholder = "turret1" }, 
						 s1     = { items = SORTS },
						 s2     = { items = SORTS },
						 s3     = { items = SORTS },
						 num    = { placeholder = "1" },
						 radar  = { items = RADAR_KEYS },
						 result = { placeholder = "result" } },
			export   = _stub,
		},
		"Sensor": {
			template = tr("Sensor %in.result = %in.all in %in.block"),
			options  = { result = { placeholder = "result" },
						 block  = { placeholder = "block1" } },
			export   = _stub,
		},
	},
	"Logics": {
		"Wait": {
			template = tr("Wait %in.time sec"),
			options  = { time = { placeholder = "0.5" } },
			export   = _stub,
		},
		"Stop": {
			template = tr("Stop"),
			options  = {},
			export   = _stub,
		},
		"End": {
			template = tr("End"),
			options  = {},
			export   = _stub,
		},
		"Jump": {
			template = tr("Jump %in.target if %in.value1 %op.cmp %in.value2"),
			options  = { target = { placeholder = "0" },
						 value1 = { placeholder = "x" },
						 cmp    = { items = COMPS },
						 value2 = { placeholder = "false" } },
			export   = _stub,
		},
		"JumpLabel": {
			template = tr("Label %in.label"),
			options  = { label = { placeholder = "label1" } },
			export   = _stub,
		},
		"Expression": {
			template = tr("Expression %in.text"),
			options  = { value1 = { placeholder = "" } },
			export   = _stub,
		},
		"If": {
			template = tr("If %in.a %op.cmp %in.b\n%li"),
			options  = { a   = { placeholder = "a" },
						 cmp = { items = COMPS },
						 b   = { placeholder = "b" } },
			export   = _stub,
		},
	},
	"Operations": {
		"Set": {
			template = tr("Set %in.result = %in.value"),
			options  = { result = { placeholder = "result" },
						 value  = { placeholder = "0" } },
			export   = _stub,
		},
		"Operation": {
			template = tr("Operation %in.result = %in.a %op.ops %in.b"),
			options  = { result = { placeholder = "result" },
						 a   = { placeholder = "a" },
						 ops = { items = OPS },
						 b   = { placeholder = "b" } },
			export   = _stub,
		},
		"Select": {
			template = tr("Select %in.result = if %in.x %op.cmp %in.value\nthen %in.t else %in.f"),
			options  = { result = { placeholder = "result" },
						 cmp   = { items = COMPS }, 
						 value = { placeholder = "false" }, 
						 t     = { placeholder = "false" }, 
						 f     = { placeholder = "false" } },
			export   = _stub,
		},
		"Lookup": {
			template = tr("Lookup %in.result = lookup %op.type # %in.id"),
			options  = { result = { placeholder = "result" },
						 type   = { items = [tr("block"),tr("unit"),tr("item"),tr("liquid"),tr("team")] }, 
						 id     = { placeholder = "0" } },
			export   = _stub,
		},
		"PackColor": {
			template = tr("Pack Color %in.result = pack %in.r %in.g %in.b %in.a"),
			options  = { result = { placeholder = "result" },
						 r      = { placeholder = "1" }, 
						 g      = { placeholder = "0" }, 
						 b      = { placeholder = "0" }, 
						 a      = { placeholder = "1" } },
			export   = _stub,
		},
		"UnpackColor": {
			template = tr("Unpack Color %in.r %in.g %in.b %in.a = unpack %in.result"),
			options  = { r      = { placeholder = "r" }, 
						 g      = { placeholder = "g" }, 
						 b      = { placeholder = "b" }, 
						 a      = { placeholder = "a" },
						 result = { placeholder = "result" } },
			export   = _stub,
		},
	},
	"PutInOut": {
		"Read": {
			template = tr("Read %in.result = %in.cell at %in.idx"),
			options  = { result = { placeholder = "result" },
						 cell   = { placeholder = "cell1" }, 
						 idx    = { placeholder = "0" } },
			export   = _stub,
		},
		"Write": {
			template = tr("Write %in.result = %in.cell at %in.idx"),
			options  = { result = { placeholder = "result" },
						 cell   = { placeholder = "cell1" }, 
						 idx    = { placeholder = "0" } },
			export   = _stub,
		},
		"Draw": {
			template = tr("Draw %op.mode r %in.r g %in.g b %in.b"),
			variants = {
				"mode": {
					tr("clear"):      tr("Draw %op.mode r %in.r g %in.g b %in.b"),
					tr("color"):      tr("Draw %op.mode r %in.r g %in.g b %in.b a %in.a"),
					tr("col"):        tr("Draw %op.mode %in.color"),
					tr("stroke"):     tr("Draw %op.mode %in.width"),
					tr("line"):       tr("Draw %op.mode x1 %in.x1 y1 %in.y1 x2 %in.x2 y2 %in.y2"),
					tr("rect"):       tr("Draw %op.mode x %in.x y %in.y width %in.width height %in.height"),
					tr("lineRect"):   tr("Draw %op.mode x %in.x y %in.y width %in.width height %in.height"),
					tr("poly"):       tr("Draw %op.mode x %in.x y %in.y sides %in.sides radius %in.radius rotation %in.rot"),
					tr("linePoly"):   tr("Draw %op.mode x %in.x y %in.y sides %in.sides radius %in.radius rotation %in.rot"),
					tr("triangle"):   tr("Draw %op.mode x1 %in.x1 y1 %in.y1 x2 %in.x2 y2 %in.y2 x3 %in.x3 y3 %in.y3"),
					tr("image"):      tr("Draw %op.mode x %in.x y %in.y image %in.image size %in.size rotation %in.rot"),
					tr("print"):      tr("Draw %op.mode"),
					tr("translate"):  tr("Draw %op.mode x %in.x y %in.y"),
					tr("scale"):      tr("Draw %op.mode x %in.x y %in.y"),
					tr("rotate"):     tr("Draw %op.mode %in.rot"),
					tr("reset"):      tr("Draw %op.mode"),
				}
			},
			options  = { mode   = { items = DRAW_MODES },
						 r      = { placeholder = "255" }, 
						 g      = { placeholder = "0" }, 
						 b      = { placeholder = "255" },
						 a      = { placeholder = "255" },
						 color  = { placeholder = "0" },
						 width  = { placeholder = "0" },
						 height = { placeholder = "0" },
						 x      = { placeholder = "0" },
						 y      = { placeholder = "0" },
						 x1     = { placeholder = "0" },
						 y1     = { placeholder = "0" },
						 x2     = { placeholder = "0" },
						 y2     = { placeholder = "0" },
						 x3     = { placeholder = "0" },
						 y3     = { placeholder = "0" },
						 sides  = { placeholder = "4" },
						 radius = { placeholder = "0" },
						 rot    = { placeholder = "0" },
						 image  = { placeholder = "@copper" },
						 size   = { placeholder = "32" } },
			export   = _stub,
		},
		"Print": {
			template = tr("Print %in.content %bu.txt"),
			options  = { content = { placeholder = "frog" }, 
						 txt     = { text = tr("txt"), pressed = _stub } },
			export   = _stub,
		},
		"PrintChar": {
			template = tr("PrintChar %op.char"),
			options  = { char = { items = ASCII } },
			export   = _stub,
		},
		"Format": {
			template = tr("Format %in.content %bu.txt"),
			options  = { content = { placeholder = "frog" }, 
						 txt     = { text = tr("txt"), pressed = _stub } },
			export   = _stub,
		},
	},
	"Units": {
		"UnitBind": {
			template = tr("Unit Bind %in.all_poly"),
			options  = {},
			export   = _stub,
		},
		"UnitIdle": {
			template = tr("Unit idle"),
			options  = {},
			export   = _stub,
		},
		"UnitStop": {
			template = tr("Unit stop"),
			options  = {},
			export   = _stub,
		},
		"UnitMove": {
			template = tr("Unit CtrlMove %op.mode x %in.x y %in.y"),
			options  = { mode = { items   = [tr("move"),tr("approach"),tr("pathfind"),tr("autoPathfind")] },
						 x    = { placeholder = "0" },
						 y    = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitBoost": {
			template = tr("Unit CtrlBoost %in.id"),
			options  = { id = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitShoot": {
			template = tr("Unit CtrlShoot %op.mode x %in.x y %in.y shoot %in.s"),
			options  = { mode = { items = [tr("target"),tr("targetp")] },
						 x    = { placeholder = "0" },
						 y    = { placeholder = "0" },
						 s    = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitItem": {
			template = tr("Unit CtrlItem %op.mode to %in.to amount %in.amount"),
			options  = { mode   = { items = [tr("itemDrop"),tr("itemTake")] },
						 to     = { placeholder = "0" },
						 amount = { placeholder = "999" } },
			export   = _stub,
		},
		"UnitPay": {
			template = tr("Unit CtrlPay %op.mode TakeUnits %in.unit"),
			options  = { mode = { items = [tr("payTake"),tr("payDrop"),tr("payEnter")] },
						 unit = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitMine": {
			template = tr("Unit CtrlMine x %in.x y %in.y"),
			options  = { x = { placeholder = "0" },
						 y = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitFlag": {
			template = tr("UnitFlag %in.id"),
			options  = { id = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitBuild": {
			template = tr("Unit CtrlBuild x %in.x y %in.y\nblock %in.block rotation %in.rot config %in.cfg"),
			options  = { x     = { placeholder = "0" },
						 y     = { placeholder = "0" }, 
						 block = { placeholder = "0" }, 
						 rot   = { placeholder = "0" }, 
						 cfg   = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitGetblock": {
			template = tr("Unit CtrlGetBlock x %in.x y %in.y\ntype %in.type building %in.bld floor %in.flr"),
			options  = { x    = { placeholder = "0" },
						 y    = { placeholder = "0" }, 
						 type = { placeholder = "0" }, 
						 bld  = { placeholder = "0" }, 
						 flr  = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitWithin": {
			template = tr("Unit CtrlWithin %in.x %in.y radius %in.radius result %in.result"),
			options  = { x      = { placeholder = "0" },
						 y      = { placeholder = "0" }, 
						 radius = { placeholder = "0" }, 
						 result = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitUnbind": {
			template = tr("Unit unbind"),
			options  = {},
			export   = _stub,
		},
		"UnitRadar": {
			template = tr("Unit Radar target %op.s1 %op.s2 %op.s3\norder %in.num sort %op.radar %in.result"),
			options  = { s1     = { items = SORTS }, 
						 s2     = { items = SORTS }, 
						 s3     = { items = SORTS }, 
						 num    = { placeholder = "1" },
						 radar  = { items = RADAR_KEYS }, 
						 result = { placeholder = "result" } },
			export   = _stub,
		},
		"UnitLocate": {
			template = tr("Unit Locate %op.find ore %in.ore\noutX %in.outX outY %in.outY found %in.found"),
			variants = {
				"find": {
					tr("ore"):      tr("Unit Locate %op.find ore %in.ore\noutX %in.outX outY %in.outY found %in.found"),
					tr("building"): tr("Unit Locate %op.find group %op.group enemy %in.enemy\noutX %in.outX outY %in.outY found %in.found building %in.building"),
					tr("spawn"):    tr("Unit Locate %op.find\noutX %in.outX outY %in.outY found %in.found"),
					tr("damaged"):  tr("Unit Locate %op.find\noutX %in.outX outY %in.outY found %in.found"),
				}
			},
			options  = { find   = { items = [tr("ore"),tr("building"),tr("spawn"),tr("damaged")] },
			group    = { items   = [tr("core"),tr("storage"),tr("generator"),tr("turret"),tr("factory"),
									tr("repair"),tr("battery"),tr("reactor"),tr("drill"),tr("shield")] },
			enemy    = { placeholder = "true" },
			ore      = { placeholder = "@copper" },
			outX     = { placeholder = "outx" },
			outY     = { placeholder = "outy" }, 
			found    = { placeholder = "found" }, 
			building = { placeholder = "building" } },
			export   = _stub,
		},
	},
}


static var _inst: BlockData

static func _instance() -> BlockData:
	if not _inst:
		_inst = BlockData.new()
	return _inst


static func kinds() -> Array:
	return _instance().BLOCKS.keys()


static func blocks() -> Dictionary:
	var result: Dictionary = {}
	for kind in _instance().BLOCKS:
		result[kind] = _instance().BLOCKS[kind].keys()
	return result


static func get_block(kind: String, name: String) -> Dictionary:
	return _instance().BLOCKS.get(kind, {}).get(name, {})
