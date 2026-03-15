package paopao.zep;

import haxe.ds.StringMap;
import paopao.zep.Ast;
import paopao.zep.Error;

private class Signal {}

private class ReturnSig extends Signal {
	public var v:Dynamic;

	public function new(v:Dynamic) {
		this.v = v;
	}
}

private class StopSig extends Signal {
	public function new() {}
}

private class ContinueSig extends Signal {
	public function new() {}
}

private class ZepThrow extends Signal {
	public var v:Dynamic;

	public function new(v:Dynamic) {
		this.v = v;
	}
}

private class YieldSig extends Signal {
	public var v:Dynamic;

	public function new(v:Dynamic) {
		this.v = v;
	}
}

class Env {
	var vars:StringMap<Dynamic>;

	public var parent:Null<Env>;

	public function new(?parent:Env) {
		this.parent = parent;
		this.vars = new StringMap();
	}

	public function get(name:String):Dynamic {
		if (vars.exists(name)) {
			var v = vars.get(name);
			if (Std.isOfType(v, ZepLazy)) {
				v = (cast v : ZepLazy).force();
				vars.set(name, v);
			}
			return v;
		}
		if (parent != null)
			return parent.get(name);
		throw new Error(ERunError('Undefined variable "$name"'));
	}

	public inline function define(name:String, v:Dynamic):Void
		vars.set(name, v);

	public function assign(name:String, v:Dynamic):Bool {
		if (vars.exists(name)) {
			vars.set(name, v);
			return true;
		}
		if (parent != null)
			return parent.assign(name, v);
		return false;
	}

	public inline function setOrDefine(name:String, v:Dynamic):Void {
		if (!assign(name, v))
			define(name, v);
	}

	public inline function child():Env
		return new Env(this);
}

class ZepFunction {
	public var name:Null<String>;
	public var args:Array<Argument>;
	public var body:Null<Expr>; // null for natives
	public var closure:Env;
	public var varNames:VariableInfo;
	public var isGenerator:Bool;
	public var native:Null<Array<Dynamic>->Dynamic>;

	public function new(name, args, body, closure, varNames, isGenerator) {
		this.name = name;
		this.args = args;
		this.body = body;
		this.closure = closure;
		this.varNames = varNames;
		this.isGenerator = isGenerator;
	}

	public static function ofNative(name:String, fn:Array<Dynamic>->Dynamic):ZepFunction {
		var f = new ZepFunction(name, [], null, new Env(), [], false);
		f.native = fn;
		return f;
	}
}

/** A class definition — holds field defaults, methods, and static members. */
class ZepClass {
	public var name:String;
	public var parent:Null<ZepClass>;
	public var interfaces:Array<String>;
	public var fieldDefaults:StringMap<Null<Dynamic>>; // declared instance fields
	public var methods:StringMap<ZepFunction>;
	public var staticFields:StringMap<Dynamic>;
	public var isAbstract:Bool;
	public var isInterface:Bool;

	public function new(name:String) {
		this.name = name;
		this.interfaces = [];
		this.fieldDefaults = new StringMap();
		this.methods = new StringMap();
		this.staticFields = new StringMap();
	}
}

/** A live object instance. Also backs the IZepCustomBehaviour contract. */
class ZepInstance implements IZepCustomBehaviour {
	public var klass:ZepClass;
	public var fields:StringMap<Dynamic>;

	public function new(klass:ZepClass) {
		this.klass = klass;
		this.fields = new StringMap();
		// Seed with defaults from the entire inheritance chain (child wins).
		var k = klass;
		var chain:Array<ZepClass> = [];
		while (k != null) {
			chain.unshift(k);
			k = k.parent;
		}
		for (c in chain)
			for (fname => def in c.fieldDefaults)
				if (!fields.exists(fname))
					fields.set(fname, def);
	}

	public function zget(name:String):Dynamic {
		if (fields.exists(name))
			return fields.get(name);
		var k = klass;
		while (k != null) {
			if (k.methods.exists(name))
				return k.methods.get(name);
			k = k.parent;
		}
		throw new Error(ERunError('No field "$name" on ${klass.name}'));
	}

	public function zset(name:String, value:Dynamic):Dynamic {
		fields.set(name, value);
		return value;
	}
}

/** An enum type definition.  Color.Red returns the variant value. */
class ZepEnumDef {
	public var name:String;
	public var variants:StringMap<Dynamic>;

	public function new(name:String) {
		this.name = name;
		this.variants = new StringMap();
	}
}

/** An inclusive integer range   from..to */
class ZepRange {
	public var from:Int;
	public var to:Int;

	public function new(f:Int, t:Int) {
		from = f;
		to = t;
	}

	public function contains(v:Dynamic):Bool {
		var i = Std.int(v);
		return i >= from && i <= to;
	}

	public function toArray():Array<Dynamic> {
		var a:Array<Dynamic> = [];
		var i = from;
		while (i <= to) {
			a.push(i);
			i++;
		}
		return a;
	}
}

/** A deferred lazy value — evaluates exactly once on first access. */
class ZepLazy {
	var thunk:Void->Dynamic;
	var computed = false;
	var cached:Dynamic;

	public function new(t:Void->Dynamic) {
		thunk = t;
	}

	public function force():Dynamic {
		if (!computed) {
			cached = thunk();
			computed = true;
		}
		return cached;
	}
}

// Test tracking
typedef TestResult = {name:String, passed:Bool, error:Null<String>}

// Interpreter
class Interp {
	// State
	public var globals:Env;

	var env:Env;
	var varNames:VariableInfo;

	/** All text written by  say  (also forwarded to printFn). */
	public var output:Array<String>;

	public var testResults:Array<TestResult>;

	/**
	 * Override to redirect output — defaults to Sys.println.
	 * Set before calling run().
	 */
	public var printFn:String->Void;

	/**
	 * When non-null, yield statements push here instead of throwing.
	 * Allows generator bodies to run to completion while collecting all yields.
	 */
	var yieldCollector:Null<Array<Dynamic>>;

	// Construction
	public function new() {
		globals = new Env();
		env = globals;
		varNames = [];
		output = [];
		testResults = [];
		yieldCollector = null;
		printFn = s -> {
			output.push(s);
			Sys.println(s);
		};
		loadStdlib();
	}

	// Entry points

	/** Run a pre-parsed statement list with its variable-name table. */
	public function run(stmts:Array<Expr>, varNames:VariableInfo):Dynamic {
		this.varNames = varNames;
		var last:Dynamic = null;
		for (s in stmts)
			last = eval(s);
		return last;
	}

	/** Convenience: lex + parse + run in one call. */
	public function runSource(src:String, ?fileName:String):Dynamic {
		var toks = new Lexer().tokenize(src, fileName);
		var parser = new Parser();
		var stmts = parser.parse(toks, fileName);
		return run(stmts, parser.varNames);
	}

	// Core evaluator
	function eval(e:Expr):Dynamic {
		return switch e.expr {
			case EEmpty: null;
			case EConst(c): evalConst(c);
			case EIdent(name): if (isSentinel(name)) null else env.get(name);
			case EVarDecl(name, _, valExpr, _, isLazy):
				var v:Dynamic = switch [valExpr, isLazy] {
					case [null, _]: null;
					case [ve, true]: new ZepLazy(() -> eval(ve));
					case [ve, false]: eval(ve);
				}
				env.define(name, v);
				v;
			case EBinop(op, e1, e2): evalBinop(op, e1, e2);
			case EUnop(op, prefix, inner): evalUnop(op, prefix, inner, eval(inner));
			case EAssign(target, rhs):
				var v = eval(rhs);
				assignTo(target, v);
				v;
			case EAssignOp(op, target, rhs):
				var v = applyBinop(op, eval(target), eval(rhs));
				assignTo(target, v);
				v;

			case EChainComp(left, chain):
				var prev = eval(left);
				var result = true;
				for (link in chain) {
					var next = eval(link.e);
					if (!isTruthy(applyBinop(link.op, prev, next))) {
						result = false;
						break;
					}
					prev = next;
				}
				result;

			case EField(obj, name): getField(eval(obj), name, e.line);
			case EOptField(obj, name):
				var v = eval(obj);
				v == null ? null : getField(v, name, e.line);

			case EArrayAccess(arr, idx): containerGet(eval(arr), eval(idx), e.line);
			case ESpread(inner): eval(inner); // context-handled in EArray/ECall

			case EArray(vals):
				var a:Array<Dynamic> = [];
				for (item in vals)
					switch item.expr {
						case ESpread(inner):
							var s = eval(inner);
							if (Std.isOfType(s, Array)) for (x in (cast s : Array<Dynamic>))
								a.push(x); else a.push(s);
						default: a.push(eval(item));
					}
				a;

			case EObject(flds):
				var m = new StringMap<Dynamic>();
				for (f in flds)
					m.set(f.name, eval(f.expr));
				m;

			case EInterp(parts):
				var buf = new StringBuf();
				for (p in parts)
					switch p {
						case IPStr(s): buf.add(s);
						case IPExpr(x): buf.add(valToString(eval(x)));
					}
				buf.toString();

			case EFunction(name, args, _, body, isLazy):
				var fn = new ZepFunction(name, args, body, env, varNames, isLazy);
				if (name != null && !StringTools.startsWith(name, "~s~"))
					env.setOrDefine(name, fn);
				fn;

			case ECall(callee, rawArgs):
				var pos = new Array<Dynamic>();
				var named = new StringMap<Dynamic>();
				for (a in rawArgs)
					switch a.expr {
						case ENamedArg(n, v): named.set(n, eval(v));
						case ESpread(inner):
							var s = eval(inner);
							if (Std.isOfType(s, Array)) for (x in (cast s : Array<Dynamic>))
								pos.push(x); else pos.push(s);
						default: pos.push(eval(a));
					}
				callValue(eval(callee), pos, named, e.line);

			case ENamedArg(_, _): null; // only consumed inside ECall

			case EReturn(inner):
				throw new ReturnSig(inner == null ? null : eval(inner));

			case EYield(inner):
				var v = eval(inner);
				if (yieldCollector != null) {
					yieldCollector.push(v);
					null;
				} else throw new YieldSig(v);

			case EBlock(exprs): evalBlock(exprs);

			case EIf(cond, then, els):
				isTruthy(eval(cond)) ? eval(then) : (els != null ? eval(els) : null);

			case EUnless(cond, body):
				if (!isTruthy(eval(cond)))
					eval(body);
				null;

			case ETernary(cond, then, els):
				isTruthy(eval(cond)) ? eval(then) : eval(els);

			case EMatch(subject, cases, def): evalMatch(eval(subject), cases, def);

			case EWhile(cond, body):
				runLoop(() -> {
					while (isTruthy(eval(cond)))
						runLoopBody(body);
				});
				null;

			case ERepeat(count, idxName, body):
				var n = Std.int(eval(count));
				runLoop(() -> {
					for (i in 0...n) {
						var child = env.child();
						if (idxName != null)
							child.define(idxName, i);
						var saved = env;
						env = child;
						try {
							eval(body);
						} catch (_:ContinueSig) {}
						env = saved;
					}
				});
				null;

			case EEvery(name, iterExpr, body):
				var iter = eval(iterExpr);
				runLoop(() -> {
					for (item in toIterable(iter, e.line)) {
						var child = env.child();
						child.define(name, item);
						var saved = env;
						env = child;
						try {
							eval(body);
						} catch (_:ContinueSig) {}
						env = saved;
					}
				});
				null;

			case EStop: throw new StopSig();
			case EContinue: throw new ContinueSig();

			case EThrow(inner): throw new ZepThrow(eval(inner));

			case ETry(body, catches, always):
				var result:Dynamic = null;
				try {
					result = eval(body);
				} catch (sig:ZepThrow) {
					var handled = false;
					for (c in catches) {
						if (c.type == null || typeOf(sig.v) == c.type) {
							var child = env.child();
							child.define(c.name, sig.v);
							var saved = env;
							env = child;
							try {
								result = eval(c.expr);
							} catch (e) {
								env = saved;
								if (always != null)
									eval(always);
								throw e;
							}
							env = saved;
							handled = true;
							break;
						}
					}
					if (!handled) {
						if (always != null)
							eval(always);
						throw sig;
					}
				}
				if (always != null)
					eval(always);
				result;

			case ECast(inner, type): castValue(eval(inner), type);
			case ETypeMatch(_): null; // used only by matchPattern

			case ENullCoal(inner, def):
				var v = eval(inner);
				v != null ? v : eval(def);

			case ERange(from, to):
				new ZepRange(Std.int(eval(from)), Std.int(eval(to)));

			case EPipeline(lhs, rhs):
				var v = eval(lhs);
				switch rhs.expr {
					case ECall(fnExpr, rawArgs):
						var fn = eval(fnExpr);
						var args = [v];
						for (a in rawArgs)
							args.push(eval(a));
						callValue(fn, args, new StringMap(), rhs.line);
					default:
						callValue(eval(rhs), [v], new StringMap(), rhs.line);
				}

			case ESay(inner):
				printFn(valToString(eval(inner)));
				null;

			case ENew(type, rawArgs):
				var klass = env.get(type);
				if (!Std.isOfType(klass, ZepClass))
					interpError('$type is not a class', e.line);
				instantiate(cast klass, [for (a in rawArgs) eval(a)], new StringMap());

			case EImport(path, mode, isLazy):
				loadModule(path, mode, isLazy);
				null;

			case EDestructArray(names, rhs):
				var arr:Array<Dynamic> = eval(rhs);
				for (i => name in names)
					if (name != null)
						env.setOrDefine(name, i < arr.length ? arr[i] : null);
				null;

			case EDestructObject(flds, rhs):
				var obj = eval(rhs);
				for (f in flds)
					env.setOrDefine(f, getField(obj, f, e.line));
				null;

			case ETest(name, body):
				runTest(name, body);
				null;
			case EExpect(inner, throws):
				if (throws) {
					var threw = false;
					try {
						eval(inner);
					} catch (_:ZepThrow) {
						threw = true;
					}
					if (!threw)
						throw new ZepThrow("Expected an exception but none was thrown");
				} else {
					var v = eval(inner);
					if (!isTruthy(v))
						throw new ZepThrow('Assertion failed: expected truthy, got ${valToString(v)}');
				}
				null;
		}
	}

	// Block — also the dispatch point for class / enum / record sentinels
	function evalBlock(exprs:Array<Expr>):Dynamic {
		if (exprs.length > 0)
			switch exprs[0].expr {
				case EIdent(tag)
					if (StringTools.startsWith(tag, "class:")
						|| StringTools.startsWith(tag, "abstract:class:")
						|| StringTools.startsWith(tag, "interface:")):
					return defineClass(tag, exprs);
				case EIdent(tag) if (StringTools.startsWith(tag, "enum:")):
					return defineEnum(tag, exprs);
				case EIdent(tag) if (StringTools.startsWith(tag, "record:")):
					return defineRecord(tag, exprs);
				default:
			}

		var child = env.child();
		var saved = env;
		env = child;
		var last:Dynamic = null;
		for (ex in exprs)
			last = eval(ex);
		env = saved;
		return last;
	}

	// Class definition

	/**
	 * Tag formats:
	 *   class:Dog           — simple class
	 *   class:Cat|Animal    — class with parent
	 *   abstract:class:Dog  — abstract class
	 *   interface:Flyable   — interface
	 */
	function defineClass(tag:String, exprs:Array<Expr>):Dynamic {
		var colonIdx = tag.lastIndexOf(":");
		var nameAndParent = tag.substring(colonIdx + 1);
		var pipeIdx = nameAndParent.indexOf("|");
		var name = pipeIdx >= 0 ? nameAndParent.substring(0, pipeIdx) : nameAndParent;
		var parentName = pipeIdx >= 0 ? nameAndParent.substring(pipeIdx + 1) : null;

		var klass = new ZepClass(name);
		klass.isAbstract = StringTools.startsWith(tag, "abstract:");
		klass.isInterface = StringTools.startsWith(tag, "interface:");

		// Resolve parent
		if (parentName != null) {
			var p = try env.get(parentName) catch (_:Dynamic) null;
			if (Std.isOfType(p, ZepClass))
				klass.parent = cast p;
		}

		for (i in 1...exprs.length)
			switch exprs[i].expr {
				// Interface sentinels from the parser
				case EIdent(s) if (StringTools.startsWith(s, "iface:")):
					klass.interfaces.push(s.substring(6));

				// Fields: strip the ~s~ static marker if present
				case EVarDecl(rawName, _, defExpr, _, isLazy):
					var isStatic = StringTools.startsWith(rawName, "~s~");
					var fname = isStatic ? rawName.substring(3) : rawName;
					var dv:Dynamic = defExpr == null ? null : isLazy ? new ZepLazy(() -> eval(defExpr)) : eval(defExpr);
					if (isStatic)
						klass.staticFields.set(fname, dv);
					else
						klass.fieldDefaults.set(fname, dv);

				// Methods: strip the ~s~ static marker if present
				case EFunction(rawName, args, _, body, isLazy) if (rawName != null):
					var isStatic = StringTools.startsWith(rawName, "~s~");
					var mname = isStatic ? rawName.substring(3) : rawName;
					var fn = new ZepFunction(mname, args, body, env, varNames, isLazy);
					if (isStatic)
						klass.staticFields.set(mname, fn);
					else
						klass.methods.set(mname, fn);

				default:
			}

		env.setOrDefine(name, klass);
		return klass;
	}

	// Enum definition
	function defineEnum(tag:String, exprs:Array<Expr>):Dynamic {
		var name = tag.substring("enum:".length);
		var enumDef = new ZepEnumDef(name);

		for (i in 1...exprs.length)
			switch exprs[i].expr {
				case EIdent(vname):
					enumDef.variants.set(vname, vname);
				case EAssign(lhs, rhs):
					switch lhs.expr {
						case EIdent(vname): enumDef.variants.set(vname, eval(rhs));
						default:
					}
				default:
			}

		env.setOrDefine(name, enumDef);
		return enumDef;
	}

	// Record definition  (becomes a named-arg factory function)
	function defineRecord(tag:String, exprs:Array<Expr>):Dynamic {
		var name = tag.substring("record:".length);
		var fields = [
			for (i in 1...exprs.length)
				switch exprs[i].expr {
					case EVarDecl(fname, _, _, _, _):
						fname;
					default:
						continue;
				}
		];

		var ctor = ZepFunction.ofNative(name, args -> {
			var m = new StringMap<Dynamic>();
			for (i => fname in fields)
				m.set(fname, i < args.length ? args[i] : null);
			m;
		});
		env.setOrDefine(name, ctor);
		return ctor;
	}

	// Binary operators
	function evalBinop(op:ExprBinop, e1:Expr, e2:Expr):Dynamic {
		// Short-circuit before evaluating both sides
		if (op == OpAnd)
			return isTruthy(eval(e1)) ? eval(e2) : false;
		if (op == OpOr)
			return isTruthy(eval(e1)) ? true : eval(e2);
		return applyBinop(op, eval(e1), eval(e2));
	}

	function applyBinop(op:ExprBinop, a:Dynamic, b:Dynamic):Dynamic {
		return switch op {
			case OpAdd:
				(Std.isOfType(a, String) || Std.isOfType(b, String)) ? valToString(a) + valToString(b) : (a : Float) + (b : Float);
			case OpSub: (a : Float) - (b : Float);
			case OpMul: (a : Float) * (b : Float);
			case OpDiv: (a : Float) / (b : Float);
			case OpMod: (a : Int) % (b : Int);
			case OpEq: valEq(a, b);
			case OpNotEq: !valEq(a, b);
			case OpLt: (a : Float) < (b : Float);
			case OpLte: (a : Float) <= (b : Float);
			case OpGt: (a : Float) > (b : Float);
			case OpGte: (a : Float) >= (b : Float);
			case OpAnd: isTruthy(a) && isTruthy(b);
			case OpOr: isTruthy(a) || isTruthy(b);
			case OpIs: a == b;
			case OpIsNot: a != b;
			case OpIn: inCheck(a, b);
			default: null;
		}
	}

	function inCheck(val:Dynamic, container:Dynamic):Bool {
		if (Std.isOfType(container, ZepRange))
			return (cast container : ZepRange).contains(val);
		if (Std.isOfType(container, Array))
			return (cast container : Array<Dynamic>).contains(val);
		if (Std.isOfType(container, StringMap))
			return (cast container : StringMap<Dynamic>).exists(valToString(val));
		return false;
	}

	// Unary operators
	function evalUnop(op:ExprUnop, prefix:Bool, target:Expr, v:Dynamic):Dynamic {
		return switch op {
			case OpNot: !isTruthy(v);
			case OpNeg: -(v : Float);
			case OpIncr:
				var next = (v : Float) + 1;
				assignTo(target, next);
				prefix ? next : v;
			case OpDecr:
				var next = (v : Float) - 1;
				assignTo(target, next);
				prefix ? next : v;
		}
	}

	// Assignment target  (l-value resolution)
	function assignTo(target:Expr, value:Dynamic):Void {
		switch target.expr {
			case EIdent(name):
				if (!env.assign(name, value))
					env.define(name, value);
			case EField(objExpr, name):
				setField(eval(objExpr), name, value, target.line);
			case EOptField(objExpr, name):
				var obj = eval(objExpr);
				if (obj != null)
					setField(obj, name, value, target.line);
			case EArrayAccess(arrExpr, idxExpr):
				var arr = eval(arrExpr);
				var idx = eval(idxExpr);
				if (Std.isOfType(arr, Array))
					(cast arr : Array<Dynamic>)[Std.int(idx)] = value;
				else if (Std.isOfType(arr, StringMap))
					(cast arr : StringMap<Dynamic>).set(valToString(idx), value);
				else
					interpError("Cannot index-assign on ${typeOf(arr)}", target.line);
			default:
				interpError("Invalid assignment target", target.line);
		}
	}

	// Field access / mutation
	function getField(obj:Dynamic, name:String, line:Int):Dynamic {
		if (obj == null)
			interpError('Cannot read field "$name" of none', line);

		// IZepCustomBehaviour (ZepInstance implements this)
		if (Std.isOfType(obj, IZepCustomBehaviour))
			return (cast obj : IZepCustomBehaviour).zget(name);

		// ZepInstance — but IZepCustomBehaviour already handles it above
		// ZepClass — static member or enum-variant-style access
		if (Std.isOfType(obj, ZepClass)) {
			var klass:ZepClass = cast obj;
			if (klass.staticFields.exists(name))
				return klass.staticFields.get(name);
			if (klass.methods.exists(name))
				return klass.methods.get(name);
			interpError('No static member "$name" on class ${klass.name}', line);
		}

		// ZepEnumDef  — variant access:  Direction.North
		if (Std.isOfType(obj, ZepEnumDef)) {
			var ed:ZepEnumDef = cast obj;
			if (ed.variants.exists(name))
				return ed.variants.get(name);
			interpError('No variant "$name" in enum ${ed.name}', line);
		}

		// StringMap  — object literals and records
		if (Std.isOfType(obj, StringMap)) {
			var m:StringMap<Dynamic> = cast obj;
			if (m.exists(name))
				return m.get(name);
			return builtinMethod(obj, name, line);
		}

		// String built-ins
		if (Std.isOfType(obj, String)) {
			if (name == "length")
				return (obj : String).length;
			return builtinMethod(obj, name, line);
		}

		// Array built-ins
		if (Std.isOfType(obj, Array)) {
			if (name == "length")
				return (cast obj : Array<Dynamic>).length;
			return builtinMethod(obj, name, line);
		}

		// ZepRange
		if (Std.isOfType(obj, ZepRange))
			switch name {
				case "from":
					return (cast obj : ZepRange).from;
				case "to":
					return (cast obj : ZepRange).to;
				default:
			}

		// Haxe reflect fallback (external objects)
		var v = Reflect.field(obj, name);
		if (v != null)
			return v;
		interpError('No field "$name"', line);
		return null;
	}

	function setField(obj:Dynamic, name:String, value:Dynamic, line:Int):Void {
		if (obj == null)
			interpError('Cannot set field "$name" of none', line);
		if (Std.isOfType(obj, IZepCustomBehaviour)) {
			(cast obj : IZepCustomBehaviour).zset(name, value);
			return;
		}
		if (Std.isOfType(obj, ZepClass)) {
			(cast obj : ZepClass).staticFields.set(name, value);
			return;
		}
		if (Std.isOfType(obj, StringMap)) {
			(cast obj : StringMap<Dynamic>).set(name, value);
			return;
		}
		Reflect.setField(obj, name, value);
	}

	// Indexed container access
	function containerGet(container:Dynamic, idx:Dynamic, line:Int):Dynamic {
		if (Std.isOfType(container, Array))
			return (cast container : Array<Dynamic>)[Std.int(idx)];
		if (Std.isOfType(container, StringMap))
			return (cast container : StringMap<Dynamic>).get(valToString(idx));
		if (Std.isOfType(container, ZepRange)) {
			var r:ZepRange = cast container;
			var i = r.from + Std.int(idx);
			return i <= r.to ? i : null;
		}
		if (Std.isOfType(container, String)) {
			var s:String = cast container;
			return s.charAt(Std.int(idx));
		}
		interpError('${typeOf(container)} is not indexable', line);
		return null;
	}

	// Method binding (closes over 'self')
	function bindMethod(fn:ZepFunction, inst:ZepInstance):ZepFunction {
		var bound = new ZepFunction(fn.name, fn.args, fn.body, fn.closure.child(), fn.varNames, fn.isGenerator);
		bound.closure.define("self", inst);
		bound.native = fn.native;
		return bound;
	}

	// Function calling
	function callValue(fn:Dynamic, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>, line:Int):Dynamic {
		if (fn == null)
			interpError("Cannot call none", line);
		if (Std.isOfType(fn, ZepClass))
			return instantiate(cast fn, posArgs, namedArgs);
		if (!Std.isOfType(fn, ZepFunction))
			interpError('${valToString(fn)} is not callable', line);
		var f:ZepFunction = cast fn;
		if (f.native != null)
			return f.native(posArgs);
		if (f.isGenerator)
			return runGenerator(f, posArgs, namedArgs);
		return callFunction(f, posArgs, namedArgs);
	}

	function callFunction(f:ZepFunction, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>):Dynamic {
		var callEnv = f.closure.child();
		bindArgs(f, posArgs, namedArgs, callEnv);
		var saved = env;
		env = callEnv;
		var result:Dynamic = null;
		try {
			result = eval(f.body);
		} catch (sig:ReturnSig) {
			result = sig.v;
		}
		env = saved;
		return result;
	}

	function bindArgs(f:ZepFunction, pos:Array<Dynamic>, named:StringMap<Dynamic>, target:Env):Void {
		for (i => arg in f.args) {
			var argName = f.varNames.length > 0 ? f.varNames[arg.name] : Std.string(arg.name);
			if (argName == null)
				continue;
			var v:Dynamic = named.exists(argName) ? named.get(argName) : i < pos.length ? pos[i] : arg.opt
				&& arg.value != null ? eval(arg.value) : null;
			target.define(argName, v);
		}
	}

	// Class instantiation
	function instantiate(klass:ZepClass, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>):Dynamic {
		var inst = new ZepInstance(klass);

		// Find and call init, walking up the chain
		var k = klass;
		while (k != null) {
			if (k.methods.exists("init")) {
				var initFn = bindMethod(k.methods.get("init"), inst);
				// Provide super() as a callable that delegates to the parent's init
				if (klass.parent != null) {
					var parentClass = klass.parent;
					initFn.closure.define("super", ZepFunction.ofNative("super", args -> {
						var pk = parentClass;
						while (pk != null) {
							if (pk.methods.exists("init")) {
								callFunction(bindMethod(pk.methods.get("init"), inst), args, new StringMap());
								return null;
							}
							pk = pk.parent;
						}
						return null;
					}));
				}
				callFunction(initFn, posArgs, namedArgs);
				break;
			}
			k = k.parent;
		}
		return inst;
	}

	// Generator  (lazy fun / yield)
	//
	// Haxe has no coroutines, so we run the body to completion while routing
	// all yield statements into a collector array.  The result is a plain list
	// whose iterator the caller can use in  every x in gen()  etc.
	function runGenerator(f:ZepFunction, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>):Array<Dynamic> {
		var results:Array<Dynamic> = [];
		var prevCollector = yieldCollector;
		yieldCollector = results;

		var callEnv = f.closure.child();
		bindArgs(f, posArgs, namedArgs, callEnv);
		var saved = env;
		env = callEnv;
		try {
			eval(f.body);
		} catch (sig:ReturnSig) {}
		env = saved;
		yieldCollector = prevCollector;
		return results;
	}

	// Pattern matching
	function evalMatch(subject:Dynamic, cases:Array<SwitchCase>, def:Null<Expr>):Dynamic {
		for (c in cases) {
			var binds = new StringMap<Dynamic>();
			if (!matchPattern(c.values[0], subject, binds))
				continue;

			// Evaluate optional guard in a scope that includes pattern bindings
			if (c.guard != null) {
				var gEnv = env.child();
				for (k => v in binds)
					gEnv.define(k, v);
				var saved = env;
				env = gEnv;
				var ok = isTruthy(eval(c.guard));
				env = saved;
				if (!ok)
					continue;
			}

			var armEnv = env.child();
			for (k => v in binds)
				armEnv.define(k, v);
			var saved = env;
			env = armEnv;
			var result = eval(c.expr);
			env = saved;
			return result;
		}
		return def != null ? eval(def) : null;
	}

	/**
	 * Try to match `subject` against `pat`.
	 * Fills `binds` with any variable captures and returns true on success.
	 */
	function matchPattern(pat:Expr, subject:Dynamic, binds:StringMap<Dynamic>):Bool {
		return switch pat.expr {
			// Literal exact match
			case EConst(c): valEq(subject, evalConst(c));

			// Range match  3..10
			case ERange(from, to):
				(subject : Float) >= (eval(from) : Float) && (subject : Float) <= (eval(to) : Float);

			// Enum-variant match  Direction.North
			case EField(enumExpr, variantName): var ed = eval(enumExpr); Std.isOfType(ed,
					ZepEnumDef) && (cast ed : ZepEnumDef).variants.exists(variantName)
					&& valEq(subject, (cast ed : ZepEnumDef).variants.get(variantName));

			// Type-name pattern  int  text  float  bool  …
			case EIdent(typeName) if (isBuiltinType(typeName)):
				typeOf(subject) == typeName;

			// Variable binding  n   →  always matches, captures subject as n
			case EIdent(name):
				binds.set(name, subject);
				true;

			default: false;
		}
	}

	// Loop helpers

	/** Wraps a loop body so that  stop  terminates gracefully. */
	inline function runLoop(body:Void->Void):Void {
		try {
			body();
		} catch (_:StopSig) {}
	}

	/** Runs a single loop iteration in a child scope, absorbing  continue. */
	function runLoopBody(body:Expr):Void {
		var child = env.child();
		var saved = env;
		env = child;
		try {
			eval(body);
		} catch (_:ContinueSig) {}
		env = saved;
	}

	// Type coercion / inspection
	function castValue(v:Dynamic, type:String):Dynamic {
		return switch type {
			case "int": Std.int(v);
			case "float": (v : Float);
			case "text": valToString(v);
			case "bool": isTruthy(v);
			default: v;
		}
	}

	public function typeOf(v:Dynamic):String {
		if (v == null)
			return "none";
		// Check Int before Float — on native targets Int is a strict subtype.
		if (Std.isOfType(v, Int))
			return "int";
		if (Std.isOfType(v, Float))
			return "float";
		if (Std.isOfType(v, Bool))
			return "bool";
		if (Std.isOfType(v, String))
			return "text";
		if (Std.isOfType(v, Array))
			return "list";
		if (Std.isOfType(v, StringMap))
			return "map";
		if (Std.isOfType(v, ZepFunction))
			return "fun";
		if (Std.isOfType(v, ZepClass))
			return "class";
		if (Std.isOfType(v, ZepEnumDef))
			return "enum";
		if (Std.isOfType(v, ZepRange))
			return "range";
		if (Std.isOfType(v, ZepInstance))
			return (cast v : ZepInstance).klass.name;
		return "any";
	}

	inline function isBuiltinType(s:String):Bool
		return s == "int" || s == "float" || s == "text" || s == "bool" || s == "list" || s == "map" || s == "fun" || s == "none" || s == "any";

	// Iteration conversion
	function toIterable(v:Dynamic, line:Int):Array<Dynamic> {
		if (Std.isOfType(v, Array))
			return cast v;
		if (Std.isOfType(v, ZepRange))
			return (cast v : ZepRange).toArray();
		if (Std.isOfType(v, StringMap))
			return [for (k in (cast v : StringMap<Dynamic>).keys()) k];
		if (Std.isOfType(v, String))
			return [for (i in 0...(cast v : String).length) (cast v : String).charAt(i)];
		interpError('${typeOf(v)} is not iterable', line);
		return [];
	}

	// Built-in methods on String / Array / Map
	function builtinMethod(obj:Dynamic, name:String, line:Int):Dynamic {
		if (Std.isOfType(obj, String)) {
			var s:String = cast obj;
			return switch name {
				case "upper": ZepFunction.ofNative("upper", _ -> s.toUpperCase());
				case "lower": ZepFunction.ofNative("lower", _ -> s.toLowerCase());
				case "trim": ZepFunction.ofNative("trim", _ -> StringTools.trim(s));
				case "split": ZepFunction.ofNative("split", a -> (s.split(a[0]) : Array<Dynamic>));
				case "contains": ZepFunction.ofNative("contains", a -> StringTools.contains(s, a[0]));
				case "startsWith": ZepFunction.ofNative("startsWith", a -> StringTools.startsWith(s, a[0]));
				case "endsWith": ZepFunction.ofNative("endsWith", a -> StringTools.endsWith(s, a[0]));
				case "replace": ZepFunction.ofNative("replace", a -> StringTools.replace(s, a[0], a[1]));
				case "indexOf": ZepFunction.ofNative("indexOf", a -> s.indexOf(a[0]));
				case "repeat": ZepFunction.ofNative("repeat", a -> {
						var buf = new StringBuf();
						for (_ in 0...Std.int(a[0]))
							buf.add(s);
						buf.toString();
					});
				case "length": s.length;
				default: interpError('No method "$name" on text', line);
			}
		}

		if (Std.isOfType(obj, Array)) {
			var a:Array<Dynamic> = cast obj;
			return switch name {
				case "push": ZepFunction.ofNative("push", x -> {
						a.push(x[0]);
						null;
					});
				case "pop": ZepFunction.ofNative("pop", _ -> a.pop());
				case "first": ZepFunction.ofNative("first", _ -> a.length > 0 ? a[0] : null);
				case "last": ZepFunction.ofNative("last", _ -> a.length > 0 ? a[a.length - 1] : null);
				case "reverse": ZepFunction.ofNative("reverse", _ -> {
						var r = a.copy();
						r.reverse();
						r;
					});
				case "contains": ZepFunction.ofNative("contains", x -> a.contains(x[0]));
				case "indexOf": ZepFunction.ofNative("indexOf", x -> a.indexOf(x[0]));
				case "join": ZepFunction.ofNative("join", x -> a.map(valToString).join(x.length > 0 ? x[0] : ""));
				case "slice": ZepFunction.ofNative("slice", x -> (a.slice(Std.int(x[0]), x.length > 1 ? Std.int(x[1]) : a.length) : Array<Dynamic>));
				case "sort": ZepFunction.ofNative("sort", x -> {
						var r = a.copy();
						if (x.length > 0 && Std.isOfType(x[0], ZepFunction))
							r.sort((p, q) -> Std.int((callValue(x[0], [p, q], new StringMap(), 0) : Float)));
						else
							r.sort((p, q) -> valToString(p) < valToString(q) ? -1 : valToString(p) > valToString(q) ? 1 : 0);
						r;
					});
				case "map": ZepFunction.ofNative("map", x -> (a.map(i -> callValue(x[0], [i], new StringMap(), 0)) : Array<Dynamic>));
				case "filter": ZepFunction.ofNative("filter", x -> (a.filter(i -> isTruthy(callValue(x[0], [i], new StringMap(), 0))) : Array<Dynamic>));
				case "reduce": ZepFunction.ofNative("reduce", x -> {
						if (a.length == 0)
							return null;
						var acc = a[0];
						for (i in 1...a.length)
							acc = callValue(x[0], [acc, a[i]], new StringMap(), 0);
						acc;
					});
				case "length": a.length;
				default: interpError('No method "$name" on list', line);
			}
		}

		if (Std.isOfType(obj, StringMap)) {
			var m:StringMap<Dynamic> = cast obj;
			return switch name {
				case "keys": ZepFunction.ofNative("keys", _ -> ([for (k in m.keys()) k] : Array<Dynamic>));
				case "values": ZepFunction.ofNative("values", _ -> ([for (v in m) v] : Array<Dynamic>));
				case "exists": ZepFunction.ofNative("exists", a -> m.exists(a[0]));
				case "remove": ZepFunction.ofNative("remove", a -> {
						m.remove(a[0]);
						null;
					});
				case "length": {var n = 0; for (_ in m) n++; n;}
				default: interpError('No method "$name" on map', line);
			}
		}

		interpError('No method "$name"', line);
		return null;
	}

	// Module loading
	function loadModule(path:String, mode:EImportMode, isLazy:Bool):Void {
		var modVal:Dynamic = isLazy ? new ZepLazy(() -> resolveModule(path)) : resolveModule(path);

		switch mode {
			case INormal:
				var shortName = path.split(".").pop();
				env.setOrDefine(shortName, modVal);
			case IAlias(alias):
				env.setOrDefine(alias, modVal);
			case IPartial(items):
				var mod:Dynamic = Std.isOfType(modVal, ZepLazy) ? (cast modVal : ZepLazy).force() : modVal;
				for (item in items)
					env.setOrDefine(item, getField(mod, item, 0));
		}
	}

	function resolveModule(path:String):Dynamic {
		return switch path {
			case "math": mathModule();
			case "text": textModule();
			case "list": listModule();
			case "random": randomModule();
			case "json": jsonModule();
			case "time": timeModule();
			case "os": osModule();
			case "assert": assertModule();
			default: interpError('Unknown module "$path"', 0);
		}
	}

	// ---- Standard library modules -------------------------------------------

	function mathModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("sqrt", ZepFunction.ofNative("sqrt", a -> Math.sqrt(a[0])));
		m.set("pow", ZepFunction.ofNative("pow", a -> Math.pow(a[0], a[1])));
		m.set("abs", ZepFunction.ofNative("abs", a -> Math.abs(a[0])));
		m.set("floor", ZepFunction.ofNative("floor", a -> Math.floor(a[0])));
		m.set("ceil", ZepFunction.ofNative("ceil", a -> Math.ceil(a[0])));
		m.set("round", ZepFunction.ofNative("round", a -> Math.round(a[0])));
		m.set("min", ZepFunction.ofNative("min", a -> Math.min(a[0], a[1])));
		m.set("max", ZepFunction.ofNative("max", a -> Math.max(a[0], a[1])));
		m.set("log", ZepFunction.ofNative("log", a -> Math.log(a[0])));
		m.set("PI", Math.PI);
		m.set("E", Math.exp(1.0));
		return m;
	}

	function textModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("split", ZepFunction.ofNative("split", a -> ((a[0] : String).split(a[1]) : Array<Dynamic>)));
		m.set("join", ZepFunction.ofNative("join", a -> (a[0] : Array<Dynamic>).map(valToString).join(a[1])));
		m.set("trim", ZepFunction.ofNative("trim", a -> StringTools.trim(a[0])));
		m.set("upper", ZepFunction.ofNative("upper", a -> (a[0] : String).toUpperCase()));
		m.set("lower", ZepFunction.ofNative("lower", a -> (a[0] : String).toLowerCase()));
		m.set("replace", ZepFunction.ofNative("replace", a -> StringTools.replace(a[0], a[1], a[2])));
		m.set("contains", ZepFunction.ofNative("contains", a -> StringTools.contains(a[0], a[1])));
		m.set("startsWith", ZepFunction.ofNative("startsWith", a -> StringTools.startsWith(a[0], a[1])));
		m.set("endsWith", ZepFunction.ofNative("endsWith", a -> StringTools.endsWith(a[0], a[1])));
		return m;
	}

	function listModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("sort", ZepFunction.ofNative("sort", a -> {
			var r:Array<Dynamic> = (cast a[0] : Array<Dynamic>).copy();
			r.sort((p, q) -> valToString(p) < valToString(q) ? -1 : 1);
			r;
		}));
		m.set("filter", ZepFunction.ofNative("filter", a -> (a[0] : Array<Dynamic>).filter(x -> isTruthy(callValue(a[1], [x], new StringMap(), 0)))));
		m.set("map", ZepFunction.ofNative("map", a -> ((a[0] : Array<Dynamic>).map(x -> callValue(a[1], [x], new StringMap(), 0)) : Array<Dynamic>)));
		m.set("reduce", ZepFunction.ofNative("reduce", a -> {
			var arr:Array<Dynamic> = a[0];
			if (arr.length == 0)
				return null;
			var acc = arr[0];
			for (i in 1...arr.length)
				acc = callValue(a[1], [acc, arr[i]], new StringMap(), 0);
			acc;
		}));
		return m;
	}

	function randomModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("int", ZepFunction.ofNative("int", a -> Std.int(Math.random() * ((a[1] : Int) - (a[0] : Int))) + (a[0] : Int)));
		m.set("float", ZepFunction.ofNative("float", _ -> Math.random()));
		m.set("pick", ZepFunction.ofNative("pick", a -> {
			var arr:Array<Dynamic> = a[0];
			arr[Std.int(Math.random() * arr.length)];
		}));
		m.set("shuffle", ZepFunction.ofNative("shuffle", a -> {
			var arr:Array<Dynamic> = (cast a[0] : Array<Dynamic>).copy();
			var n = arr.length;
			while (n > 1) {
				n--;
				var k = Std.int(Math.random() * (n + 1));
				var t = arr[k];
				arr[k] = arr[n];
				arr[n] = t;
			}
			arr;
		}));
		return m;
	}

	function jsonModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("parse", ZepFunction.ofNative("parse", a -> haxe.Json.parse(a[0])));
		m.set("stringify", ZepFunction.ofNative("stringify", a -> haxe.Json.stringify(a[0])));
		return m;
	}

	function timeModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("now", ZepFunction.ofNative("now", _ -> Date.now().getTime()));
		m.set("sleep", ZepFunction.ofNative("sleep", a -> {
			Sys.sleep(a[0]);
			null;
		}));
		m.set("format", ZepFunction.ofNative("format", a -> DateTools.format(Date.fromTime(a[0]), a[1])));
		return m;
	}

	function osModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("args", (Sys.args() : Array<Dynamic>));
		m.set("env", ZepFunction.ofNative("env", a -> Sys.getEnv(a[0])));
		m.set("exit", ZepFunction.ofNative("exit", a -> {
			Sys.exit(a.length > 0 ? Std.int(a[0]) : 0);
			null;
		}));
		return m;
	}

	function assertModule():Dynamic {
		var m = new StringMap<Dynamic>();
		m.set("equal", ZepFunction.ofNative("equal", a -> {
			if (!valEq(a[0], a[1]))
				throw new ZepThrow('Expected ${valToString(a[0])} == ${valToString(a[1])}');
			null;
		}));
		m.set("notEqual", ZepFunction.ofNative("notEqual", a -> {
			if (valEq(a[0], a[1]))
				throw new ZepThrow('Expected ${valToString(a[0])} != ${valToString(a[1])}');
			null;
		}));
		m.set("true", ZepFunction.ofNative("true", a -> {
			if (!isTruthy(a[0]))
				throw new ZepThrow('Expected truthy, got ${valToString(a[0])}');
			null;
		}));
		m.set("false", ZepFunction.ofNative("false", a -> {
			if (isTruthy(a[0]))
				throw new ZepThrow('Expected falsy, got ${valToString(a[0])}');
			null;
		}));
		m.set("throws", ZepFunction.ofNative("throws", a -> {
			var threw = false;
			try
				callValue(a[0], [], new StringMap(), 0)
			catch (_:ZepThrow) {
				threw = true;
			}
			if (!threw)
				throw new ZepThrow("Expected an exception");
			null;
		}));
		return m;
	}

	// Global stdlib init
	function loadStdlib():Void {
		// say is also available as a global function (in addition to the keyword)
		globals.define("say", ZepFunction.ofNative("say", a -> {
			printFn(a.length > 0 ? valToString(a[0]) : "");
			null;
		}));
		// Type conversion
		globals.define("int", ZepFunction.ofNative("int", a -> Std.int(a[0])));
		globals.define("float", ZepFunction.ofNative("float", a -> (a[0] : Float)));
		globals.define("text", ZepFunction.ofNative("text", a -> valToString(a[0])));
		globals.define("bool", ZepFunction.ofNative("bool", a -> isTruthy(a[0])));
		// Introspection
		globals.define("type", ZepFunction.ofNative("type", a -> typeOf(a[0])));
		globals.define("len", ZepFunction.ofNative("len", a -> switch typeOf(a[0]) {
			case "text": (a[0] : String).length;
			case "list": (cast a[0] : Array<Dynamic>).length;
			case "map": {var n = 0; for (_ in (cast a[0] : StringMap<Dynamic>)) n++; n;}
			default: interpError('len() not supported on ${typeOf(a[0])}', 0);
		}));
	}

	// Test runner
	function runTest(name:String, body:Expr):Void {
		var saved = env;
		env = globals.child();
		var err:Null<String> = null;
		try {
			eval(body);
		} catch (sig:ZepThrow) {
			err = valToString(sig.v);
		} catch (e:Error) {
			err = e.toString();
		}
		env = saved;
		testResults.push({name: name, passed: err == null, error: err});
		var tag = err == null ? "PASS" : "FAIL";
		printFn('[$tag] $name${err != null ? " — " + err : ""}');
	}

	public function printTestSummary():Void {
		var pass = testResults.filter(r -> r.passed).length;
		var total = testResults.length;
		printFn('$pass / $total tests passed');
	}

	// Value helpers
	public function isTruthy(v:Dynamic):Bool {
		if (v == null)
			return false;
		if (Std.isOfType(v, Bool) && !(v : Bool))
			return false;
		if (Std.isOfType(v, Int) && (v : Int) == 0)
			return false;
		if (Std.isOfType(v, Float) && (v : Float) == 0.0)
			return false;
		if (Std.isOfType(v, String) && (v : String) == "")
			return false;
		if (Std.isOfType(v, Array) && (cast v : Array<Dynamic>).length == 0)
			return false;
		return true;
	}

	public function valEq(a:Dynamic, b:Dynamic):Bool {
		if (a == null && b == null)
			return true;
		if (a == null || b == null)
			return false;
		if (Std.isOfType(a, Array) && Std.isOfType(b, Array)) {
			var aa:Array<Dynamic> = cast a;
			var bb:Array<Dynamic> = cast b;
			if (aa.length != bb.length)
				return false;
			for (i in 0...aa.length)
				if (!valEq(aa[i], bb[i]))
					return false;
			return true;
		}
		return a == b;
	}

	public function valToString(v:Dynamic):String {
		if (v == null)
			return "none";
		if (v == true)
			return "true";
		if (v == false)
			return "false";
		if (Std.isOfType(v, ZepFunction)) {
			var f:ZepFunction = cast v;
			return f.name != null ? '<fun ${f.name}>' : '<fun>';
		}
		if (Std.isOfType(v, ZepClass))
			return '<class ${(cast v : ZepClass).name}>';
		if (Std.isOfType(v, ZepEnumDef))
			return '<enum ${(cast v : ZepEnumDef).name}>';
		if (Std.isOfType(v, ZepRange)) {
			var r:ZepRange = cast v;
			return '${r.from}..${r.to}';
		}
		if (Std.isOfType(v, ZepInstance)) {
			var inst:ZepInstance = cast v;
			// Call toString() if the class defines one
			var k = inst.klass;
			while (k != null) {
				if (k.methods.exists("toString")) {
					return callFunction(bindMethod(k.methods.get("toString"), inst), [], new StringMap());
				}
				k = k.parent;
			}
			// Otherwise serialize visible fields
			var pairs = [for (k => fv in inst.fields) '$k: ${valToString(fv)}'];
			return '${inst.klass.name}{ ${pairs.join(", ")} }';
		}
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = cast v;
			return '[${a.map(valToString).join(", ")}]';
		}
		if (Std.isOfType(v, StringMap)) {
			var m:StringMap<Dynamic> = cast v;
			var pairs = [for (k => mv in m) '$k: ${valToString(mv)}'];
			return '{ ${pairs.join(", ")} }';
		}
		return Std.string(v);
	}

	inline function evalConst(c:AstConst):Dynamic
		return switch c {
			case CInt(v): v;
			case CFloat(v): v;
			case CString(s): s;
			case CBool(v): v;
			case CNull: null;
		}

	inline function isSentinel(s:String):Bool
		return StringTools.startsWith(s, "class:")
			|| StringTools.startsWith(s, "abstract:")
			|| StringTools.startsWith(s, "interface:")
			|| StringTools.startsWith(s, "enum:")
			|| StringTools.startsWith(s, "record:")
			|| StringTools.startsWith(s, "alias:")
			|| StringTools.startsWith(s, "module:")
			|| StringTools.startsWith(s, "iface:");

	function interpError(msg:String, line:Int):Dynamic
		throw new Error(ERunError(msg), 0, 0, "", line);
}
