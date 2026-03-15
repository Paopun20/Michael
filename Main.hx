import sys.io.File;
import sys.io.FileInput;
import Sys;
import paopao.zap.Interp;
import paopao.zap.Parser;
import paopao.zap.Lexer;
import paopao.zap.Error;
import haxe.io.Path;

class Main {
	static function main() {
		var args = Sys.args();

		if (args.length == 0)
			runRepl();

		// Bare  zep <file.zep>  shorthand
		if (StringTools.endsWith(args[0], ".zep"))
			runFile(args[0], false);
		else {
			Sys.stderr().writeString('Unknown command "${args[0]}"\n');
			Sys.exit(1);
		}

		Sys.exit(0);
	}

	// File runner
	static function runFile(path:String, testMode:Bool):Void {
		if (!sys.FileSystem.exists(path)) {
			Sys.stderr().writeString('zep: file not found: $path\n');
			Sys.exit(1);
		}

		var src = File.getContent(path);
		var interp = new Interp();
		interp.printFn = s -> Sys.println(s);

		try {
			var tokens = new Lexer().tokenize(src, path);
			var parser = new Parser();
			var stmts = parser.parse(tokens, path);
			interp.run(stmts, parser.varNames);
		} catch (e:Error) {
			Sys.stderr().writeString(e.toString() + "\n");
			Sys.exit(1);
		} catch (e:Dynamic) {
			Sys.stderr().writeString('zep: uncaught error: $e\n');
			Sys.exit(1);
		}

		if (testMode) {
			interp.printTestSummary();
			var failed = interp.testResults.filter(r -> !r.passed).length;
			Sys.exit(failed > 0 ? 1 : 0);
		}
	}

	// REPL
	static function runRepl():Void {
		Sys.println("Zep - Dev Build");
		Sys.println("Type \"help\" , \"copyright\", \"credits\" or \"license\" for more information.");

		var interp = new Interp();
		interp.printFn = s -> Sys.println(s);

		// Keep a shared parser varNames table across lines so names declared
		// in one line are visible in the next.
		var varNames:paopao.zap.Ast.VariableInfo = [];

		while (true) {
			Sys.print(">>> ");
			Sys.stdout().flush();
			var line = readLine();
			line = StringTools.trim(line);
			if (line != null)
				switch (line.toLowerCase()) {
					case "help":
						Sys.println("It no help in Dev Build, sorry!");
						Sys.println("Try the online playground or check the GitHub repo for docs and examples");
						Sys.println("https://github.com/Paopun20/Zap");
					case "copyright":
						Sys.println("Copyright (c) 2023 Zap Developers");
					case "credits":
						Sys.println("Developed by the Zep Team");
					case "license":
						Sys.println("Licensed under the MIT License");
						Sys.println("https://opensource.org/licenses/MIT");
					case "exit":
						return;
					default:
						var src = line;
						while (needsContinuation(src)) {
							Sys.print("... ");
							var more = readLine();
							if (more == null)
								break;
							src += "\n" + more;
						}

						try {
							var tokens = new Lexer().tokenize(src, "<repl>");
							var parser = new Parser();
							// Seed the parser with accumulated names so prior bindings resolve
							parser.parse(tokens, "<repl>");
							// Merge any new names into the shared table
							for (n in parser.varNames)
								if (varNames.indexOf(n) == -1)
									varNames.push(n);

							var stmts = new Parser().parse(new Lexer().tokenize(src, "<repl>"), "<repl>");
							var result = interp.run(stmts, varNames);
							if (result != null)
								Sys.println("=> " + interp.valToString(result));
						} catch (e:Error) {
							Sys.println('Error: ${e.toString()}');
						} catch (e:Dynamic) {
							Sys.println('Error: $e');
						}
				}
		}
	}

	static function needsContinuation(src:String):Bool {
		var openers = ~/\b(if|unless|while|repeat|every|match|fun|class|interface|abstract|record|enum|try)\b/g;
		var closers = ~/\bend\b/g;

		var opens = 0;
		var s = src;
		while (openers.match(s)) {
			opens++;
			s = openers.matchedRight();
		}

		var closes = 0;
		s = src;
		while (closers.match(s)) {
			closes++;
			s = closers.matchedRight();
		}

		return opens > closes;
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
