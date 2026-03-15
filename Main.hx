import sys.io.File;
import sys.io.FileInput;
import Sys;
import paopao.zep.Interp;
import paopao.zep.Parser;
import paopao.zep.Lexer;
import paopao.zep.Error;
import haxe.io.Path;

class Main {
	static function main() {
		var args = Sys.args();

		if (args.length == 0) {
			printUsage();
			Sys.exit(0);
		}

		switch args[0] {
			case "repl":
				runRepl();

			case "test":
				if (args.length < 2) {
					Sys.stderr().writeString("Usage: zep test <file.zep>\n");
					Sys.exit(1);
				}
				runFile(args[1], true);

			case "run":
				if (args.length < 2) {
					Sys.stderr().writeString("Usage: zep run <file.zep>\n");
					Sys.exit(1);
				}
				runFile(args[1], false);

			default:
				// Bare  zep <file.zep>  shorthand
				if (StringTools.endsWith(args[0], ".zep"))
					runFile(args[0], false);
				else {
					Sys.stderr().writeString('Unknown command "${args[0]}"\n');
					printUsage();
					Sys.exit(1);
				}
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
		Sys.println("Zep REPL — type 'exit' or Ctrl-D to quit\n");

		var interp = new Interp();
		interp.printFn = s -> Sys.println(s);

		// Keep a shared parser varNames table across lines so names declared
		// in one line are visible in the next.
		var varNames:paopao.zep.Ast.VariableInfo = [];

		while (true) {
			Sys.print(">>> ");
			var line = readLine();
			if (line == null || line == "exit")
				break;
			line = StringTools.trim(line);
			if (line == "")
				continue;

			// Accumulate continuation lines until the input is balanced
			// (open blocks need  end  before we can evaluate).
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

		Sys.println("\nBye!");
	}

	// REPL helpers

	/**
	 * Count open block-openers vs  end  keywords to decide whether we need
	 * more input before we can evaluate.
	 * Openers: if unless while repeat every match fun class interface record enum try
	 * Closer:  end
	 */
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

	// Usage
	static function printUsage():Void {
		Sys.println("Zep ⚡ — fast, simple, readable");
		Sys.println("");
		Sys.println("Usage:");
		Sys.println("  zep <file.zep>        Run a file");
		Sys.println("  zep run <file.zep>    Run a file");
		Sys.println("  zep test <file.zep>   Run tests in a file");
		Sys.println("  zep repl              Start interactive shell");
	}
}
