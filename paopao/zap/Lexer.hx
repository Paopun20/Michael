package paopao.zap;

import paopao.zap.Ast.ExprUnop;
import paopao.zap.Ast.ExprBinop;
import paopao.zap.Error.ErrorDef;

typedef LTokenPos = {
	var token:LToken;
	var min:Int;
	var max:Int;
	var line:Int;
}

enum LToken {
	TConst(c:LConst); // literal value
	TIdent(s:String); // non-keyword identifier
	TKeyword(k:LKeyword); // reserved word
	TOp(op:LexerOp); // operator
	TPOpen; // (
	TPClose; // )
	TBrOpen; // {
	TBrClose; // }
	TBkOpen; // [
	TBkClose; // ]
	TComma; // ,
	TDot; // .
	TColon; // :
	TQuestion; // ?  (standalone — nullable type annotation  int?)
	TNewline; // \n  statement separator (Zap has no semicolons)
	TEOF;
}

enum LConst {
	LCInt(v:Int);
	LCFloat(v:Float);
	LCString(s:String);
	LCBool(v:Bool);
	LCNull;
}

enum abstract LexerOp(String) from String to String {
	// Arithmetic
	var OpAdd = "+";
	var OpSub = "-";
	var OpMul = "*";
	var OpDiv = "/";
	var OpMod = "%";
	// Comparison
	var OpEq = "==";
	var OpNotEq = "!=";
	var OpLt = "<";
	var OpLte = "<=";
	var OpGt = ">";
	var OpGte = ">=";
	// Assignment
	var OpAssign = "=";
	var OpAddAssign = "+=";
	var OpSubAssign = "-=";
	var OpMulAssign = "*=";
	var OpDivAssign = "/=";
	// Increment / decrement
	var OpIncr = "++";
	var OpDecr = "--";
	// Special
	var OpArrow = "->"; // fun … -> type  /  match arm  /  value -> type cast
	var OpNullCoal = "??"; // x ?? default
	var OpPipe = "|>"; // x |> fn()
	var OpRange = ".."; // 0..10
	var OpSpread = "..."; // ...arr
	var OpOptChain = "?."; // x?.field
	var OpUnion = "|"; // int | error  (result / union type)
}

enum abstract LKeyword(String) from String to String {
	// Control flow
	var KIf = "if";
	var KElse = "else";
	var KThen = "then";
	var KUnless = "unless";
	var KMatch = "match";
	var KWhen = "when";
	var KEnd = "end";
	// Loops
	var KWhile = "while";
	var KRepeat = "repeat";
	var KTimes = "times";
	var KEvery = "every";
	var KIn = "in";
	var KStop = "stop";
	var KContinue = "continue";
	// Functions
	var KFun = "fun";
	var KGive = "give";
	var KYield = "yield";
	// Variables / declarations
	var KConst = "const";
	var KLazy = "lazy";
	var KAlias = "alias";
	// OOP
	var KClass = "class";
	var KInterface = "interface";
	var KAbstract = "abstract";
	var KStatic = "static";
	var KInit = "init";
	var KSelf = "self";
	var KSuper = "super";
	var KFrom = "from";
	var KPub = "pub";
	var KPriv = "priv";
	// Types
	var KRecord = "record";
	var KEnum = "enum";
	var KType = "type";
	// Modules
	var KUse = "use";
	var KModule = "module";
	var KAs = "as";
	// Error handling
	var KTry = "try";
	var KCatch = "catch";
	var KAlways = "always";
	var KThrow = "throw";
	// Logic (word-form operators)
	var KAnd = "and";
	var KOr = "or";
	var KNot = "not";
	var KIs = "is"; // reference equality, interface impl, type guard
	// Built-in statements
	var KSay = "say";
	var KNew = "new";
	// Literals as keywords
	var KTrue = "true";
	var KFalse = "false";
	var KNone = "none";
	// Testing
	var KTest = "test";
	var KExpect = "expect";
	var KThrows = "throws";
}

@:analyzer(optimize, local_dce, fusion, user_var_fusion)
class Lexer {
	var src:String;
	var pos:Int;
	var line:Int;
	var tokens:Array<LTokenPos>;
	var fileName:String;

	static final KEYWORDS:Map<String, LKeyword> = buildKeywordMap();

	public function new() {}

	// Entry point

	/**
	 * Tokenize `source` and return a flat array of positioned tokens.
	 * The final token is always TEOF.
	 */
	public function tokenize(source:String, ?fileName:String):Array<LTokenPos> {
		this.src = source;
		this.pos = 0;
		this.line = 1;
		this.tokens = [];
		this.fileName = fileName != null ? fileName : "";

		while (pos < src.length) {
			skipSpaces();
			if (pos >= src.length)
				break;

			var cc = at(pos);

			// Newline  (significant as statement separator)
			if (cc == 10) {
				if (shouldEmitNewline())
					push(TNewline, pos, pos + 1);
				pos++;
				line++;
				continue;
			}

			// Carriage return (Windows, ignore)
			if (cc == 13) {
				pos++;
				continue;
			}

			// Comments
			// @ line comment  or  @-- block --@
			if (cc == 64 /*@*/) {
				if (at(pos + 1) == 45 /*-*/ && at(pos + 2) == 45 /*-*/)
					skipBlockComment();
				else
					skipLineComment();
				continue;
			}

			var start = pos;

			// String literals
			if (cc == 34 /*"*/) {
				if (at(pos + 1) == 34 && at(pos + 2) == 34)
					readMultilineString(start);
				else
					readString(start);
				continue;
			}

			// Numbers
			if (isDigit(cc)) {
				readNumber(start);
				continue;
			}

			// Identifiers / keywords
			if (isIdentStart(cc)) {
				readIdent(start);
				continue;
			}

			// Symbols / operators
			readSymbol(start);
		}

		push(TEOF, pos, pos);
		return tokens;
	}

	// Whitespace / comments

	/** Skip spaces and tabs only — newlines are significant. */
	inline function skipSpaces() {
		while (pos < src.length) {
			var cc = at(pos);
			if (cc != 32 /*space*/ && cc != 9 /*tab*/)
				break;
			pos++;
		}
	}

	/** Skip everything up to (but not including) the newline. */
	function skipLineComment() {
		while (pos < src.length && at(pos) != 10)
			pos++;
	}

	/**
	 * Skip  @-- ... --@  block comment.
	 * Tracks line numbers across the comment body.
	 */
	function skipBlockComment() {
		pos += 3; // consume  @--
		while (pos < src.length) {
			var cc = at(pos);
			if (cc == 10)
				line++;
			if (cc == 45 /*-*/ && at(pos + 1) == 45 && at(pos + 2) == 64 /*@*/) {
				pos += 3; // consume  --@
				return;
			}
			pos++;
		}
		lexError("Unterminated block comment");
	}

	// String literals

	/**
	 * Regular string  "..."
	 * Backslash escapes are resolved.
	 * {interpolation} braces are kept verbatim — the parser splits them into
	 * EInterp nodes later.
	 */
	function readString(start:Int) {
		pos++; // skip opening "
		var buf = new StringBuf();
		var closed = false;
		while (pos < src.length) {
			var cc = at(pos);
			if (cc == 34 /*"*/) {
				pos++;
				closed = true;
				break;
			}
			if (cc == 10)
				lexError("Unterminated string literal");
			if (cc == 92 /*\\*/) {
				pos++; // skip backslash
				switch at(pos) {
					case 110:
						buf.addChar(10); // \n
					case 116:
						buf.addChar(9); // \t
					case 114:
						buf.addChar(13); // \r
					case 34:
						buf.addChar(34); // \"
					case 92:
						buf.addChar(92); // \\
					case 123:
						buf.addChar(123); // \{
					case c:
						buf.addChar(92);
						buf.addChar(c);
				}
				pos++;
				continue;
			}
			buf.addChar(cc);
			pos++;
		}
		if (!closed)
			lexError("Unterminated string literal");
		push(TConst(LCString(buf.toString())), start, pos);
	}

	/**
	 * Triple-quoted multiline string  """..."""
	 * No escape processing. One leading and one trailing newline are stripped.
	 */
	function readMultilineString(start:Int) {
		pos += 3; // skip opening """
		var buf = new StringBuf();
		while (pos < src.length) {
			if (at(pos) == 34 && at(pos + 1) == 34 && at(pos + 2) == 34) {
				pos += 3; // skip closing """
				break;
			}
			if (at(pos) == 10)
				line++;
			buf.addChar(at(pos));
			pos++;
		}
		var s = buf.toString();
		// strip one leading newline and one trailing newline (Zap convention)
		if (s.length > 0 && s.charCodeAt(0) == 10)
			s = s.substr(1);
		if (s.length > 0 && s.charCodeAt(s.length - 1) == 10)
			s = s.substr(0, s.length - 1);
		push(TConst(LCString(s)), start, pos);
	}

	// Numbers
	function readNumber(start:Int) {
		while (pos < src.length && isDigit(at(pos)))
			pos++;
		var isFloat = false;
		// decimal point — but not the start of  ..  range operator
		if (pos < src.length && at(pos) == 46 && isDigit(at(pos + 1))) {
			isFloat = true;
			pos++; // consume '.'
			while (pos < src.length && isDigit(at(pos)))
				pos++;
		}
		var s = src.substring(start, pos);
		push(isFloat ? TConst(LCFloat(Std.parseFloat(s))) : TConst(LCInt(Std.parseInt(s))), start, pos);
	}

	// Identifiers / keywords
	function readIdent(start:Int) {
		while (pos < src.length && isIdentPart(at(pos)))
			pos++;
		var word = src.substring(start, pos);
		var kw = KEYWORDS.get(word);
		if (kw != null) {
			// Fold literal keywords directly into TConst so the parser never
			// has to special-case  true / false / none  as keywords.
			switch kw {
				case KTrue:
					push(TConst(LCBool(true)), start, pos);
				case KFalse:
					push(TConst(LCBool(false)), start, pos);
				case KNone:
					push(TConst(LCNull), start, pos);
				default:
					push(TKeyword(kw), start, pos);
			}
		} else {
			push(TIdent(word), start, pos);
		}
	}

	// Symbols / operators
	function readSymbol(start:Int) {
		var cc = at(pos);
		var n1 = at(pos + 1);
		var n2 = at(pos + 2);

		switch cc {
			// Brackets
			case 40 /*(*/:
				pos++;
				push(TPOpen, start, pos);
			case 41 /*)*/:
				pos++;
				push(TPClose, start, pos);
			case 123 /*{*/:
				pos++;
				push(TBrOpen, start, pos);
			case 125 /*}*/:
				pos++;
				push(TBrClose, start, pos);
			case 91 /*[*/:
				pos++;
				push(TBkOpen, start, pos);
			case 93 /*]*/:
				pos++;
				push(TBkClose, start, pos);

			// Misc single-char
			case 44 /*,*/:
				pos++;
				push(TComma, start, pos);
			case 58 /*:*/:
				pos++;
				push(TColon, start, pos);

			// .  /  ..  /  ...
			case 46 /*.*/:
				if (n1 == 46 && n2 == 46) {
					pos += 3;
					push(TOp(OpSpread), start, pos);
				} else if (n1 == 46) {
					pos += 2;
					push(TOp(OpRange), start, pos);
				} else {
					pos++;
					push(TDot, start, pos);
				}

			// +  /  ++  /  +=
			case 43 /*+*/:
				if (n1 == 43) {
					pos += 2;
					push(TOp(OpIncr), start, pos);
				} else if (n1 == 61) {
					pos += 2;
					push(TOp(OpAddAssign), start, pos);
				} else {
					pos++;
					push(TOp(OpAdd), start, pos);
				}

			// -  /  --  /  -=  /  ->
			case 45 /*-*/:
				if (n1 == 62) {
					pos += 2;
					push(TOp(OpArrow), start, pos);
				} // -> first
				else if (n1 == 45) {
					pos += 2;
					push(TOp(OpDecr), start, pos);
				} else if (n1 == 61) {
					pos += 2;
					push(TOp(OpSubAssign), start, pos);
				} else {
					pos++;
					push(TOp(OpSub), start, pos);
				}

			// *  /  *=
			case 42 /***/:
				if (n1 == 61) {
					pos += 2;
					push(TOp(OpMulAssign), start, pos);
				} else {
					pos++;
					push(TOp(OpMul), start, pos);
				}

			// /  /  /=
			case 47 /*/*/:
				if (n1 == 61) {
					pos += 2;
					push(TOp(OpDivAssign), start, pos);
				} else {
					pos++;
					push(TOp(OpDiv), start, pos);
				}

			// %
			case 37 /*%*/:
				pos++;
				push(TOp(OpMod), start, pos);

			// =  /  ==
			case 61 /*=*/:
				if (n1 == 61) {
					pos += 2;
					push(TOp(OpEq), start, pos);
				} else {
					pos++;
					push(TOp(OpAssign), start, pos);
				}

			// !  /  !=
			case 33 /*!*/:
				if (n1 == 61) {
					pos += 2;
					push(TOp(OpNotEq), start, pos);
				} else
					lexError('Unexpected "!"  (did you mean  !=  or  not ?)');

			// <  /  <=
			case 60 /*<*/:
				if (n1 == 61) {
					pos += 2;
					push(TOp(OpLte), start, pos);
				} else {
					pos++;
					push(TOp(OpLt), start, pos);
				}

			// >  /  >=
			case 62 /*>*/:
				if (n1 == 61) {
					pos += 2;
					push(TOp(OpGte), start, pos);
				} else {
					pos++;
					push(TOp(OpGt), start, pos);
				}

			// ?  /  ?.  /  ??
			case 63 /*?*/:
				if (n1 == 46) {
					pos += 2;
					push(TOp(OpOptChain), start, pos);
				} else if (n1 == 63) {
					pos += 2;
					push(TOp(OpNullCoal), start, pos);
				} else {
					pos++;
					push(TQuestion, start, pos);
				}

			// |  /  |>
			case 124 /*|*/:
				if (n1 == 62) {
					pos += 2;
					push(TOp(OpPipe), start, pos);
				} else {
					pos++;
					push(TOp(OpUnion), start, pos);
				}

			default:
				lexError('Unexpected character: "${String.fromCharCode(cc)}"');
		}
	}

	function shouldEmitNewline():Bool {
		if (tokens.length == 0)
			return false;
		return switch tokens[tokens.length - 1].token {
			// Never emit a second consecutive newline
			case TNewline: false;
			// Postfix ++ and -- end a statement — emit the newline
			case TOp(OpIncr) | TOp(OpDecr): true;
			// All other operators imply the right-hand side follows
			case TOp(_): false;
			// Comma / open brackets — still inside a list or argument list
			case TComma | TPOpen | TBkOpen | TBrOpen: false;
			// Keywords that open a following expression or block
			case TKeyword(KElse) | TKeyword(KThen) | TKeyword(KAnd) | TKeyword(KOr) | TKeyword(KNot) | TKeyword(KIs) | TKeyword(KIn): false;
			// Everything else can end a statement
			default: true;
		}
	}

	// Helpers

	/** Safe char-code read — returns 0 (null byte) if out of bounds. */
	inline function at(i:Int):Int
		return i < src.length ? src.charCodeAt(i) : 0;

	inline function isDigit(cc:Int):Bool
		return cc >= 48 && cc <= 57;

	inline function isIdentStart(cc:Int):Bool
		return (cc >= 65 && cc <= 90) // A-Z
			|| (cc >= 97 && cc <= 122) // a-z
			|| cc == 95; // _

	inline function isIdentPart(cc:Int):Bool
		return isIdentStart(cc) || isDigit(cc);

	inline function push(token:LToken, min:Int, max:Int)
		tokens.push({
			token: token,
			min: min,
			max: max,
			line: line
		});

	function lexError(msg:String):Dynamic
		throw new Error(LexError(msg), pos, pos, fileName, line);

	// Static keyword table
	static function buildKeywordMap():Map<String, LKeyword> {
		return [
			// Control flow
			"if" => KIf,
			"else" => KElse,
			"then" => KThen,
			"unless" => KUnless,
			"match" => KMatch,
			"when" => KWhen,
			"end" => KEnd,
			// Loops
			"while" => KWhile,
			"repeat" => KRepeat,
			"times" => KTimes,
			"every" => KEvery,
			"in" => KIn,
			"stop" => KStop,
			"continue" => KContinue,
			// Functions
			"fun" => KFun,
			"give" => KGive,
			"yield" => KYield,
			// Variables
			"const" => KConst,
			"lazy" => KLazy,
			"alias" => KAlias,
			// OOP
			"class" => KClass,
			"interface" => KInterface,
			"abstract" => KAbstract,
			"static" => KStatic,
			"init" => KInit,
			"self" => KSelf,
			"super" => KSuper,
			"from" => KFrom,
			"pub" => KPub,
			"priv" => KPriv,
			// Types
			"record" => KRecord,
			"enum" => KEnum,
			"type" => KType,
			// Modules
			"use" => KUse,
			"module" => KModule,
			"as" => KAs,
			// Error handling
			"try" => KTry,
			"catch" => KCatch,
			"always" => KAlways,
			"throw" => KThrow,
			// Logic
			"and" => KAnd,
			"or" => KOr,
			"not" => KNot,
			"is" => KIs,
			// Built-in statements
			"say" => KSay,
			"new" => KNew,
			// Literals
			"true" => KTrue,
			"false" => KFalse,
			"none" => KNone,
			// Testing
			"test" => KTest,
			"expect" => KExpect,
			"throws" => KThrows,
		];
	}
}
