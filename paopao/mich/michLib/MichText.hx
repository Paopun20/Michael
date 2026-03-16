package paopao.mich.michLib;

using StringTools;

class MichText {
	public static function upper(s:String):String
		return s.toUpperCase();

	public static function lower(s:String):String
		return s.toLowerCase();

	public static function trim(s:String):String
		return s.trim();

	public static function split(s:String, sep:String):Array<String>
		return s.split(sep);

	public static function join(arr:Array<Dynamic>, sep:String):String
		return arr.map(Std.string).join(sep);

	public static function contains(s:String, sub:String):Bool
		return s.indexOf(sub) != -1;

	public static function startsWith(s:String, prefix:String):Bool
		return s.startsWith(prefix);

	public static function endsWith(s:String, suffix:String):Bool
		return s.endsWith(suffix);

	public static function replace(s:String, a:String, b:String):String
		return s.replace(a, b);

	public static function length(s:String):Int
		return s.length;

	public static function indexOf(s:String, sub:String):Int
		return s.indexOf(sub);

	public static function charAt(s:String, i:Int):String
		return s.charAt(i);

	public static function repeat(n:Int, s:String):String {
		var buf = new StringBuf();
		for (i in 0...n)
			buf.add(s);
		return buf.toString();
	}
}
