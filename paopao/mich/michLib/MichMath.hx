package paopao.mich.michLib;

class MichMath {
    public static var pi:Float = Math.PI;
    public static var e:Float = Math.exp(1);

	public static function abs(x:Float):Float
		return Std.int(x) < 0 ? -x : x;

	public static function floor(x:Float):Float
		return Math.floor(x);

	public static function ceil(x:Float):Float
		return Math.ceil(x);

	public static function round(x:Float):Float
		return Math.round(x);

	public static function sqrt(x:Float):Float
		return Math.sqrt(x);

	public static function pow(a:Float,b:Float):Float
		return Math.pow(a,b);

	public static function sin(x:Float):Float
		return Math.sin(x);

	public static function cos(x:Float):Float
		return Math.cos(x);

	public static function tan(x:Float):Float
		return Math.tan(x);

	public static function log(x:Float):Float
		return Math.log(x);

	public static function exp(x:Float):Float
		return Math.exp(x);

	public static function min(a:Float,b:Float):Float
		return a < b ? a : b;

	public static function max(a:Float,b:Float):Float
		return a > b ? a : b;

	public static function random():Float
		return Math.random();

}