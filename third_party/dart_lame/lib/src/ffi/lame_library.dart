import 'dart:ffi' as ffi;

import '../generated/bindings.g.dart';
import './lame_loader.dart';

ffi.DynamicLibrary? _lib;
LameBindings? _bindings;

ffi.DynamicLibrary get lib {
  _lib ??= lameLoader.load();
  return _lib!;
}

LameBindings get bindings {
  _bindings ??= LameBindings(lib);
  return _bindings!;
}
