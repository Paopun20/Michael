package paopao.zep;

abstract class Expr {
	public var expr:ExprDef;
	public var line:Int;

	public function new(expr:ExprDef, line:Int) {
		this.expr = expr;
		this.line = line;
	}
}

enum ExprDef {
	EEmpty;
}

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
	public var values:Array<Expr>;
	public var expr:Expr;

	public function new(values:Array<Expr>, expr:Expr) {
		this.values = values;
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

/**
 * https://haxe.org/manual/expression-operators-binops.html
 */
enum abstract ExprBinop(Int) {}

/**
 * https://haxe.org/manual/expression-operators-unops.html
 */
enum abstract ExprUnop(Int) {}

enum EImportMode {}
typedef VariableType = Int;
typedef VariableInfo = Array<String>;

interface IZepCustomBehaviour {
	public function zset(name:String, value:Dynamic):Dynamic;
	public function zget(name:String):Dynamic;
}
