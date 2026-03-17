package paopao.mich;

import Sys;
import sys.io.File;
import sys.FileSystem;
import prismcli.CLI;
import prismcli.ParseType.FlagParseType;
import prismcli.ParseType.ArgParseType;
import paopao.mich.Interp;
import paopao.mich.Parser;
import paopao.mich.Error;

using StringTools;

class Main {
	static function args() {
		var args = Sys.args();
		var file = FileSystem.readDirectory("./");

		return args;
	}

	static function main():Void {
		var args = args();

		var cwd = args.length > 0 ? args[args.length - 1] : null;
		if (cwd != null && sys.FileSystem.exists(cwd) && sys.FileSystem.isDirectory(cwd)) {
			args = args.slice(0, args.length - 1);
			Sys.setCwd(cwd);
		}

		if (args.length == 0) {
			runRepl();
			return;
		} else if (sys.FileSystem.exists(args[0]) && !sys.FileSystem.isDirectory(args[0]) && (args[0].endsWith(".mich") )) {
			runFile(args[0], false);
			return;
		} else {
			var cli = new CLI("Michael", "Michael CLI", "0.0.1");
			cli.addDefaults();
			var runCmd = cli.addCommand("run", "Run a script file", (cli, args, flags) -> {
				var file = args["file"];
				var testMode = flags.exists("t") || flags.exists("test");
				runFile(file, testMode);
			});
			runCmd.addArgument("file", "The script file to run", String);
			runCmd.addFlag("t", "Test mode", ["-t", "--test"], None);

			cli.addCommand("repl", "Start interactive REPL", (cli, args, flags) -> {
				runRepl();
			});

			var h = cli.addCommand('help', 'Show this help message', (cli, args, flags) -> {
				cli.help();
			});
			cli.setDefaultCommand(h);
			cli.run();
		}
		Sys.exit(0);
	}

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
			Sys.stderr().writeString('Michael: uncaught error: $e\n');
			Sys.exit(1);
		}

		if (testMode) {
			interp.printTestSummary();
			var failed = interp.testResults.filter(r -> !r.passed).length;
			Sys.exit(failed > 0 ? 1 : 0);
		}
		Sys.exit(0);
	}

	static function runRepl():Void {
		Sys.println("Michael REPL - Dev Build");
		Sys.println("Type \":help\" for commands.");
		Sys.println("Type \":exit\" or press Ctrl+C to exit.");

		var cline = 0;
		var interp = new Interp();
		interp.printFn = (s:String) -> Sys.println(s);
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
						Sys.println("  :help        Show this message");
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
		var abstractSig = ~/\babstract\b.*\bfun\b/;

		for (line in src.split("\n")) {
			var t = line.trim();
			if (t == "" || t.startsWith("@"))
				continue;

			var openers = ~/\b(if|unless|while|repeat|every|match|init|class|interface|record|enum|try|test)\b/g;
			var s = t;
			while (openers.match(s)) {
				depth++;
				s = openers.matchedRight();
			}

			if (!abstractSig.match(t)) {
				var funR = ~/\bfun\b/g;
				s = t;
				while (funR.match(s)) {
					depth++;
					s = funR.matchedRight();
				}
			}

			var endR = ~/\bend\b/g;
			s = t;
			while (endR.match(s)) {
				depth--;
				s = endR.matchedRight();
			}
		}

		return depth > 0;
	}

	static function readLine():Null<String> {
		try {
			return Sys.stdin().readLine();
		} catch (_:haxe.io.Eof) {
			return null;
		}
	}
}
