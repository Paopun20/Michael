package paopao.zap;

abstract class Expr {
	public var expr:ExprDef;
	public var line:Int;

	public function new(expr:ExprDef, line:Int) {
		this.expr = expr;
		this.line = line;
	}
}

// Literal constants
// Defined here (not in Lexer) to avoid a circular import, since Lexer already
// imports ExprBinop / ExprUnop from Ast.
enum AstConst {
	CInt(v:Int);
	CFloat(v:Float);
	CString(s:String);
	CBool(v:Bool);
	CNull;
}

// String interpolation  "Hello {name}!"
enum InterpPart {
	IPStr(s:String); // plain text segment
	IPExpr(e:Expr); // embedded {expression}
}

// Supporting structures
class Argument {
	public var name:VariableType;
	public var opt:Bool;
	public var value:Expr;

	public function new(name:VariableType, opt:Bool = false, ?value:Expr) {
		this.name = name;
		this.opt = opt;
		this.value = value;
	}
}

class SwitchCase {
	public var values:Array<Expr>; // patterns; empty = wildcard (_)
	public var guard:Null<Expr>; // optional `when` guard
	public var expr:Expr;

	public function new(values:Array<Expr>, expr:Expr, ?guard:Expr) {
		this.values = values;
		this.guard = guard;
		this.expr = expr;
	}
}

class ObjectField {
	public var name:String;
	public var expr:Expr;

	public function new(name:String, expr:Expr) {
		this.name = name;
		this.expr = expr;
	}
}

typedef CatchClause = {
	var name:String; // bound variable  (catch err)
	var type:Null<String>; // optional type   (catch err: NetworkError)
	var expr:Expr; // handler body
}

// Binary operators

/**
 * https://haxe.org/manual/expression-operators-binops.html
 */
enum abstract ExprBinop(Int) from Int to Int {
	var OpAdd = 0; //  +
	var OpSub = 1; //  -
	var OpMul = 2; //  *
	var OpDiv = 3; //  /
	var OpMod = 4; //  %
	var OpEq = 5; //  ==
	var OpNotEq = 6; //  !=
	var OpLt = 7; //  <
	var OpLte = 8; //  <=
	var OpGt = 9; //  >
	var OpGte = 10; //  >=
	var OpAnd = 11; //  and
	var OpOr = 12; //  or
	var OpIs = 13; //  is   (reference equality)
	var OpIsNot = 14; //  is not
	var OpIn = 15; //  in   (range / collection membership:  x in 0..100)
}

// Unary operators

/**
 * https://haxe.org/manual/expression-operators-unops.html
 */
enum abstract ExprUnop(Int) from Int to Int {
	var OpNot = 0; // not x
	var OpNeg = 1; // -x
	var OpIncr = 2; // x++  /  ++x
	var OpDecr = 3; // x--  /  --x
}

// Import modes
enum EImportMode {
	INormal; // use math
	IPartial(items:Array<String>); // use math { sqrt, pow }
	IAlias(alias:String); // use net.http as http
}

// Expression definitions
enum ExprDef {
	// Noop / placeholder
	EEmpty;

	// Literals
	EConst(c:AstConst); // 42, 3.14, "hi", true, none

	// Identifiers
	EIdent(name:String); // variable / name reference

	// Declarations
	EVarDecl(name:String, type:Null<String>, // optional type annotation  x: int
		value:Null<Expr>, // optional initialiser
		isConst:Bool, // const MAX = 100
		isLazy:Bool // lazy expensive = ...
	);

	// Arithmetic / logic / comparison
	EBinop(op:ExprBinop, e1:Expr, e2:Expr); // a + b, a == b, a and b …
	EUnop(op:ExprUnop, prefix:Bool, e:Expr); // not x, -x, x++, ++x …
	EAssign(e1:Expr, e2:Expr); // x = value
	EAssignOp(op:ExprBinop, e1:Expr, e2:Expr); // x += 1, x -= 2 …

	// Chained comparison  0 < x < 100
	// Each entry is (operator, right-hand operand); the left of the first
	// pair is the leading expression stored outside the array.
	EChainComp(left:Expr, chain:Array<{op:ExprBinop, e:Expr}>);

	// Member / index access
	EField(e:Expr, name:String); // obj.field
	EOptField(e:Expr, name:String); // obj?.field
	EArrayAccess(e:Expr, index:Expr); // arr[i]
	ESpread(e:Expr); // ...arr

	// Collections
	EArray(values:Array<Expr>); // [1, 2, 3]
	EObject(fields:Array<ObjectField>); // { name: "Alice" }

	// Strings
	EInterp(parts:Array<InterpPart>); // "Hello {name}!"

	// Functions
	EFunction(name:Null<String>, args:Array<Argument>, ret:Null<String>, // return type annotation
		body:Expr, isLazy:Bool // lazy fun / generator
	);
	ECall(e:Expr, args:Array<Expr>); // fn(a, b)
	ENamedArg(name:String, value:Expr); // fn(name: value)
	EReturn(e:Null<Expr>); // give [value]
	EYield(e:Expr); // yield value  (generators)

	// Blocks
	EBlock(exprs:Array<Expr>);

	// Control flow
	EIf(cond:Expr, then:Expr, els:Null<Expr>); // if / else if / else
	EUnless(cond:Expr, body:Expr); // unless cond (sugar for if not)
	ETernary(cond:Expr, then:Expr, els:Expr); // if x then a else b

	// Pattern matching
	EMatch(e:Expr, cases:Array<SwitchCase>, def:Null<Expr>); // match x … end

	// Loops
	EWhile(cond:Expr, body:Expr); // while cond
	ERepeat(count:Expr, index:Null<String>, body:Expr); // repeat N times [i]
	EEvery(name:String, iter:Expr, body:Expr); // every x in iter
	EStop; // stop  (break)
	EContinue;

	// Error handling
	EThrow(e:Expr);
	ETry(body:Expr, catches:Array<CatchClause>, always:Null<Expr>);

	// Type ops
	ECast(e:Expr, type:String); // value -> type
	ETypeMatch(type:String); // type pattern inside match

	// Null safety
	ENullCoal(e:Expr, def:Expr); // x ?? default

	// Range
	ERange(from:Expr, to:Expr); // 0..10

	// Pipeline
	EPipeline(e:Expr, fn:Expr); // x |> fn()

	// Built-in keywords
	ESay(e:Expr); // say value
	ENew(type:String, args:Array<Expr>); // Dog("Rex")
	EImport(path:String, mode:EImportMode, isLazy:Bool);

	// Destructuring
	EDestructArray(names:Array<Null<String>>, e:Expr); // [a, b, c] = ...
	EDestructObject(fields:Array<String>, e:Expr); // { name, age } = ...

	// Testing
	ETest(name:String, body:Expr); // test "label" … end
	EExpect(e:Expr, throws:Bool); // expect expr / expect throws
}

typedef VariableType = Int;
typedef VariableInfo = Array<String>;

interface IZepCustomBehaviour {
	public function zset(name:String, value:Dynamic):Dynamic;
	public function zget(name:String):Dynamic;
}
