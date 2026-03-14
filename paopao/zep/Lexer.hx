package paopao.zep;

import paopao.zep.Ast.ExprUnop;
import paopao.zep.Ast.ExprBinop;
import paopao.zep.Error.ErrorDef;

typedef LTokenPos = {
	var token:LToken;
	var min:Int;
	var max:Int;
	var line:Int;
}

enum LToken {}

enum LConst {
	LCInt(int:Int);
	LCFloat(float:Float);
	LCString(string:String);
	LCBool(bool:Bool);
	LCNull;
}

enum abstract LexerOp(String) from String to String {}
enum abstract LKeyword(String) from String {}
class Lexer {}
