package paopao.zep;

import paopao.zep.Lexer.LToken;
import paopao.zep.Ast.ExprUnop;
import paopao.zep.Ast.ExprBinop;
import haxe.ds.Either;

class Error {
	public var e:ErrorDef;
	public var min:Int;
	public var max:Int;
	public var fileName:String;
	public var line:Int;

	public function new(e:ErrorDef, ?min:Int, ?max:Int, ?fileName:String, ?line:Int) {
		this.e = e;
		this.min = min;
		this.max = max;
		this.fileName = fileName;
		this.line = line;
	}

	public function toString():String {
		var message:String = switch( this.e ) {

		};
		return (this.fileName != null && this.fileName != "" ? (this.fileName + ":") : "") + this.line + ": " + message;
	}
}

enum ErrorDef {
    
}