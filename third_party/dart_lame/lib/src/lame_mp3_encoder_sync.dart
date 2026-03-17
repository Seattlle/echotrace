import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dart_lame_base.dart';
import 'ffi/lame_library.dart';
import 'generated/bindings.g.dart';

/// Synchronous PCM->MP3 encoder using LAME via FFI.
///
/// This is intended for use from a background isolate. On the main isolate it
/// may block the UI.
class LameMp3EncoderSync {
  final int numChannels;
  final int sampleRate;
  final int bitRate;

  final ffi.Pointer<lame_global_struct> _flags;

  ffi.Pointer<ffi.Int16>? _int16LeftBuf;
  int _int16LeftCapacity = 0;
  ffi.Pointer<ffi.Int16>? _int16RightBuf;
  int _int16RightCapacity = 0;

  ffi.Pointer<ffi.Double>? _float64LeftBuf;
  int _float64LeftCapacity = 0;
  ffi.Pointer<ffi.Double>? _float64RightBuf;
  int _float64RightCapacity = 0;

  ffi.Pointer<ffi.Uint8>? _mp3Buf;
  int _mp3BufCapacity = 0;

  bool _closed = false;

  LameMp3EncoderSync({
    this.numChannels = 2,
    this.sampleRate = 44100,
    this.bitRate = 128,
  }) : _flags = bindings.lame_init() {
    bindings.lame_set_num_channels(_flags, numChannels);
    bindings.lame_set_in_samplerate(_flags, sampleRate);
    bindings.lame_set_brate(_flags, bitRate);

    if (numChannels == 1) {
      bindings.lame_set_mode(_flags, 3); // 3: mono mode
    }

    final int retCode = bindings.lame_init_params(_flags);
    if (retCode < 0) {
      throw LameMp3EncoderException(
        retCode,
        errorMessage:
            'Unable to create encoder, probably because of invalid parameters',
      );
    }
  }

  Uint8List encode({required Int16List leftChannel, Int16List? rightChannel}) {
    _ensureOpen();

    if (rightChannel != null && rightChannel.length != leftChannel.length) {
      throw ArgumentError.value(
        rightChannel,
        'rightChannel',
        'Must have the same length as leftChannel',
      );
    }

    final int sampleCount = leftChannel.length;
    if (_int16LeftCapacity < sampleCount) {
      if (_int16LeftBuf != null) calloc.free(_int16LeftBuf!);
      _int16LeftBuf = calloc<ffi.Int16>(sampleCount);
      _int16LeftCapacity = sampleCount;
    }
    _int16LeftBuf!.asTypedList(sampleCount).setAll(0, leftChannel);

    ffi.Pointer<ffi.Int16>? ptrRight;
    if (rightChannel != null) {
      if (_int16RightCapacity < sampleCount) {
        if (_int16RightBuf != null) calloc.free(_int16RightBuf!);
        _int16RightBuf = calloc<ffi.Int16>(sampleCount);
        _int16RightCapacity = sampleCount;
      }
      _int16RightBuf!.asTypedList(sampleCount).setAll(0, rightChannel);
      ptrRight = _int16RightBuf;
    }

    final int requiredMp3BufSize = (1.25 * sampleCount + 7500).ceil();
    _ensureMp3Buf(requiredMp3BufSize);

    final int encodedSize = bindings.lame_encode_buffer(
      _flags,
      _int16LeftBuf!.cast<ffi.Short>(),
      (ptrRight ?? ffi.Pointer<ffi.Int16>.fromAddress(0)).cast<ffi.Short>(),
      sampleCount,
      _mp3Buf!.cast<ffi.UnsignedChar>(),
      _mp3BufCapacity,
    );
    if (encodedSize < 0) {
      throw LameMp3EncoderException(
        encodedSize,
        errorMessage: 'lame_encode_buffer failed',
      );
    }

    final result = Uint8List(encodedSize);
    result.setAll(0, _mp3Buf!.asTypedList(encodedSize));
    return result;
  }

  Uint8List encodeDouble(
      {required Float64List leftChannel, Float64List? rightChannel}) {
    _ensureOpen();

    if (rightChannel != null && rightChannel.length != leftChannel.length) {
      throw ArgumentError.value(
        rightChannel,
        'rightChannel',
        'Must have the same length as leftChannel',
      );
    }

    final int sampleCount = leftChannel.length;
    if (_float64LeftCapacity < sampleCount) {
      if (_float64LeftBuf != null) calloc.free(_float64LeftBuf!);
      _float64LeftBuf = calloc<ffi.Double>(sampleCount);
      _float64LeftCapacity = sampleCount;
    }
    _float64LeftBuf!.asTypedList(sampleCount).setAll(0, leftChannel);

    ffi.Pointer<ffi.Double>? ptrRight;
    if (rightChannel != null) {
      if (_float64RightCapacity < sampleCount) {
        if (_float64RightBuf != null) calloc.free(_float64RightBuf!);
        _float64RightBuf = calloc<ffi.Double>(sampleCount);
        _float64RightCapacity = sampleCount;
      }
      _float64RightBuf!.asTypedList(sampleCount).setAll(0, rightChannel);
      ptrRight = _float64RightBuf;
    }

    final int requiredMp3BufSize = (1.25 * sampleCount + 7500).ceil();
    _ensureMp3Buf(requiredMp3BufSize);

    final int encodedSize = bindings.lame_encode_buffer_ieee_double(
      _flags,
      _float64LeftBuf!,
      ptrRight ?? ffi.Pointer<ffi.Double>.fromAddress(0),
      sampleCount,
      _mp3Buf! as ffi.Pointer<ffi.UnsignedChar>,
      _mp3BufCapacity,
    );
    if (encodedSize < 0) {
      throw LameMp3EncoderException(
        encodedSize,
        errorMessage: 'lame_encode_buffer_ieee_double failed',
      );
    }

    final result = Uint8List(encodedSize);
    result.setAll(0, _mp3Buf!.asTypedList(encodedSize));
    return result;
  }

  Uint8List flush() {
    _ensureOpen();

    const int requiredMp3BufSize = 7200; // See LAME API doc
    _ensureMp3Buf(requiredMp3BufSize);

    final int encodedSize =
        bindings.lame_encode_flush(
            _flags, _mp3Buf!.cast<ffi.UnsignedChar>(), _mp3BufCapacity);
    if (encodedSize < 0) {
      throw LameMp3EncoderException(
        encodedSize,
        errorMessage: 'lame_encode_flush failed',
      );
    }

    final result = Uint8List(encodedSize);
    result.setAll(0, _mp3Buf!.asTypedList(encodedSize));
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;

    bindings.lame_close(_flags);

    if (_int16LeftBuf != null) calloc.free(_int16LeftBuf!);
    if (_int16RightBuf != null) calloc.free(_int16RightBuf!);
    if (_float64LeftBuf != null) calloc.free(_float64LeftBuf!);
    if (_float64RightBuf != null) calloc.free(_float64RightBuf!);
    if (_mp3Buf != null) calloc.free(_mp3Buf!);
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Encoder is closed');
    }
  }

  void _ensureMp3Buf(int requiredSize) {
    if (_mp3BufCapacity >= requiredSize) return;
    if (_mp3Buf != null) calloc.free(_mp3Buf!);
    _mp3Buf = calloc<ffi.Uint8>(requiredSize);
    _mp3BufCapacity = requiredSize;
  }
}
