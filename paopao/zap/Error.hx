package paopao.zap;

import paopao.zap.Lexer.LToken;
import paopao.zap.Ast.ExprUnop;
import paopao.zap.Ast.ExprBinop;
import haxe.ds.Either;

enum ErrorDef {
	UnexpectedToken(token:LToken);
	UnexpectedEOF;
	InvalidNumberFormat(numStr:String);
	InvalidStringEscape(escSeq:String);
	UnterminatedString;
	UnknownOperator(opStr:String);
	InvalidIdentifier(idStr:String);
	TypeError(expected:String, actual:String);
	UndefinedVariable(name:String);
	UndefinedFunction(name:String);
	UndefinedField(name:String);
	Redefinition(name:String);
	MissingField(name:String);
	InvalidAssignmentTarget;
	LexError(msg:String);
	ParseError(msg:String);
	ERunError(msg:String);
	Other(msg:String);
}

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
		var message:String = switch (this.e) {
			case UnexpectedToken(token): "Unexpected token: " + token;
			case UnexpectedEOF: "Unexpected end of file";
			case InvalidNumberFormat(numStr): "Invalid number format: " + numStr;
			case InvalidStringEscape(escSeq): "Invalid string escape sequence: " + escSeq;
			case UnterminatedString: "Unterminated string";
			case UnknownOperator(opStr): "Unknown operator: " + opStr;
			case InvalidIdentifier(idStr): "Invalid identifier: " + idStr;
			case TypeError(expected, actual): "Type error: expected " + expected + ", got " + actual;
			case UndefinedVariable(name): "Undefined variable: " + name;
			case UndefinedFunction(name): "Undefined function: " + name;
			case UndefinedField(name): "Undefined field: " + name;
			case Redefinition(name): "Redefinition of: " + name;
			case MissingField(name): "Missing field: " + name;
			case InvalidAssignmentTarget: "Invalid assignment target";
			case LexError(msg): "Lexing error: " + msg;
			case ParseError(msg): "Parsing error: " + msg;
			case ERunError(msg): "Runtime error: " + msg;
			case Other(msg): msg;
		};
		return (this.fileName != null && this.fileName != "" ? (this.fileName + ":") : "") + this.line + ": " + message;
	}
}
