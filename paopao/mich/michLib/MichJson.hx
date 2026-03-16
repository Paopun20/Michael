package paopao.mich.michLib;

import haxe.Json;

class MichJson {

	public static function parse(s:String):Dynamic
		return Json.parse(s);

	public static function stringify(v:Dynamic):String
		return Json.stringify(v);

	public static function pretty(v:Dynamic):String
		return Json.stringify(v, null, "  ");

	public static function valid(s:String):Bool {
		try {
			Json.parse(s);
			return true;
		} catch (e:Dynamic) {
			return false;
		}
	}

}