package paopao.mich.michLib;

class MichRandom {
	public static function random():Float
		return Math.random();

	public static function int(min:Int, max:Int):Int
		return min + Std.random(max - min + 1);

	public static function float(min:Float, max:Float):Float
		return min + Math.random() * (max - min);

	public static function choice(a:Array<Dynamic>):Dynamic
		return a[Std.random(a.length)];

	public static function shuffle(a:Array<Dynamic>):Array<Dynamic> {
		var b = a.copy();
		for (i in 0...b.length) {
			var j = Std.random(b.length);
			var tmp = b[i];
			b[i] = b[j];
			b[j] = tmp;
		}
		return b;
	}

	public static function bool():Bool
		return Math.random() < 0.5;
}
