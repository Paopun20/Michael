import sys.io.File;
import sys.io.FileInput;
import Sys;
import paopao.mich.Interp;
import paopao.mich.Parser;
import paopao.mich.Error;
import haxe.io.Path;

using StringTools;

class Main {
	static function main() {
		var args = Sys.args();

		// On the cpp target Haxe appends the calling directory as the last
		// element — pop() strips it on that target while leaving file args intact.
		var fileArg = args.pop();

		// Strip leading flags before deciding what to do
		var testMode = false;
		while (args.length > 0 && args[0].startsWith("--")) {
			switch args.shift() {
				case "--test":
					testMode = true;
				case flag:
					Sys.stderr().writeString('Unknown flag "$flag"\n');
					Sys.exit(1);
			}
		}

		// Nothing left after popping and flag-stripping → REPL
		if (fileArg == null || fileArg == "") {
			runRepl();
			return;
		}

		if (true) {
			runFile(fileArg, testMode);
		} else {
			Sys.stderr().writeString('Unknown command "$fileArg"\n');
			Sys.exit(1);
		}

		Sys.exit(0);
	}

	// Load File and Run
	static function runFile(path:String, testMode:Bool):Void {
		if (!sys.FileSystem.exists(path)) {
			Sys.stderr().writeString('michael: can\'t open file: $path (No such file or directory)\n');
			Sys.exit(1);
		}

		var src = File.getContent(path);
		var interp = new Interp();
		interp.printFn = s -> Sys.println(s);

		try {
			var parser = new Parser();
			var stmts = parser.parseString(src, path);
			interp.run(stmts, parser.varNames);
		} catch (e:Error) {
			Sys.stderr().writeString(e.toString() + "\n");
			Sys.exit(1);
		} catch (e:Dynamic) {
			Sys.stderr().writeString('zap: uncaught error: $e\n');
			Sys.exit(1);
		}

		if (testMode) {
			interp.printTestSummary();
			var failed = interp.testResults.filter(r -> !r.passed).length;
			Sys.exit(failed > 0 ? 1 : 0);
		}
		Sys.exit(0);
	}

	// REPL
	static function runRepl():Void {
		Sys.println("Michael REPL - Dev Build");
		Sys.println("Type \":help\" for commands.");
		Sys.println("Type \":exit\" or press Ctrl+C to exit.");

		var cline = 0;

		var interp = new Interp();
		interp.printFn = (s:String) -> Sys.println(s);

		// Keep a shared parser varNames table across lines so names declared
		// in one line are visible in the next.
		var varNames:paopao.mich.Ast.VariableInfo = [];

		while (true) {
			Sys.print('mich:${cline + 1} > ');
			Sys.stdout().flush();
			var line = readLine();
			line = line.trim();
			if (line != null && line != "")
				switch (line.toLowerCase()) {
					case ":help":
						Sys.println("Available commands:");
						Sys.println("  :help       Show this message");
						Sys.println("  :copyright   Show copyright information");
						Sys.println("  :credits     Show credits");
						Sys.println("  :license     Show license information");
						Sys.println("  :reset       Reset REPL state");
						Sys.println("  :exit        Exit the REPL");
					case ":copyright":
						Sys.println("Copyright (c) 2026 PaoPaoDev");
					case ":credits":
						Sys.println("Developed by PaoPaoDev and contributors");
					case ":license":
						Sys.println("Licensed under the MIT License");
						Sys.println("https://opensource.org/licenses/MIT");
					case ":reset":
						interp = new Interp();
						interp.printFn = s -> Sys.println(s);
						varNames = [];
						Sys.println("REPL state reset.");
						cline = 0;
						continue;
					case ":exit":
						return;
					default:
						var src = line;
						while (needsContinuation(src)) {
							Sys.print("... ");
							Sys.stdout().flush();
							var more = readLine();
							if (more == null)
								break;
							src += "\n" + more;
						}

						try {
							var parser = new Parser();
							var stmts = parser.parseString(src, "<repl>");
							for (n in parser.varNames)
								if (varNames.indexOf(n) == -1)
									varNames.push(n);

							var result = interp.run(stmts, varNames);
							if (result != null)
								Sys.println("=> " + interp.valToString(result));
							cline += 1;
						} catch (e:Error) {
							Sys.println('Error: ${e.toString()}');
						} catch (e:Dynamic) {
							Sys.println('Error: $e');
						}
				}
		}
	}

	static function needsContinuation(src:String):Bool {
		var depth = 0;
		// Only `abstract fun name(...) -> type` has no body.
		// All other `fun` declarations open a block that needs `end`.
		var abstractSig = ~/\babstract\b.*\bfun\b/;

		for (line in src.split("\n")) {
			var t = line.trim();
			if (t == "" || t.startsWith("@"))
				continue;

			// Block openers (excluding `fun` — handled separately below)
			var openers = ~/\b(if|unless|while|repeat|every|match|init|class|interface|record|enum|try|test)\b/g;
			var s = t;
			while (openers.match(s)) {
				depth++;
				s = openers.matchedRight();
			}

			// `fun` opens a block unless the line is an abstract declaration
			if (!abstractSig.match(t)) {
				var funR = ~/\bfun\b/g;
				s = t;
				while (funR.match(s)) {
					depth++;
					s = funR.matchedRight();
				}
			}

			// `end` closes a block
			var endR = ~/\bend\b/g;
			s = t;
			while (endR.match(s)) {
				depth--;
				s = endR.matchedRight();
			}
		}

		return depth > 0;
	}

	/** Read a line from stdin; returns null on EOF. */
	static function readLine():Null<String> {
		try {
			return Sys.stdin().readLine();
		} catch (_:haxe.io.Eof) {
			return null;
		}
	}
}
