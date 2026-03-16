package paopao.mich;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.ds.StringMap;

class SimpleMacro {
	public static macro function gen(cls:Expr):Expr {
		switch (cls.expr) {
			case EConst(CIdent(name)):
				var t = Context.getType(name);

				switch (t) {
					case TInst(c, _):
						var fields = c.get().statics.get();
						var sets:Array<Expr> = [];
						var clsExpr = macro $p{c.get().pack.concat([c.get().name])};

						for (f in fields) {
							switch (f.kind) {
								case FMethod(_):
									var fname = f.name;
									var t = Context.follow(f.type);
									var args:Array<Expr> = [];

									switch (t) {
										case TFun(params, _):
											for (i in 0...params.length)
												args.push(macro a[$v{i}]);
										default:
									}

									sets.push(macro m.set($v{fname}, MichFunction.ofNative($v{fname}, a -> $clsExpr.$fname($a{args}))));

								case FVar(_, _):
									var fname = f.name;

									sets.push(macro m.set($v{fname}, $clsExpr.$fname));

								default:
							}
						}

						return macro {
							var m:StringMap<Dynamic> = new StringMap();
							$b{sets};
							m;
						};

					default:
						Context.error("Not a class", cls.pos);
				}

			default:
				Context.error("Invalid", cls.pos);
		}

		return macro null;
	}

	public static macro function injectInterp():Array<Field> {
		var fields = Context.getBuildFields();

		for (field in fields) {
			if (field.meta != null) {
				for (meta in field.meta) {
					if (meta.name == ":injectinterp") {
						field.kind = FVar(macro :Interp, macro paopao.mich.Interp.CURRENT);
					}
				}
			}
		}

		return fields;
	}
}
