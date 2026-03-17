import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

extension Int16ListExtension on Int16List {
  /// Allocate native memory and copy list data into it. You are responsible to
  /// free this memory after use
  Pointer<Short> copyToNativeMemory() {
    final pointer = calloc<Short>(length);
    // `Short` is ABI-specific; `asTypedList` only exists on fixed-width types.
    pointer.cast<Int16>().asTypedList(length).setAll(0, this);
    return pointer;
  }
}

extension Float64ListExtension on Float64List {
  Pointer<Double> copyToNativeMemory() {
    final pointer = calloc<Double>(length);
    pointer.asTypedList(length).setAll(0, this);
    return pointer;
  }
}
