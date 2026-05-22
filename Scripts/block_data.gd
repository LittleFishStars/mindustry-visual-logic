extends RefCounted


const SORTS       = ["any","enemy","ally","player","attacker","flying","boss","ground"]
const COMPS       = ["==","not","<","<=",">",">=","===","always"]
const RADAR_KEYS  = ["distance","health","shield","armor","maxHealth"]
const OPS         = ["+","-","*","/","//","%","^","==","!=","&&","<","<=",">",">=","===","<<",">>",">>>",
					 "or","b-and","xor","flip","max","min","angle","angle-diff","len","noise",
					 "abs","sign","log","logn","log10","floor","ceil","round","sqrt","rand",
					 "sin","cos","tan","asin","acos","atan"]
const DRAW_MODES  = ["clear","color","col","stroke","line","rect","lineRect","polfoundy","linePoly",
					 "triangle","image","print","translate","scale","rotate","reset"]
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


var BLOCKS: Dictionary = {
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
						 link = { placeholder = "0" } },
			export   = _stub,
		},
		"Control": {
			template = tr("Control %op.mode %in.block to %in.index"),
			options  = { mode = { items = ["enabled", "shoot", "shootp", "config", "color"], changed = _stub },
						 block = { placeholder = "block1" },
						 index = { placeholder = "0" } },
			export   = _stub,
		},
		"Radar": {
			template = tr("Radar from %in.turret %op.s1 %op.s2 %op.s3\norder %in.num sort %op.radar %in.result"),
			options  = { turret = { placeholder = "turret1" }, 
						 s1 = { items = SORTS, changed = _stub },
						 s2 = { items = SORTS, changed = _stub },
						 s3 = { items = SORTS, changed = _stub },
						 num = { placeholder = "1" },
						 radar = { items = RADAR_KEYS, changed = _stub },
						 result = { placeholder = "result" } },
			export   = _stub,
		},
		"Sensor": {
			template = tr("Sensor %in.result = %in.all in %in.block"),
			options  = { result = { placeholder = "result" },
						 block = { placeholder = "block1" } },
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
						 cmp = { items = COMPS, changed = _stub },
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
			options  = { a = { placeholder = "a" },
						 cmp = { items = COMPS, changed = _stub },
						 b = { placeholder = "b" } },
			export   = _stub,
		},
	},
	"Operations": {
		"Set": {
			template = tr("Set %in.result = %in.value"),
			options  = { result = { placeholder = "result" },
						 value = { placeholder = "0" } },
			export   = _stub,
		},
		"Operation": {
			template = tr("Operation %in.result = %in.a %op.ops %in.b"),
			options  = { result = { placeholder = "result" },
						 a = { placeholder = "a" },
						 ops = { items = OPS, changed = _stub },
						 b = { placeholder = "b" } },
			export   = _stub,
		},
		"Select": {
			template = tr("Select %in.result = if %in.x %op.cmp %in.value\nthen %in.t else %in.f"),
			options  = { result = { placeholder = "result" },
						 cmp = { items = COMPS, changed = _stub }, 
						 value = { placeholder = "false" }, 
						 t = { placeholder = "false" }, 
						 f = { placeholder = "false" } },
			export   = _stub,
		},
		"Lookup": {
			template = tr("Lookup %in.result = lookup %op.type # %in.id"),
			options  = { result = { placeholder = "result" },
						 type = { items = ["block","unit","item","liquid","team"], changed = _stub }, 
						 id = { placeholder = "0" } },
			export   = _stub,
		},
		"PackColor": {
			template = tr("Pack Color %in.result = pack %in.r %in.g %in.b %in.a"),
			options  = { result = { placeholder = "result" },
						 r = { placeholder = "1" }, 
						 g = { placeholder = "0" }, 
						 b = { placeholder = "0" }, 
						 a = { placeholder = "1" } },
			export   = _stub,
		},
		"UnpackColor": {
			template = tr("Unpack Color %in.r %in.g %in.b %in.a = unpack %in.result"),
			options  = { r = { placeholder = "r" }, 
						 g = { placeholder = "g" }, 
						 b = { placeholder = "b" }, 
						 a = { placeholder = "a" },
						 result = { placeholder = "result" } },
			export   = _stub,
		},
	},
	"PutInOut": {
		"Read": {
			template = tr("Read %in.result = %in.cell at %in.idx"),
			options  = { result = { placeholder = "result" },
						 cell = { placeholder = "cell1" }, 
						 idx = { placeholder = "0" } },
			export   = _stub,
		},
		"Write": {
			template = tr("Write %in.result = %in.cell at %in.idx"),
			options  = { result = { placeholder = "result" },
						 cell = { placeholder = "cell1" }, 
						 idx = { placeholder = "0" } },
			export   = _stub,
		},
		"Draw": {
			template = tr("Draw %op.mode r %in.r g %in.g b %in.b"),
			options  = { mode = { items = DRAW_MODES, changed = _stub },
						 r = { placeholder = "255" }, 
						 g = { placeholder = "0" }, 
						 b = { placeholder = "255" } },
			export   = _stub,
		},
		"Print": {
			template = tr("Print %in.content %bu.txt"),
			options  = { content = { placeholder = "frog" }, 
						 txt = { text = "txt", pressed = _stub } },
			export   = _stub,
		},
		"PrintChar": {
			template = tr("PrintChar %op.char"),
			options  = { char = { items = ASCII, changed = _stub } },
			export   = _stub,
		},
		"Format": {
			template = tr("Format %in.content %bu.txt"),
			options  = { content = { placeholder = "frog" }, 
						 txt = { text = "txt", pressed = _stub } },
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
			options  = { mode = { items = ["move","approach","pathfind","autoPathfind"], changed = _stub },
						 x = { placeholder = "0" },
						 y = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitBoost": {
			template = tr("Unit CtrlBoost %in.id"),
			options  = { id = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitShoot": {
			template = tr("Unit CtrlShoot %op.mode x %in.x y %in.y shoot %in.s"),
			options  = { mode = { items = ["target","targetp"], changed = _stub },
						 x = { placeholder = "0" },
						 y = { placeholder = "0" },
						 s = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitItem": {
			template = tr("Unit CtrlItem %op.mode to %in.to amount %in.amount"),
			options  = { mode = { items = ["itemDrop","itemTake"], changed = _stub },
						 to = { placeholder = "0" },
						 amount = { placeholder = "999" } },
			export   = _stub,
		},
		"UnitPay": {
			template = tr("Unit CtrlPay %op.mode TakeUnits %in.unit"),
			options  = { mode = { items = ["payTake","payDrop","payEnter"], changed = _stub },
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
			options  = { x = { placeholder = "0" },
						 y = { placeholder = "0" }, 
						 block = { placeholder = "0" }, 
						 rot = { placeholder = "0" }, 
						 cfg = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitGetblock": {
			template = tr("Unit CtrlGetBlock x %in.x y %in.y\ntype %in.type building %in.bld floor %in.flr"),
			options  = { x = { placeholder = "0" },
						 y = { placeholder = "0" }, 
						 type = { placeholder = "0" }, 
						 bld = { placeholder = "0" }, 
						 flr = { placeholder = "0" } },
			export   = _stub,
		},
		"UnitWithin": {
			template = tr("Unit CtrlWithin %in.x %in.y radius %in.radius result %in.result"),
			options  = { x = { placeholder = "0" },
						 y = { placeholder = "0" }, 
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
			options  = { s1 = { items = SORTS, changed = _stub }, 
						 s2 = { items = SORTS, changed = _stub }, 
						 s3 = { items = SORTS, changed = _stub }, 
						 num = { placeholder = "1" },
						 radar = { items = RADAR_KEYS, changed = _stub }, 
						 result = { placeholder = "result" } },
			export   = _stub,
		},
		"UnitLocate": {
			template = tr("Unit Locate %op.find group %op.group enemy %in.enemy %in.res\n" +
						  "outX %in.outX outY %in.outY found %in.found building %in.building"),
			options  = { find = { items = ["ore","building","spawn","damaged"], changed = _stub },
						 group = { items = ["core","storage","generator","turret","factory",
											"repair","battery","reactor","drill","shield"], changed = _stub },
						 enemy = { placeholder = "true" }, 
						 outX = { placeholder = "outx" },
						 outY = { placeholder = "outy" }, 
						 found = { placeholder = "found" }, 
						 building = { placeholder = "building" } },
			export   = _stub,
		},
	},
}
