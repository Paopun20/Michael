package paopao.mich;

import haxe.ds.StringMap;
import paopao.mich.Ast;
import paopao.mich.Error;
import paopao.mich.SimpleMacro;
import paopao.mich.michLib.*;

using StringTools;
using Lambda;

/**
 * Internal signal type used by the interpreter to implement non-local control flow
 * such as return, break, continue, throw, and yield.
 */
private class MichSignal {}

/**
 * Return from a function with the given value.
 * Caught by the function-call logic in eval(ECall) to implement return semantics
 * across nested blocks.
 */
class ReturnSig extends MichSignal {
	public var v:Dynamic;

	public function new(v:Dynamic) {
		this.v = v;
	}
}

/**
 * Signal used to break out of a loop.
 */
class StopSig extends MichSignal {
	public function new() {}
}

/**
 * Signal used to continue to the next iteration of a loop.
 */
class ContinueSig extends MichSignal {
	public function new() {}
}

/**
 * Signal used to throw an exception.
 */
class MichThrow extends MichSignal {
	public var v:Dynamic;

	public function new(v:Dynamic) {
		this.v = v;
	}
}

/**
 * Signal used to suspend execution and yield a value (generator semantics).
 */
class YieldSig extends MichSignal {
	public var v:Dynamic;

	public function new(v:Dynamic) {
		this.v = v;
	}
}

/**
 * An environment frame, mapping variable names to values. Also supports parent chaining
 */
final class Env {
	var vars:StringMap<Dynamic>;

	public var parent:Null<Env>;

	public function new(?parent:Env) {
		this.parent = parent;
		this.vars = new StringMap();
	}

	public function get(name:String):Dynamic {
		if (vars.exists(name)) {
			var v = vars.get(name);
			if (Std.isOfType(v, MichLazy)) {
				v = (cast v : MichLazy).force();
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

final class MichFunction {
	public var name:Null<String>;
	public var args:Array<Argument>;
	public var body:Null<Expr>; // null for natives
	public var closure:Env;
	public var varNames:VariableInfo;
	public var isGenerator:Bool;
	public var native:Null<Array<Dynamic>->Dynamic>;

	public function new(name:Null<String>, args:Array<Argument>, body:Null<Expr>, closure:Env, varNames:VariableInfo, isGenerator:Bool) {
		this.name = name;
		this.args = args;
		this.body = body;
		this.closure = closure;
		this.varNames = varNames;
		this.isGenerator = isGenerator;
	}

	public static function ofNative(name:String, fn:Array<Dynamic>->Dynamic):MichFunction {
		var f = new MichFunction(name, [], null, new Env(), [], false);
		f.native = fn;
		return f;
	}
}

/** A class definition — holds field defaults, methods, and static members. */
final class MichClass {
	public var name:String;
	public var parent:Null<MichClass>;
	public var interfaces:Array<String>;
	public var fieldDefaults:StringMap<Null<Dynamic>>; // declared instance fields
	public var methods:StringMap<MichFunction>;
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

/** A live object instance. Also backs the IMichCustomBehaviour contract. */
final class MichInstance implements IMichCustomBehaviour {
	public var klass:MichClass;
	public var fields:StringMap<Dynamic>;

	public function new(klass:MichClass) {
		this.klass = klass;
		this.fields = new StringMap();
		// Seed with defaults from the entire inheritance chain (child wins).
		var k = klass;
		var chain:Array<MichClass> = [];
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
			if (k.methods.exists(name)) {
				var fn:MichFunction = k.methods.get(name);
				// Bind self so method bodies can reference it.
				var bound = new MichFunction(fn.name, fn.args, fn.body, fn.closure.child(), fn.varNames, fn.isGenerator);
				bound.closure.define("self", this);
				bound.native = fn.native;
				return bound;
			}
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
final class MichEnumDef {
	public var name:String;
	public var variants:StringMap<Dynamic>;

	public function new(name:String) {
		this.name = name;
		this.variants = new StringMap();
	}
}

/** An inclusive integer range   from..to */
final class MichRange {
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
final class MichLazy {
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

/** The main interpreter class. Create a new instance for each top-level file or REPL session. */
@:analyzer(optimize, local_dce, fusion, user_var_fusion)
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
	public function run(stmts:Array<Expr>, varNames:Null<VariableInfo> = null):Dynamic {
		if (varNames != null)
			this.varNames = varNames;
		var last:Dynamic = null;
		for (s in stmts)
			last = eval(s);
		return last;
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
					case [ve, true]: new MichLazy(() -> eval(ve));
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
				var fn = new MichFunction(name, args, body, env, varNames, isLazy);
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

			case EThrow(inner): throw new MichThrow(eval(inner));

			case ETry(body, catches, always):
				var result:Dynamic = null;
				try {
					result = eval(body);
				} catch (sig:MichThrow) {
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
				new MichRange(Std.int(eval(from)), Std.int(eval(to)));

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
				if (!Std.isOfType(klass, MichClass))
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
					} catch (_:MichThrow) {
						threw = true;
					}
					if (!threw)
						throw new MichThrow("Expected an exception but none was thrown");
				} else {
					var v = eval(inner);
					if (!isTruthy(v))
						throw new MichThrow('Assertion failed: expected truthy, got ${valToString(v)}');
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

		var klass = new MichClass(name);
		klass.isAbstract = StringTools.startsWith(tag, "abstract:");
		klass.isInterface = StringTools.startsWith(tag, "interface:");

		// Resolve parent
		if (parentName != null) {
			var p = try env.get(parentName) catch (_:Dynamic) null;
			if (Std.isOfType(p, MichClass))
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
					var dv:Dynamic = defExpr == null ? null : isLazy ? new MichLazy(() -> eval(defExpr)) : eval(defExpr);
					if (isStatic)
						klass.staticFields.set(fname, dv);
					else
						klass.fieldDefaults.set(fname, dv);

				// Methods: strip the ~s~ static marker if present
				case EFunction(rawName, args, _, body, isLazy) if (rawName != null):
					var isStatic = StringTools.startsWith(rawName, "~s~");
					var mname = isStatic ? rawName.substring(3) : rawName;
					var fn = new MichFunction(mname, args, body, env, varNames, isLazy);
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
		var enumDef = new MichEnumDef(name);

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

		var ctor = MichFunction.ofNative(name, args -> {
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
		if (Std.isOfType(container, MichRange))
			return (cast container : MichRange).contains(val);
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

		// IMichCustomBehaviour (MichInstance implements this)
		if (Std.isOfType(obj, IMichCustomBehaviour))
			return (cast obj : IMichCustomBehaviour).zget(name);

		// MichInstance — but IMichCustomBehaviour already handles it above
		// MichClass — static member or enum-variant-style access
		if (Std.isOfType(obj, MichClass)) {
			var klass:MichClass = cast obj;
			if (klass.staticFields.exists(name))
				return klass.staticFields.get(name);
			if (klass.methods.exists(name))
				return klass.methods.get(name);
			interpError('No static member "$name" on class ${klass.name}', line);
		}

		// MichEnumDef  — variant access:  Direction.North
		if (Std.isOfType(obj, MichEnumDef)) {
			var ed:MichEnumDef = cast obj;
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

		// MichRange
		if (Std.isOfType(obj, MichRange))
			switch name {
				case "from":
					return (cast obj : MichRange).from;
				case "to":
					return (cast obj : MichRange).to;
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
		if (Std.isOfType(obj, IMichCustomBehaviour)) {
			(cast obj : IMichCustomBehaviour).zset(name, value);
			return;
		}
		if (Std.isOfType(obj, MichClass)) {
			(cast obj : MichClass).staticFields.set(name, value);
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
		if (Std.isOfType(container, MichRange)) {
			var r:MichRange = cast container;
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
	function bindMethod(fn:MichFunction, inst:MichInstance):MichFunction {
		var bound = new MichFunction(fn.name, fn.args, fn.body, fn.closure.child(), fn.varNames, fn.isGenerator);
		bound.closure.define("self", inst);
		bound.native = fn.native;
		return bound;
	}

	// Function calling
	function callValue(fn:Dynamic, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>, line:Int):Dynamic {
		if (fn == null)
			interpError("Cannot call none", line);
		if (Std.isOfType(fn, MichClass))
			return instantiate(cast fn, posArgs, namedArgs);
		if (!Std.isOfType(fn, MichFunction))
			interpError('${valToString(fn)} is not callable', line);
		var f:MichFunction = cast fn;
		if (f.native != null)
			return f.native(posArgs);
		if (f.isGenerator)
			return runGenerator(f, posArgs, namedArgs);
		return callFunction(f, posArgs, namedArgs);
	}

	function callFunction(f:MichFunction, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>):Dynamic {
		var callEnv = f.closure.child();
		bindArgs(f, posArgs, namedArgs, callEnv);
		var saved = env;
		env = callEnv;
		var result:Dynamic = null;
		try {
			// Evaluate block statements directly instead of going through evalBlock,
			// which would create yet another child env.
			var stmts = switch f.body.expr {
				case EBlock(exprs): exprs;
				default: [f.body];
			};
			for (s in stmts)
				result = eval(s);
		} catch (sig:ReturnSig) {
			result = sig.v;
		}
		env = saved;
		return result;
	}

	function bindArgs(f:MichFunction, pos:Array<Dynamic>, named:StringMap<Dynamic>, target:Env):Void {
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
	function instantiate(klass:MichClass, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>):Dynamic {
		var inst = new MichInstance(klass);

		// Find and call init, walking up the chain
		var k = klass;
		while (k != null) {
			if (k.methods.exists("init")) {
				var initFn = bindMethod(k.methods.get("init"), inst);
				// Provide super() as a callable that delegates to the parent's init
				if (klass.parent != null) {
					var parentClass = klass.parent;
					initFn.closure.define("super", MichFunction.ofNative("super", args -> {
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
	function runGenerator(f:MichFunction, posArgs:Array<Dynamic>, namedArgs:StringMap<Dynamic>):Array<Dynamic> {
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
					MichEnumDef) && (cast ed : MichEnumDef).variants.exists(variantName)
					&& valEq(subject, (cast ed : MichEnumDef).variants.get(variantName));

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
		if (Std.isOfType(v, MichFunction))
			return "fun";
		if (Std.isOfType(v, MichClass))
			return "class";
		if (Std.isOfType(v, MichEnumDef))
			return "enum";
		if (Std.isOfType(v, MichRange))
			return "range";
		if (Std.isOfType(v, MichInstance))
			return (cast v : MichInstance).klass.name;
		return "any";
	}

	inline function isBuiltinType(s:String):Bool
		return s == "int" || s == "float" || s == "text" || s == "bool" || s == "list" || s == "map" || s == "fun" || s == "none" || s == "any";

	// Iteration conversion
	function toIterable(v:Dynamic, line:Int):Array<Dynamic> {
		if (Std.isOfType(v, Array))
			return cast v;
		if (Std.isOfType(v, MichRange))
			return (cast v : MichRange).toArray();
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
				case "upper": MichFunction.ofNative("upper", _ -> s.toUpperCase());
				case "lower": MichFunction.ofNative("lower", _ -> s.toLowerCase());
				case "trim": MichFunction.ofNative("trim", _ -> StringTools.trim(s));
				case "split": MichFunction.ofNative("split", a -> (s.split(a[0]) : Array<Dynamic>));
				case "contains": MichFunction.ofNative("contains", a -> StringTools.contains(s, a[0]));
				case "startsWith": MichFunction.ofNative("startsWith", a -> StringTools.startsWith(s, a[0]));
				case "endsWith": MichFunction.ofNative("endsWith", a -> StringTools.endsWith(s, a[0]));
				case "replace": MichFunction.ofNative("replace", a -> StringTools.replace(s, a[0], a[1]));
				case "indexOf": MichFunction.ofNative("indexOf", a -> s.indexOf(a[0]));
				case "repeat": MichFunction.ofNative("repeat", a -> {
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
				case "push": MichFunction.ofNative("push", x -> {
						a.push(x[0]);
						null;
					});
				case "pop": MichFunction.ofNative("pop", _ -> a.pop());
				case "first": MichFunction.ofNative("first", _ -> a.length > 0 ? a[0] : null);
				case "last": MichFunction.ofNative("last", _ -> a.length > 0 ? a[a.length - 1] : null);
				case "reverse": MichFunction.ofNative("reverse", _ -> {
						var r = a.copy();
						r.reverse();
						r;
					});
				case "contains": MichFunction.ofNative("contains", x -> a.contains(x[0]));
				case "indexOf": MichFunction.ofNative("indexOf", x -> a.indexOf(x[0]));
				case "join": MichFunction.ofNative("join", x -> a.map(valToString).join(x.length > 0 ? x[0] : ""));
				case "slice": MichFunction.ofNative("slice", x -> (a.slice(Std.int(x[0]), x.length > 1 ? Std.int(x[1]) : a.length) : Array<Dynamic>));
				case "sort": MichFunction.ofNative("sort", x -> {
						var r = a.copy();
						if (x.length > 0 && Std.isOfType(x[0], MichFunction))
							r.sort((p, q) -> Std.int((callValue(x[0], [p, q], new StringMap(), 0) : Float)));
						else
							r.sort((p, q) -> valToString(p) < valToString(q) ? -1 : valToString(p) > valToString(q) ? 1 : 0);
						r;
					});
				case "map": MichFunction.ofNative("map", x -> (a.map(i -> callValue(x[0], [i], new StringMap(), 0)) : Array<Dynamic>));
				case "filter": MichFunction.ofNative("filter", x -> (a.filter(i -> isTruthy(callValue(x[0], [i], new StringMap(), 0))) : Array<Dynamic>));
				case "reduce": MichFunction.ofNative("reduce", x -> {
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
				case "keys": MichFunction.ofNative("keys", _ -> ([for (k in m.keys()) k] : Array<Dynamic>));
				case "values": MichFunction.ofNative("values", _ -> ([for (v in m) v] : Array<Dynamic>));
				case "exists": MichFunction.ofNative("exists", a -> m.exists(a[0]));
				case "remove": MichFunction.ofNative("remove", a -> {
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
		var modVal:Dynamic = isLazy ? new MichLazy(() -> resolveModule(path)) : resolveModule(path);

		switch mode {
			case INormal:
				var shortName = path.split(".").pop();
				env.setOrDefine(shortName, modVal);
			case IAlias(alias):
				env.setOrDefine(alias, modVal);
			case IPartial(items):
				var mod:Dynamic = Std.isOfType(modVal, MichLazy) ? (cast modVal : MichLazy).force() : modVal;
				for (item in items)
					env.setOrDefine(item, getField(mod, item, 0));
		}
	}

	function assertModule():Dynamic {
		var m = new StringMap<Dynamic>();

		m.set("equal", MichFunction.ofNative("equal", a -> {
			if (!valEq(a[0], a[1]))
				throw new MichThrow('Expected ${valToString(a[0])} == ${valToString(a[1])}');
			null;
		}));

		m.set("notEqual", MichFunction.ofNative("notEqual", a -> {
			if (valEq(a[0], a[1]))
				throw new MichThrow('Expected ${valToString(a[0])} != ${valToString(a[1])}');
			null;
		}));

		m.set("true", MichFunction.ofNative("true", a -> {
			if (!isTruthy(a[0]))
				throw new MichThrow('Expected truthy, got ${valToString(a[0])}');
			null;
		}));

		m.set("false", MichFunction.ofNative("false", a -> {
			if (isTruthy(a[0]))
				throw new MichThrow('Expected falsy, got ${valToString(a[0])}');
			null;
		}));

		m.set("throws", MichFunction.ofNative("throws", a -> {
			var threw = false;

			try
				callValue(a[0], [], new StringMap(), 0)
			catch (_:MichThrow)
				threw = true;

			if (!threw)
				throw new MichThrow("Expected an exception");

			null;
		}));

		return m;
	}

	// Standard of facking hardcode library modules, power by Simply Shity Macro
	function resolveModule(path:String):Dynamic {
		return switch path {
			case "math": SimpleMacro.gen(MichMath);
			case "text": SimpleMacro.gen(MichText);
			case "list": SimpleMacro.gen(MichList);
			case "random": SimpleMacro.gen(MichRandom);
			case "json": SimpleMacro.gen(MichJson);
			case "time": SimpleMacro.gen(MichTime);
			case "os": SimpleMacro.gen(MichOS);
			case "io": SimpleMacro.gen(MichIO);
			case "file": SimpleMacro.gen(MichFile);
			case "assert": assertModule(); // not a real module, just a convenient place for test assertions
			default: interpError('Unknown module "$path"', 0);
		}
	}

	// Global stdlib init
	function loadStdlib():Void {
		// say is also available as a global function (in addition to the keyword)
		globals.define("say", MichFunction.ofNative("say", a -> {
			printFn(a.length > 0 ? valToString(a[0]) : "");
			null;
		}));
		// Type conversion
		globals.define("int", MichFunction.ofNative("int", a -> Std.int(a[0])));
		globals.define("float", MichFunction.ofNative("float", a -> (a[0] : Float)));
		globals.define("text", MichFunction.ofNative("text", a -> valToString(a[0])));
		globals.define("bool", MichFunction.ofNative("bool", a -> isTruthy(a[0])));
		// Introspection
		globals.define("type", MichFunction.ofNative("type", a -> typeOf(a[0])));
		globals.define("len", MichFunction.ofNative("len", a -> switch typeOf(a[0]) {
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
		} catch (sig:MichThrow) {
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
		if (Std.isOfType(v, Bool))
			return (v : Bool) ? "true" : "false";
		if (Std.isOfType(v, MichFunction)) {
			var f:MichFunction = cast v;
			return f.name != null ? '<fun ${f.name}>' : '<fun>';
		}
		if (Std.isOfType(v, MichClass))
			return '<class ${(cast v : MichClass).name}>';
		if (Std.isOfType(v, MichEnumDef))
			return '<enum ${(cast v : MichEnumDef).name}>';
		if (Std.isOfType(v, MichRange)) {
			var r:MichRange = cast v;
			return '${r.from}..${r.to}';
		}
		if (Std.isOfType(v, MichInstance)) {
			var inst:MichInstance = cast v;
			var k = inst.klass;
			while (k != null) {
				if (k.methods.exists("toString")) {
					return callFunction(bindMethod(k.methods.get("toString"), inst), [], new StringMap());
				}
				k = k.parent;
			}
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
		return s.startsWith("class:") || s.startsWith("abstract:") || s.startsWith("interface:") || s.startsWith("enum:") || s.startsWith("record:")
			|| s.startsWith("alias:") || s.startsWith("module:") || s.startsWith("iface:");

	function interpError(msg:String, line:Int):Dynamic
		throw new Error(ERunError(msg), 0, 0, "", line);
}
