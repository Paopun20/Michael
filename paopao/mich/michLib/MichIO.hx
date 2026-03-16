package paopao.mich.michLib;

class MichIO {
	public static function print(v:Dynamic):Null<Dynamic> {
		Sys.print(Std.string(v));
		return null;
	}

	public static function println(v:Dynamic):Null<Dynamic> {
		Sys.println(Std.string(v));
		return null;
	}

	public static function error(v:Dynamic):Null<Dynamic> {
		Sys.stderr().writeString(Std.string(v) + "\n");
		return null;
	}

	public static function readLine():String {
		return Sys.stdin().readLine();
	}

	public static function readInt():Int {
		return Std.parseInt(Sys.stdin().readLine());
	}

	public static function readFloat():Float {
		return Std.parseFloat(Sys.stdin().readLine());
	}
}
