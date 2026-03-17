import 'dart:async';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'ffi/lame_library.dart';
import 'encoder_worker.dart';

String getLameVersion() {
  return bindings.get_lame_version().cast<Utf8>().toDartString();
}

class LameMp3Encoder {
  late Future<EncoderWorker> _futureWorker;

  /// Counter to identify [_SumRequest]s and [_SumResponse]s.
  int _nextEncodeRequestId = 0;

  /// Mapping from [_EncodeRequest] or [_EncodeRequestFloat64] `id`s to the completers corresponding to the correct future of the pending request.
  final Map<int, Completer<Uint8List>> _encodeRequests =
      <int, Completer<Uint8List>>{};

  LameMp3Encoder(
      {int numChannels = 2, int sampleRate = 44100, int bitRate = 128}) {
    _futureWorker = EncoderWorker.create(
        numChannels: numChannels,
        sampleRate: sampleRate,
        bitRate: bitRate,
        responseCallback: _onWorkerResponse);
  }

  void _onWorkerResponse(EncodeResponse response) {
    final Completer<Uint8List?> completer = _encodeRequests[response.id]!;
    _encodeRequests.remove(response.id);
    completer.complete(response.result);
  }

  /// Encode PCM-16bit data to mp3 frames
  Future<Uint8List> encode(
      {required Int16List leftChannel, Int16List? rightChannel}) async {
    // Encode will take a long time, which will occupy the thread calling it.
    //
    // Do not call these kind of (long lived) native functions in the main isolate. They will
    // block Dart execution. This will cause dropped frames in Flutter applications.
    // Instead, call these native functions on a separate isolate.

    EncoderWorker worker = await _futureWorker;
    final int requestId = _nextEncodeRequestId++;
    final EncodeRequest request = EncodeRequest(
        id: requestId, leftChannel: leftChannel, rightChannel: rightChannel);
    final Completer<Uint8List> completer = Completer<Uint8List>();
    _encodeRequests[requestId] = completer;
    worker.sendRequest(request);
    return completer.future;
  }

  /// Encode PCM IEEE Double data to mp3 frames
  Future<Uint8List> encodeDouble(
      {required Float64List leftChannel, Float64List? rightChannel}) async {
    final EncoderWorker worker = await _futureWorker;
    final int requestId = _nextEncodeRequestId++;
    final EncodeFloat64Request request = EncodeFloat64Request(
        id: requestId, leftChannel: leftChannel, rightChannel: rightChannel);
    final Completer<Uint8List> completer = Completer<Uint8List>();
    _encodeRequests[requestId] = completer;
    worker.sendRequest(request);
    return completer.future;
  }

  Future<Uint8List> flush() async {
    final EncoderWorker worker = await _futureWorker;
    final int requestId = _nextEncodeRequestId++;
    final FlushRequest request = FlushRequest(requestId);
    final Completer<Uint8List> completer = Completer<Uint8List>();
    _encodeRequests[requestId] = completer;
    worker.sendRequest(request);
    return completer.future;
  }

  Future close() async {
    final EncoderWorker worker = await _futureWorker;
    worker.close();
  }
}

class LameMp3EncoderException implements Exception {
  int errorCode;
  String? errorMessage;

  LameMp3EncoderException(this.errorCode, {this.errorMessage});

  @override
  String toString() {
    return "LameMp3EncoderException! Error Code: $errorCode. ${errorMessage ?? ""}";
  }
}
