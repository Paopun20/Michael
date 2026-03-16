package paopao.zap;

import paopao.zap.Ast;
import paopao.zap.Lexer;
import paopao.zap.Error;

using StringTools;

@:analyzer(optimize, local_dce, fusion, user_var_fusion)
class Parser {
	// State
	var tokens:Array<LTokenPos>;
	var pos:Int;
	var fileName:String;
	var inMatchGuard:Bool = false;
	var inInterface:Bool = false;

	/**
	 * Variable-name intern table.
	 * Indices are VariableType (Int) values — the same index scheme Argument.name uses.
	 * Make this available to the interpreter after parsing.
	 */
	public var varNames(default, null):VariableInfo;

	public function new() {}

	// Entry point

	/**
	 * Parse a flat token stream into a list of top-level statements.
	 * Access `varNames` afterwards to get the variable name table.
	 */
	public function parseString(src:String, fileName:String):Array<Expr> {
		var tokens = new Lexer().tokenize(src, fileName);
		this.tokens = tokens;
		this.pos = 0;
		this.varNames = [];
		this.fileName = fileName != null ? fileName : "";

		var stmts:Array<Expr> = [];
		skipNewlines();
		while (!check(TEOF)) {
			stmts.push(parseStmt());
			expectNewlineOrEOF();
			skipNewlines();
		}
		return stmts;
	}

	// Variable name interning  (VariableType = Int index into varNames)
	function internVar(name:String):VariableType {
		var idx = varNames.indexOf(name);
		if (idx == -1) {
			idx = varNames.length;
			varNames.push(name);
		}
		return idx;
	}

	// Block parsing

	/**
	 * Parse zero or more statements until a block-closing token is peeked.
	 * Does NOT consume the closing token.
	 */
	function parseBlock():Expr {
		var line = curLine();
		var stmts:Array<Expr> = [];
		skipNewlines();
		while (!isBlockEnd()) {
			stmts.push(parseStmt());
			expectNewlineOrEOF();
			skipNewlines();
		}
		return mk(EBlock(stmts), line);
	}

	/** Tokens that close a block without being part of it. */
	inline function isBlockEnd():Bool
		return check(TEOF) || checkKw(KEnd) || checkKw(KElse) || checkKw(KCatch) || checkKw(KAlways);

	// Statement dispatch
	function parseStmt():Expr {
		var line = curLine();
		return switch peek().token {
			case TKeyword(KIf): parseIf();
			case TKeyword(KUnless): parseUnless();
			case TKeyword(KWhile): parseWhile();
			case TKeyword(KRepeat): parseRepeat();
			case TKeyword(KEvery): parseEvery();
			case TKeyword(KMatch): parseMatch();
			case TKeyword(KFun): parseFun(false);
			case TKeyword(KGive):
				advance();
				mk(EReturn(isStmtEnd() ? null : parseExpr()), line);
			case TKeyword(KYield):
				advance();
				mk(EYield(parseExpr()), line);
			case TKeyword(KSay):
				advance();
				mk(ESay(parseExpr()), line);
			case TKeyword(KThrow):
				advance();
				mk(EThrow(parseExpr()), line);
			case TKeyword(KTry): parseTry();
			case TKeyword(KStop):
				advance();
				mk(EStop, line);
			case TKeyword(KContinue):
				advance();
				mk(EContinue, line);
			case TKeyword(KConst): parseVarDecl(false, true);
			case TKeyword(KLazy): parseLazy();
			case TKeyword(KUse): parseUse(false);
			case TKeyword(KModule): parseModuleDecl();
			case TKeyword(KClass): parseClass(false, false);
			case TKeyword(KAbstract): parseAbstract();
			case TKeyword(KInterface): parseClass(false, true);
			case TKeyword(KEnum): parseEnum();
			case TKeyword(KRecord): parseRecord();
			case TKeyword(KAlias): parseAlias();
			case TKeyword(KTest): parseTest();
			case TKeyword(KExpect): parseExpect();
			// Destructure-or-literal decided by lookahead
			case TBkOpen: parseArrayDestructOrLiteral();
			case TBrOpen: parseObjectDestructOrLiteral();
			default: parseExprStmt();
		}
	}

	// Expression-statement
	// May resolve to EVarDecl (typed), EAssign, EAssignOp, or plain expression.
	function parseExprStmt():Expr {
		var line = curLine();

		// Typed decl:  name: type [= value]
		if (checkIdent() && checkAt(1, TColon)) {
			var name = expectIdent();
			advance(); // :
			var type = parseTypeAnnot();
			var val:Null<Expr> = matchOp(OpAssign) ? parseExpr() : null;
			return mk(EVarDecl(name, type, val, false, false), line);
		}

		var e = parseExpr();

		// Simple assignment  lhs = rhs
		if (matchOp(OpAssign)) {
			return mk(EAssign(e, parseExpr()), line);
		}

		// Compound assignment  lhs += rhs  etc.
		var cop = peekCompoundAssignOp();
		if (cop != null) {
			advance();
			return mk(EAssignOp(cop, e, parseExpr()), line);
		}

		return e;
	}

	// Expression — precedence climbing
	//
	// Lowest → highest:
	//   pipeline  ??  or  and  is/is-not  ==!=  in  < <= > >=  ..  + -  * / %
	//   prefix-unary  cast->  postfix
	function parseExpr():Expr
		return parsePipeline();

	// |>
	function parsePipeline():Expr {
		var line = curLine();
		var e = parseNullCoal();
		while (matchOp(OpPipe)) {
			skipNewlines(); // allow multi-line pipeline
			e = mk(EPipeline(e, parseNullCoal()), line);
		}
		return e;
	}

	// ??
	function parseNullCoal():Expr {
		var line = curLine();
		var e = parseOr();
		while (matchOp(OpNullCoal))
			e = mk(ENullCoal(e, parseOr()), line);
		return e;
	}

	// or
	function parseOr():Expr {
		var line = curLine();
		var e = parseAnd();
		while (matchKw(KOr))
			e = mk(EBinop(OpOr, e, parseAnd()), line);
		return e;
	}

	// and
	function parseAnd():Expr {
		var line = curLine();
		var e = parseIs();
		while (matchKw(KAnd))
			e = mk(EBinop(OpAnd, e, parseIs()), line);
		return e;
	}

	// is  /  is not
	function parseIs():Expr {
		var line = curLine();
		var e = parseEquality();
		while (checkKw(KIs)) {
			advance();
			var op = matchKw(KNot) ? OpIsNot : OpIs;
			e = mk(EBinop(op, e, parseEquality()), line);
		}
		return e;
	}

	// ==  !=
	function parseEquality():Expr {
		var line = curLine();
		var e = parseIn();
		while (true) {
			if (matchOp(OpEq)) {
				e = mk(EBinop(OpEq, e, parseIn()), line);
				continue;
			}
			if (matchOp(OpNotEq)) {
				e = mk(EBinop(OpNotEq, e, parseIn()), line);
				continue;
			}
			break;
		}
		return e;
	}

	// in  (range / collection membership:  x in 0..100  /  x in list)
	function parseIn():Expr {
		var line = curLine();
		var e = parseComparison();
		if (matchKw(KIn))
			e = mk(EBinop(OpIn, e, parseComparison()), line);
		return e;
	}

	// <  <=  >  >=  — with chained comparison support:  0 < x < 100
	function parseComparison():Expr {
		var line = curLine();
		var left = parseRange();
		var op = peekCmpOp();
		if (op == null)
			return left;
		advance();
		var second = parseRange();
		// Another comparison op?  → chained
		if (peekCmpOp() != null) {
			var chain:Array<{op:ExprBinop, e:Expr}> = [{op: op, e: second}];
			while (true) {
				var nop = peekCmpOp();
				if (nop == null)
					break;
				advance();
				chain.push({op: nop, e: parseRange()});
			}
			return mk(EChainComp(left, chain), line);
		}
		return mk(EBinop(op, left, second), line);
	}

	// ..
	function parseRange():Expr {
		var line = curLine();
		var e = parseAddSub();
		if (matchOp(OpRange))
			return mk(ERange(e, parseAddSub()), line);
		return e;
	}

	// +  -
	function parseAddSub():Expr {
		var line = curLine();
		var e = parseMulDiv();
		while (true) {
			if (matchOp(OpAdd)) {
				e = mk(EBinop(OpAdd, e, parseMulDiv()), line);
				continue;
			}
			if (matchOp(OpSub)) {
				e = mk(EBinop(OpSub, e, parseMulDiv()), line);
				continue;
			}
			break;
		}
		return e;
	}

	// *  /  %
	function parseMulDiv():Expr {
		var line = curLine();
		var e = parseUnary();
		while (true) {
			if (matchOp(OpMul)) {
				e = mk(EBinop(OpMul, e, parseUnary()), line);
				continue;
			}
			if (matchOp(OpDiv)) {
				e = mk(EBinop(OpDiv, e, parseUnary()), line);
				continue;
			}
			if (matchOp(OpMod)) {
				e = mk(EBinop(OpMod, e, parseUnary()), line);
				continue;
			}
			break;
		}
		return e;
	}

	// Prefix:  not  -  ++  --
	function parseUnary():Expr {
		var line = curLine();
		if (matchKw(KNot))
			return mk(EUnop(OpNot, true, parseUnary()), line);
		if (matchOp(OpSub))
			return mk(EUnop(OpNeg, true, parseUnary()), line);
		if (matchOp(OpIncr))
			return mk(EUnop(OpIncr, true, parseUnary()), line);
		if (matchOp(OpDecr))
			return mk(EUnop(OpDecr, true, parseUnary()), line);
		return parseCast();
	}

	// Postfix cast:  expr -> TypeName
	function parseCast():Expr {
		var line = curLine();
		var e = parsePostfix();
		while (!inMatchGuard && matchOp(OpArrow))
			e = mk(ECast(e, parseTypeName()), line);
		return e;
	}

	// Postfix:  call()  .field  ?.field  [index]  ++  --
	function parsePostfix():Expr {
		var line = curLine();
		var e = parsePrimary();
		while (true) {
			switch peek().token {
				case TPOpen:
					advance();
					var args = parseCallArgs();
					expect(TPClose);
					e = mk(ECall(e, args), line);
				case TDot:
					advance();
					e = mk(EField(e, expectFieldName()), line);
				case TOp(OpOptChain):
					advance();
					e = mk(EOptField(e, expectFieldName()), line);
				case TBkOpen:
					advance();
					var idx = parseExpr();
					expect(TBkClose);
					e = mk(EArrayAccess(e, idx), line);
				case TOp(OpIncr):
					advance();
					e = mk(EUnop(OpIncr, false, e), line);
				case TOp(OpDecr):
					advance();
					e = mk(EUnop(OpDecr, false, e), line);
				default:
					break;
			}
		}
		return e;
	}

	// Primary atoms
	function parsePrimary():Expr {
		var line = curLine();
		return switch peek().token {
			case TConst(LCInt(v)):
				advance();
				mk(EConst(CInt(v)), line);
			case TConst(LCFloat(v)):
				advance();
				mk(EConst(CFloat(v)), line);
			case TConst(LCBool(v)):
				advance();
				mk(EConst(CBool(v)), line);
			case TConst(LCNull):
				advance();
				mk(EConst(CNull), line);
			case TConst(LCString(s)):
				advance();
				parseStringOrInterp(s, line);
			case TIdent(name):
				advance();
				mk(EIdent(name), line);
			case TKeyword(KSelf):
				advance();
				mk(EIdent("self"), line);
			case TKeyword(KSuper):
				advance();
				mk(EIdent("super"), line);
			case TKeyword(KFun): parseFun(false);
			// if used inline is the ternary form; block form only valid as statement
			case TKeyword(KIf): parseTernaryOrFullIf();
			case TPOpen: parseGroupOrTuple();
			case TBkOpen: parseArrayLit();
			case TBrOpen: parseObjectLit();
			case TOp(OpSpread):
				advance();
				mk(ESpread(parseUnary()), line);
			// Any keyword not claimed above treated as a variable name
			// (covers params/vars named after keywords: stop, repeat, in, type …)
			case TKeyword(k):
				advance();
				mk(EIdent((k : String)), line);
			default: parseError('Unexpected token: ${tokenStr(peek().token)}');
		}
	}

	// String interpolation
	// Strings reach here raw (lexer keeps {…} intact).
	// We split into IPStr / IPExpr parts and build EInterp, or EConst if plain.
	function parseStringOrInterp(raw:String, line:Int):Expr {
		if (raw.indexOf("{") == -1)
			return mk(EConst(CString(raw)), line);

		var parts:Array<InterpPart> = [];
		var buf = new StringBuf();
		var i = 0;

		while (i < raw.length) {
			var cc = raw.charCodeAt(i);
			if (cc == 123 /* { */) {
				if (buf.length > 0) {
					parts.push(IPStr(buf.toString()));
					buf = new StringBuf();
				}
				i++;
				var depth = 1;
				var inner = new StringBuf();
				while (i < raw.length && depth > 0) {
					var c2 = raw.charCodeAt(i);
					if (c2 == 123)
						depth++;
					else if (c2 == 125) {
						if (--depth == 0) {
							i++;
							break;
						}
					}
					inner.addChar(c2);
					i++;
				}
				// Recursively lex + parse the embedded expression
				var subParser = new Parser();
				var subStmts = subParser.parseString(inner.toString(), fileName);
				var innerExpr = subStmts.length == 1 ? subStmts[0] : mk(EBlock(subStmts), line);
				parts.push(IPExpr(innerExpr));
			} else {
				buf.addChar(cc);
				i++;
			}
		}
		if (buf.length > 0)
			parts.push(IPStr(buf.toString()));

		return switch parts {
			case [IPStr(s)]: mk(EConst(CString(s)), line);
			case [IPExpr(e)]: e;
			default: mk(EInterp(parts), line);
		}
	}

	// Collection literals
	function parseArrayLit():Expr {
		var line = curLine();
		expect(TBkOpen);
		var vals:Array<Expr> = [];
		skipNewlines();
		while (!check(TBkClose)) {
			vals.push(matchOp(OpSpread) ? mk(ESpread(parseExpr()), curLine()) : parseExpr());
			skipNewlines();
			if (!matchToken(TComma))
				break;
			skipNewlines();
		}
		expect(TBkClose);
		return mk(EArray(vals), line);
	}

	function parseObjectLit():Expr {
		var line = curLine();
		expect(TBrOpen);
		var fields:Array<ObjectField> = [];
		skipNewlines();
		while (!check(TBrClose)) {
			var name = expectIdent();
			expect(TColon);
			fields.push(new ObjectField(name, parseExpr()));
			skipNewlines();
			if (!matchToken(TComma))
				break;
			skipNewlines();
		}
		expect(TBrClose);
		return mk(EObject(fields), line);
	}

	// Grouped  (expr)  /  tuple  (a, b)
	// Multi-return tuple literals are represented as a fixed-size EArray.
	function parseGroupOrTuple():Expr {
		var line = curLine();
		expect(TPOpen);
		skipNewlines();
		var first = parseExpr();
		skipNewlines();
		if (matchToken(TComma)) {
			var elems = [first];
			skipNewlines();
			while (!check(TPClose)) {
				elems.push(parseExpr());
				skipNewlines();
				if (!matchToken(TComma))
					break;
				skipNewlines();
			}
			expect(TPClose);
			return mk(EArray(elems), line);
		}
		expect(TPClose);
		return first; // transparent grouping
	}

	// Destructuring  vs  literal  — decided by fast lookahead

	/**
	 * [a, b, c] = rhs  →  EDestructArray
	 * [1, 2, 3]        →  EArray (literal)
	 */
	function parseArrayDestructOrLiteral():Expr {
		var line = curLine();
		var savedPos = pos;
		if (looksLikeArrayDestruct()) {
			advance(); // [
			var names:Array<Null<String>> = [];
			while (!check(TBkClose)) {
				if (checkIdent("_")) {
					advance();
					names.push(null);
				} else
					names.push(expectIdent());
				if (!matchToken(TComma))
					break;
			}
			expect(TBkClose);
			expect(TOp(OpAssign));
			return mk(EDestructArray(names, parseExpr()), line);
		}
		pos = savedPos;
		return parseArrayLit();
	}

	/**
	 * { name, age } = rhs    →  EDestructObject  (no colons inside)
	 * { name: "Alice" }      →  EObject (literal)
	 */
	function parseObjectDestructOrLiteral():Expr {
		var line = curLine();
		var savedPos = pos;
		if (looksLikeObjectDestruct()) {
			advance(); // {
			skipNewlines();
			var fields:Array<String> = [];
			while (!check(TBrClose)) {
				fields.push(expectIdent());
				skipNewlines();
				if (!matchToken(TComma))
					break;
				skipNewlines();
			}
			expect(TBrClose);
			expect(TOp(OpAssign));
			return mk(EDestructObject(fields, parseExpr()), line);
		}
		pos = savedPos;
		return parseObjectLit();
	}

	// Control flow

	/** Full block form:  if cond \n body [else …] end */
	function parseIf():Expr {
		var line = curLine();
		expect(TKeyword(KIf));
		var cond = parseExpr();
		expectNewline();
		return parseIfBody(cond, line);
	}

	/**
	 * Dispatches to ternary or full block depending on  then  keyword.
	 *   if cond then a else b    →  ETernary
	 *   if cond \n body … end   →  EIf
	 */
	function parseTernaryOrFullIf():Expr {
		var line = curLine();
		expect(TKeyword(KIf));
		var cond = parseExpr();
		if (matchKw(KThen)) {
			var then = parseExpr();
			expect(TKeyword(KElse));
			return mk(ETernary(cond, then, parseExpr()), line);
		}
		expectNewline();
		return parseIfBody(cond, line);
	}

	function parseIfBody(cond:Expr, line:Int):Expr {
		var then = parseBlock();
		var els:Null<Expr> = null;
		if (matchKw(KElse)) {
			skipNewlines(); // absorb the newline after `else` before checking what follows
			if (checkKw(KIf)) {
				// else if — recurse; the recursive call handles its own end
				els = parseIf();
			} else {
				els = parseBlock();
				expect(TKeyword(KEnd));
			}
		} else {
			expect(TKeyword(KEnd));
		}
		return mk(EIf(cond, then, els), line);
	}

	function parseUnless():Expr {
		var line = curLine();
		expect(TKeyword(KUnless));
		var cond = parseExpr();
		expectNewline();
		var body = parseBlock();
		expect(TKeyword(KEnd));
		return mk(EUnless(cond, body), line);
	}

	// Loops
	function parseWhile():Expr {
		var line = curLine();
		expect(TKeyword(KWhile));
		var cond = parseExpr();
		expectNewline();
		var body = parseBlock();
		expect(TKeyword(KEnd));
		return mk(EWhile(cond, body), line);
	}

	/**
	 * repeat N times
	 * repeat N times i
	 */
	function parseRepeat():Expr {
		var line = curLine();
		expect(TKeyword(KRepeat));
		var count = parseExpr();
		expect(TKeyword(KTimes));
		var idx:Null<String> = checkIdent() ? expectIdent() : null;
		expectNewline();
		var body = parseBlock();
		expect(TKeyword(KEnd));
		return mk(ERepeat(count, idx, body), line);
	}

	/** every name in iter */
	function parseEvery():Expr {
		var line = curLine();
		expect(TKeyword(KEvery));
		var name = expectIdent();
		expect(TKeyword(KIn));
		var iter = parseExpr();
		expectNewline();
		var body = parseBlock();
		expect(TKeyword(KEnd));
		return mk(EEvery(name, iter, body), line);
	}

	// Pattern matching

	/**
	 * match expr
	 *   pattern [when guard] -> body
	 *   _                   -> body
	 * end
	 */
	function parseMatch():Expr {
		var line = curLine();
		expect(TKeyword(KMatch));
		var subject = parseExpr();
		expectNewline();
		skipNewlines();

		var cases:Array<SwitchCase> = [];
		var def:Null<Expr> = null;

		while (!checkKw(KEnd) && !check(TEOF)) {
			if (checkIdent("_")) {
				advance(); // _
				expect(TOp(OpArrow));
				def = parseMatchArm();
			} else {
				var pat = parseMatchPattern();
				var guard:Null<Expr> = null;
				if (matchKw(KWhen)) {
					inMatchGuard = true;
					guard = parseExpr();
					inMatchGuard = false;
				}
				expect(TOp(OpArrow));
				cases.push(new SwitchCase([pat], parseMatchArm(), guard));
			}
			skipNewlines();
		}
		expect(TKeyword(KEnd));
		return mk(EMatch(subject, cases, def), line);
	}

	/**
	 * A pattern is a primary optionally followed by  ..  for a range:
	 *   3..10   →  ERange
	 *   int     →  EIdent("int")  — type patterns are resolved by the interpreter
	 */
	function parseMatchPattern():Expr {
		var line = curLine();
		var e = parsePostfix();
		if (matchOp(OpRange))
			return mk(ERange(e, parsePostfix()), line);
		return e;
	}

	/**
	 * Arm body:
	 *   -> stmt    (no newline after arrow — inline)
	 *   -> \n body (newline after arrow — indented block until next pattern)
	 */
	function parseMatchArm():Expr {
		if (!isStmtEnd())
			return parseStmt();
		expectNewline();
		return parseBlock();
	}

	// Functions

	/**
	 * Named:  fun name(args) -> retType \n body \n end
	 * Lambda: fun(args) -> expr
	 */
	function parseFun(isLazy:Bool):Expr {
		var line = curLine();
		expect(TKeyword(KFun));
		var name:Null<String> = checkIdent() ? expectIdent() : null;
		expect(TPOpen);
		var args = parseFunArgs();
		expect(TPClose);

		// Interface method — consume optional return type then return, no body
		if (inInterface) {
			var ret:Null<String> = matchOp(OpArrow) ? parseFunRetType() : null;
			return mk(EFunction(name, args, ret, mk(EEmpty, line), false), line);
		}
		if (name != null) {
			// Named function:  fun name(args) -> RetType \n body end
			var ret:Null<String> = matchOp(OpArrow) ? parseFunRetType() : null;
			expectNewline();
			var body = parseBlock();
			expect(TKeyword(KEnd));
			return mk(EFunction(name, args, ret, body, isLazy), line);
		} else {
			// Anonymous lambda:  fun(args) -> expr   (-> is body, NOT return type)
			if (matchOp(OpArrow))
				return mk(EFunction(null, args, null, parseExpr(), isLazy), line);
			// Block lambda:  fun(args) \n body end
			expectNewline();
			var body = parseBlock();
			expect(TKeyword(KEnd));
			return mk(EFunction(null, args, null, body, isLazy), line);
		}
	}

	function parseFunArgs():Array<Argument> {
		var args:Array<Argument> = [];
		while (!check(TPClose)) {
			matchOp(OpSpread);
			// Parameter names may shadow keywords (stop, repeat, in, type …)
			var argName = expectFieldName();
			var typeStr:Null<String> = null;
			if (matchToken(TColon)) {
				var lazyPrefix = matchKw(KLazy) ? "lazy " : "";
				typeStr = lazyPrefix + parseTypeAnnot();
			}
			var isOpt = false;
			var defVal:Null<Expr> = null;
			if (matchOp(OpAssign)) {
				isOpt = true;
				defVal = parseExpr();
			}
			args.push(new Argument(internVar(argName), isOpt, defVal));
			if (!matchToken(TComma))
				break;
		}
		return args;
	}

	/**
	 * Return type after  ->
	 *   type          simple
	 *   (type, type)  multi-return tuple
	 */
	function parseFunRetType():String {
		if (check(TPOpen)) {
			advance();
			var types = [parseTypeName()];
			while (matchToken(TComma))
				types.push(parseTypeName());
			expect(TPClose);
			return "(" + types.join(", ") + ")";
		}
		return parseTypeAnnot();
	}

	function parseCallArgs():Array<Expr> {
		var args:Array<Expr> = [];
		skipNewlines();
		while (!check(TPClose)) {
			// Named arg:  name: value
			if (checkIdent() && checkAt(1, TColon)) {
				var n = expectIdent();
				advance(); // :
				args.push(mk(ENamedArg(n, parseExpr()), curLine()));
			} else if (matchOp(OpSpread)) {
				args.push(mk(ESpread(parseExpr()), curLine()));
			} else {
				args.push(parseExpr());
			}
			skipNewlines();
			if (!matchToken(TComma))
				break;
			skipNewlines();
		}
		return args;
	}

	// Error handling

	/**
	 * try
	 *   body
	 * catch err [: Type]
	 *   handler
	 * always
	 *   cleanup
	 * end
	 */
	function parseTry():Expr {
		var line = curLine();
		expect(TKeyword(KTry));
		expectNewline();
		var body = parseBlock();
		var catches:Array<CatchClause> = [];
		while (matchKw(KCatch)) {
			var cname = expectIdent();
			var ctype:Null<String> = matchToken(TColon) ? parseTypeName() : null;
			expectNewline();
			catches.push({name: cname, type: ctype, expr: parseBlock()});
		}
		var always:Null<Expr> = null;
		if (matchKw(KAlways)) {
			expectNewline();
			always = parseBlock();
		}
		expect(TKeyword(KEnd));
		return mk(ETry(body, catches, always), line);
	}

	// Variable declarations
	function parseVarDecl(isLazy:Bool, isConst:Bool):Expr {
		var line = curLine();
		if (isConst)
			advance(); // consume 'const'
		var name = expectIdent();
		var type:Null<String> = matchToken(TColon) ? parseTypeAnnot() : null;
		expect(TOp(OpAssign));
		return mk(EVarDecl(name, type, parseExpr(), isConst, isLazy), line);
	}

	/**
	 * lazy can precede:  use  fun  variable-name
	 */
	function parseLazy():Expr {
		var line = curLine();
		advance(); // consume 'lazy'
		if (checkKw(KUse))
			return parseUse(true);
		if (checkKw(KFun))
			return parseFun(true);
		var name = expectIdent();
		var type:Null<String> = matchToken(TColon) ? parseTypeAnnot() : null;
		expect(TOp(OpAssign));
		return mk(EVarDecl(name, type, parseExpr(), false, true), line);
	}

	// Modules

	/**
	 * use path
	 * use path { items }
	 * use path as alias
	 * lazy use path
	 */
	function parseUse(isLazy:Bool):Expr {
		var line = curLine();
		expect(TKeyword(KUse));
		var path = parseDottedPath();
		var mode:EImportMode = INormal;
		if (matchKw(KAs)) {
			mode = IAlias(expectIdent());
		} else if (check(TBrOpen)) {
			advance();
			var items:Array<String> = [];
			while (!check(TBrClose)) {
				items.push(expectIdent());
				if (!matchToken(TComma))
					break;
			}
			expect(TBrClose);
			mode = IPartial(items);
		}
		return mk(EImport(path, mode, isLazy), line);
	}

	function parseModuleDecl():Expr {
		var line = curLine();
		advance(); // module
		return mk(EIdent("module:" + parseDottedPath()), line);
	}

	// OOP declarations

	/**
	 * class Name [<T>] [from Parent] [is Interface, …]
	 *   members
	 * end
	 *
	 * Encoded as EBlock([ EIdent("class:Name"), ...members ]).
	 * The tag prefix ("class:", "interface:", "abstract:class:") lets the
	 * interpreter distinguish declaration kinds without a new ExprDef variant.
	 */
	function parseClass(isAbstract:Bool, isInterface:Bool):Expr {
		var line = curLine();
		advance(); // class | interface
		var name = expectIdent();
		parseGenericParams(); // consumed; type params not yet stored
		var parent:Null<String> = matchKw(KFrom) ? expectIdent() : null;
		var ifaces:Array<String> = [];
		if (matchKw(KIs)) {
			ifaces.push(expectIdent());
			while (matchToken(TComma))
				ifaces.push(expectIdent());
		}
		expectNewline();
		var savedInterface = inInterface;
		inInterface = isInterface;
		var members = parseClassBody();
		inInterface = savedInterface;
		expect(TKeyword(KEnd));
		var tag = isInterface ? "interface" : isAbstract ? "abstract:class" : "class";
		// Encode optional parent after "|":  "class:Cat|Animal"
		var qualName = parent != null ? '$name|$parent' : name;
		var header = mk(EIdent('$tag:$qualName'), line);
		// Encode implemented interfaces as sentinel nodes right after the header
		var ifaceNodes = [for (i in ifaces) mk(EIdent('iface:$i'), line)];
		var nodes:Array<Expr> = [header];
		nodes = nodes.concat(ifaceNodes).concat(members);
		return mk(EBlock(nodes), line);
	}

	function parseAbstract():Expr {
		advance(); // abstract
		if (checkKw(KClass))
			return parseClass(true, false);
		if (checkKw(KFun))
			return parseFun(false); // abstract fun inside class body
		return parseError("Expected 'class' or 'fun' after 'abstract'");
	}

	function parseClassBody():Array<Expr> {
		var members:Array<Expr> = [];
		skipNewlines();
		while (!checkKw(KEnd) && !check(TEOF)) {
			members.push(parseClassMember());
			expectNewlineOrEOF();
			skipNewlines();
		}
		return members;
	}

	function parseClassMember():Expr {
		var line = curLine();
		var _pub = matchKw(KPub);
		var _priv = !_pub && matchKw(KPriv);
		var _static = matchKw(KStatic);
		var _abstract = matchKw(KAbstract);
		var isLazy = matchKw(KLazy);
		if (checkKw(KFun)) {
			var fn = parseFun(isLazy);
			// Prefix name with "~s~" so the interpreter can route to staticFields
			if (_static)
				switch fn.expr {
					case EFunction(n, a, r, b, lz):
						return mk(EFunction(n != null ? "~s~" + n : "~s~", a, r, b, lz), fn.line);
					default:
				}
			return fn;
		}
		if (checkKw(KInit))
			return parseInit();
		// Field:  name: type [= default]
		var name = (_static ? "~s~" : "") + expectIdent();
		expect(TColon);
		var type = parseTypeAnnot();
		var value:Null<Expr> = matchOp(OpAssign) ? parseExpr() : null;
		return mk(EVarDecl(name, type, value, false, isLazy), line);
	}

	function parseInit():Expr {
		var line = curLine();
		advance(); // init
		expect(TPOpen);
		var args = parseFunArgs();
		expect(TPClose);
		expectNewline();
		var body = parseBlock();
		expect(TKeyword(KEnd));
		return mk(EFunction("init", args, null, body, false), line);
	}

	// Enum / Record / Alias

	/**
	 * enum Name
	 *   Variant [= value]
	 * end
	 */
	function parseEnum():Expr {
		var line = curLine();
		advance(); // enum
		var name = expectIdent();
		expectNewline();
		skipNewlines();
		var variants:Array<Expr> = [];
		while (!checkKw(KEnd)) {
			var vline = curLine();
			var vname = expectIdent();
			var vval = matchOp(OpAssign) ? parseExpr() : null;
			variants.push(vval != null ? mk(EAssign(mk(EIdent(vname), vline), vval), vline) : mk(EIdent(vname), vline));
			skipNewlines();
			matchToken(TComma); // optional trailing comma between variants
			skipNewlines();
		}
		expect(TKeyword(KEnd));
		var nodes:Array<Expr> = [mk(EIdent("enum:" + name), line)];
		nodes = nodes.concat(variants);
		return mk(EBlock(nodes), line);
	}

	/**
	 * record Name
	 *   field: type
	 * end
	 */
	function parseRecord():Expr {
		var line = curLine();
		advance(); // record
		var name = expectIdent();
		expectNewline();
		skipNewlines();
		var fields:Array<Expr> = [];
		while (!checkKw(KEnd)) {
			var fline = curLine();
			var fname = expectIdent();
			expect(TColon);
			fields.push(mk(EVarDecl(fname, parseTypeAnnot(), null, false, false), fline));
			expectNewlineOrEOF();
			skipNewlines();
		}
		expect(TKeyword(KEnd));
		var nodes:Array<Expr> = [mk(EIdent("record:" + name), line)];
		nodes = nodes.concat(fields);
		return mk(EBlock(nodes), line);
	}

	/** alias ID = int */
	function parseAlias():Expr {
		var line = curLine();
		advance(); // alias
		var name = expectIdent();
		expect(TOp(OpAssign));
		return mk(EIdent("alias:" + name + "=" + parseTypeName()), line);
	}

	// Testing

	/**
	 * test "label"
	 *   body
	 * end
	 */
	function parseTest():Expr {
		var line = curLine();
		advance(); // test
		var name = expectString();
		expectNewline();
		var body = parseBlock();
		expect(TKeyword(KEnd));
		return mk(ETest(name, body), line);
	}

	/**
	 * expect expr
	 * expect throws
	 *   body
	 * end
	 */
	function parseExpect():Expr {
		var line = curLine();
		advance(); // expect
		if (matchKw(KThrows)) {
			expectNewline();
			var body = parseBlock();
			expect(TKeyword(KEnd));
			return mk(EExpect(body, true), line);
		}
		return mk(EExpect(parseExpr(), false), line);
	}

	// Type annotations

	/** Parses a type name then optionally  ?  for nullable:  int?  list<text>? */
	function parseTypeAnnot():String {
		var t = parseTypeName();
		return check(TQuestion) ? (advance() != null ? t + "?" : t) : t;
	}

	/**
	 * Parses a type expression:
	 *   int
	 *   list<int>
	 *   int | error   (result / union — | is a single-pipe OpUnion token)
	 */
	function parseTypeName():String {
		// `none`, `true`, `false` are folded to TConst by the lexer but are
		// valid type names in annotations (-> none, bool?, etc.)
		switch peek().token {
			case TConst(LCNull):
				advance();
				return "none";
			case TConst(LCBool(_)):
				advance();
				return "bool";
			default:
		}
		var name = expectIdent();
		// Generic param  <T>
		if (checkOp(OpLt)) {
			advance();
			var inner = parseTypeName();
			expectOp(OpGt);
			name = '$name<$inner>';
		}
		// Union / result type  T | error
		if (checkOp(OpUnion)) {
			advance();
			name = '$name | ${parseTypeName()}';
		}
		return name;
	}

	/** net.http  →  "net.http" */
	function parseDottedPath():String {
		var buf = new StringBuf();
		buf.add(expectIdent());
		while (check(TDot)) {
			advance();
			buf.add(".");
			buf.add(expectIdent());
		}
		return buf.toString();
	}

	/** <T>  or  <K, V> — returns param names (not yet used in nodes) */
	function parseGenericParams():Array<String> {
		if (!checkOp(OpLt))
			return [];
		advance(); // <
		var p = [expectIdent()];
		while (matchToken(TComma))
			p.push(expectIdent());
		expectOp(OpGt);
		return p;
	}

	// Destructuring look-ahead

	/**
	 * Lookahead to decide if  [ ident, … ]  is followed by  =
	 * Pattern:  TBkOpen (TIdent TComma?)* TBkClose TOp(OpAssign)
	 */
	function looksLikeArrayDestruct():Bool {
		if (!check(TBkOpen))
			return false;
		var i = pos + 1;
		while (i < tokens.length) {
			switch tokens[i].token {
				case TIdent(_) | TComma:
					i++;
				case TBkClose:
					return (i + 1) < tokens.length && switch tokens[i + 1].token {
						case TOp(OpAssign): true;
						default: false;
					};
				default:
					return false;
			}
		}
		return false;
	}

	/**
	 * Lookahead to decide if  { ident, … }  (no colons) is followed by  =
	 * A colon inside means  key: value  (object literal), not destructuring.
	 */
	function looksLikeObjectDestruct():Bool {
		if (!check(TBrOpen))
			return false;
		var i = pos + 1;
		while (i < tokens.length && tokens[i].token == TNewline)
			i++; // skip leading nl
		while (i < tokens.length) {
			switch tokens[i].token {
				case TIdent(_) | TComma | TNewline:
					i++;
				case TBrClose:
					var j = i + 1;
					while (j < tokens.length && tokens[j].token == TNewline)
						j++;
					return j < tokens.length && switch tokens[j].token {
						case TOp(OpAssign): true;
						default: false;
					};
				case TColon:
					return false; // key: val → object literal
				default:
					return false;
			}
		}
		return false;
	}

	// Token stream primitives
	inline function peek(?offset:Int = 0):LTokenPos
		return tokens[pos + offset];

	inline function advance():LTokenPos
		return tokens[pos++];

	inline function curLine():Int
		return tokens[pos].line;

	/** True when the current position is a natural statement boundary. */
	inline function isStmtEnd():Bool
		return check(TNewline) || check(TEOF);

	function check(t:LToken):Bool
		return tokEq(peek().token, t);

	function checkAt(offset:Int, t:LToken):Bool
		return (pos + offset) < tokens.length && tokEq(tokens[pos + offset].token, t);

	function checkIdent(?name:String):Bool
		return switch peek().token {
			case TIdent(s): name == null || s == name;
			default: false;
		}

	function checkKw(k:LKeyword):Bool
		return switch peek().token {
			case TKeyword(kk): (kk : String) == (k : String);
			default: false;
		}

	function checkOp(op:LexerOp):Bool
		return switch peek().token {
			case TOp(o): (o : String) == (op : String);
			default: false;
		}

	function matchToken(t:LToken):Bool {
		if (tokEq(peek().token, t)) {
			advance();
			return true;
		}
		return false;
	}

	function matchKw(k:LKeyword):Bool {
		if (checkKw(k)) {
			advance();
			return true;
		}
		return false;
	}

	function matchOp(op:LexerOp):Bool {
		if (checkOp(op)) {
			advance();
			return true;
		}
		return false;
	}

	function skipNewlines()
		while (check(TNewline))
			advance();

	function expectNewline() {
		if (!matchToken(TNewline))
			parseError('Expected newline, got ${tokenStr(peek().token)}');
	}

	function expectNewlineOrEOF() {
		if (!check(TEOF) && !matchToken(TNewline))
			parseError('Expected newline or EOF, got ${tokenStr(peek().token)}');
	}

	function expect(t:LToken):LTokenPos {
		if (!tokEq(peek().token, t))
			parseError('Expected ${tokenStr(t)}, got ${tokenStr(peek().token)}');
		return advance();
	}

	function expectOp(op:LexerOp) {
		if (!matchOp(op))
			parseError('Expected "${(op : String)}", got ${tokenStr(peek().token)}');
	}

	function expectIdent(?name:String):String
		return switch peek().token {
			case TIdent(s):
				if (name != null && s != name)
					parseError('Expected "$name", got "$s"');
				advance();
				s;
			default:
				parseError('Expected identifier, got ${tokenStr(peek().token)}');
		}

	/** Accepts both TIdent and TKeyword as a name — used for field access and
	 *  parameter names where keywords are valid (repeat, stop, type, in …). */
	function expectFieldName():String
		return switch peek().token {
			case TIdent(s):
				advance();
				s;
			case TKeyword(k):
				advance();
				(k : String);
			default: parseError('Expected field name, got ${tokenStr(peek().token)}');
		}

	function expectString():String
		return switch peek().token {
			case TConst(LCString(s)):
				advance();
				s;
			default: parseError('Expected string, got ${tokenStr(peek().token)}');
		}

	// Peek compound assignment op:  +=  -=  *=  /=
	function peekCompoundAssignOp():Null<ExprBinop>
		return switch peek().token {
			case TOp(OpAddAssign): OpAdd;
			case TOp(OpSubAssign): OpSub;
			case TOp(OpMulAssign): OpMul;
			case TOp(OpDivAssign): OpDiv;
			default: null;
		}

	// Peek comparison op:  <  <=  >  >=
	function peekCmpOp():Null<ExprBinop>
		return switch peek().token {
			case TOp(OpLt): OpLt;
			case TOp(OpLte): OpLte;
			case TOp(OpGt): OpGt;
			case TOp(OpGte): OpGte;
			default: null;
		}

	// Structural token equality (enum tags + payloads)
	function tokEq(a:LToken, b:LToken):Bool
		return switch [a, b] {
			case [TConst(ca), TConst(cb)]: constEq(ca, cb);
			case [TIdent(sa), TIdent(sb)]: sa == sb;
			case [TKeyword(ka), TKeyword(kb)]: (ka : String) == (kb : String);
			case [TOp(oa), TOp(ob)]: (oa : String) == (ob : String);
			case [TPOpen, TPOpen]: true;
			case [TPClose, TPClose]: true;
			case [TBrOpen, TBrOpen]: true;
			case [TBrClose, TBrClose]: true;
			case [TBkOpen, TBkOpen]: true;
			case [TBkClose, TBkClose]: true;
			case [TComma, TComma]: true;
			case [TDot, TDot]: true;
			case [TColon, TColon]: true;
			case [TQuestion, TQuestion]: true;
			case [TNewline, TNewline]: true;
			case [TEOF, TEOF]: true;
			default: false;
		}

	function constEq(a:LConst, b:LConst):Bool
		return switch [a, b] {
			case [LCInt(x), LCInt(y)]: x == y;
			case [LCFloat(x), LCFloat(y)]: x == y;
			case [LCString(x), LCString(y)]: x == y;
			case [LCBool(x), LCBool(y)]: x == y;
			case [LCNull, LCNull]: true;
			default: false;
		}

	function tokenStr(t:LToken):String
		return switch t {
			case TConst(LCInt(v)): 'int($v)';
			case TConst(LCFloat(v)): 'float($v)';
			case TConst(LCString(s)): '"$s"';
			case TConst(LCBool(v)): Std.string(v);
			case TConst(LCNull): 'none';
			case TIdent(s): 'identifier "$s"';
			case TKeyword(k): '"${(k : String)}"';
			case TOp(op): '"${(op : String)}"';
			case TPOpen: '"("';
			case TPClose: '")"';
			case TBrOpen: '"{"';
			case TBrClose: '"}"';
			case TBkOpen: '"["';
			case TBkClose: '"]"';
			case TComma: '","';
			case TDot: '"."';
			case TColon: '":"';
			case TQuestion: '"?"';
			case TNewline: 'newline';
			case TEOF: 'end of file';
		}

	// AST node factory

	/** Creates a concrete Expr node. Uses ExprNode (see bottom of file). */
	inline function mk(def:ExprDef, line:Int):Expr
		return new ExprNode(def, line);

	// Error
	function parseError(msg:String):Dynamic {
		var t = peek();
		throw new Error(ParseError(msg), t.min, t.max, fileName, t.line);
	}
}

// Concrete Expr subclass
// Expr is declared `abstract class` — ExprNode is the single concrete impl.
private class ExprNode extends Expr {
	public function new(def:ExprDef, line:Int)
		super(def, line);
}
