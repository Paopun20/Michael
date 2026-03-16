package paopao.mich.michLib;

class MichTime {
	public static function now():Float
		return Date.now().getTime();

	public static function date():String
		return Date.now().toString();

	public static function year():Int
		return Date.now().getFullYear();

	public static function month():Int
		return Date.now().getMonth() + 1;

	public static function day():Int
		return Date.now().getDate();

	public static function hour():Int
		return Date.now().getHours();

	public static function minute():Int
		return Date.now().getMinutes();

	public static function second():Int
		return Date.now().getSeconds();

	public static function sleep(ms:Int):Bool {
		Sys.sleep(ms / 1000);
		return true;
	}
}
