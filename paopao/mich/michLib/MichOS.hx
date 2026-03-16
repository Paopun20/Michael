package paopao.mich.michLib;

class MichOS {
	public static function name():String
		return Sys.systemName();

	public static function cwd():String
		return Sys.getCwd();

	public static function setCwd(path:String):Bool {
		Sys.setCwd(path);
		return true;
	}

	public static function env(name:String):String
		return Sys.getEnv(name);

	public static function args():Array<String>
		return Sys.args();

	public static function command(cmd:String, args:Null<Array<String>>):Int
		return Sys.command(cmd, args == null ? [] : args);

	public static function exit(code:Int):Bool {
		Sys.exit(code);
		return true;
	}
}
