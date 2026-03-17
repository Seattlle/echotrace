import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

/// You can assign your own loader to load `libmp3lame` from other location.
LameLibraryLoader lameLoader = _DefaultLameLoader();

/// Loader to load `libmp3lame` library
///
/// This class must be able to send between [Isolate] (i.e. sendable)
/// See also https://dart.dev/guides/language/concurrency#background-workers
abstract class LameLibraryLoader {
  ffi.DynamicLibrary load();
}

const String _libName = 'mp3lame';

class _DefaultLameLoader extends LameLibraryLoader {
  @override
  ffi.DynamicLibrary load() {
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('lib$_libName.dylib');
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('lib$_libName.so');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('$_libName.dll');
    }
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }
}
