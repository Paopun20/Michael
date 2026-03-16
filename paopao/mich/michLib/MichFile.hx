package paopao.mich.michLib;

import sys.io.File;
import sys.FileSystem;

class MichFile {
	public static function read(path:String):String {
		return File.getContent(path);
	}

	public static function write(path:String, v:Null<Dynamic>):Null<Dynamic> {
		File.saveContent(path, v == null ? "" : Std.string(v));
		return null;
	}

	public static function append(path:String, v:Null<Dynamic>):Null<Dynamic> {
		var txt = v == null ? "" : Std.string(v);
		var old = FileSystem.exists(path) ? File.getContent(path) : "";
		File.saveContent(path, old + txt);
		return null;
	}

	public static function exists(path:String):Bool {
		return FileSystem.exists(path);
	}

	public static function delete(path:String):Null<Dynamic> {
		if (FileSystem.exists(path))
			FileSystem.deleteFile(path);
		return null;
	}
}
