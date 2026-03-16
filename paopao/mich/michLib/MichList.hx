package paopao.mich.michLib;

class MichList {
	public static function length(a:Array<Dynamic>):Int
		return a.length;

	public static function push(a:Array<Dynamic>, v:Dynamic):Array<Dynamic> {
		a.push(v);
		return a;
	}

	public static function pop(a:Array<Dynamic>):Dynamic
		return a.pop();

	public static function shift(a:Array<Dynamic>):Dynamic
		return a.shift();

	public static function unshift(a:Array<Dynamic>, v:Dynamic):Array<Dynamic> {
		a.unshift(v);
		return a;
	}

	public static function join(a:Array<Dynamic>, sep:String):String
		return a.map(Std.string).join(sep);

	public static function slice(a:Array<Dynamic>, start:Int, end:Int):Array<Dynamic>
		return a.slice(start, end);

	public static function concat(a:Array<Dynamic>, b:Array<Dynamic>):Array<Dynamic>
		return a.concat(b);

	public static function indexOf(a:Array<Dynamic>, v:Dynamic):Int
		return a.indexOf(v);

	public static function contains(a:Array<Dynamic>, v:Dynamic):Bool
		return a.indexOf(v) != -1;
}
