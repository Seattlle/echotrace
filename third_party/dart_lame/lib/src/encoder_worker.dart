import 'dart:async';
import 'dart:isolate';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/lame_library.dart';
import 'ffi/lame_loader.dart';
import 'dart_lame_base.dart';
import 'generated/bindings.g.dart';

class EncoderWorker {
  final ReceivePort receivePort;
  final SendPort sendPort;
  final Function(EncodeResponse) responseCallback;

  EncoderWorker._(
      {required this.receivePort,
      required this.sendPort,
      required this.responseCallback});

  static Future<EncoderWorker> create(
      {required int numChannels,
      required int sampleRate,
      required int bitRate,
      required Function(EncodeResponse) responseCallback}) async {
    // The worker isolate is going to send us back a SendPort, which we want to
    // wait for.
    final Completer<SendPort> completer = Completer<SendPort>();

    // Receive port on the main isolate to receive messages from the helper.
    // We receive two types of messages:
    // 1. A port to send messages on.
    // 2. Responses to requests we sent.
    final ReceivePort receivePort = ReceivePort()
      ..listen((dynamic data) {
        if (data is SendPort) {
          // The worker isolate sent us the port on which we can sent it requests.
          completer.complete(data);
          return;
        }
        if (data is EncodeResponse) {
          // The worker isolate sent us a response to a request we sent.
          responseCallback(data);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    await Isolate.spawn((EncoderWorkerOptions options) {
      lameLoader = options.lameLoader;

      final ffi.Pointer<lame_global_struct> flags = bindings.lame_init();
      bindings.lame_set_num_channels(flags, options.numChannels);
      bindings.lame_set_in_samplerate(flags, options.sampleRate);
      bindings.lame_set_brate(flags, options.bitRate);

      if (options.numChannels == 1) {
        bindings.lame_set_mode(flags, 3); // 3: mono mode
      }

      int retCode = bindings.lame_init_params(flags);
      if (retCode < 0) {
        throw LameMp3EncoderException(retCode,
            errorMessage:
                "Unable to create encoder, probably because of invalid parameters");
      }

      final ReceivePort workerReceivePort = ReceivePort();

      ffi.Pointer<ffi.Int16>? int16LeftBuf;
      int int16LeftCapacity = 0;
      ffi.Pointer<ffi.Int16>? int16RightBuf;
      int int16RightCapacity = 0;

      ffi.Pointer<ffi.Double>? float64LeftBuf;
      int float64LeftCapacity = 0;
      ffi.Pointer<ffi.Double>? float64RightBuf;
      int float64RightCapacity = 0;

      ffi.Pointer<ffi.Uint8>? mp3Buf;
      int mp3BufCapacity = 0;

      workerReceivePort.listen((dynamic data) {
        // On the worker isolate listen to requests and respond to them.
        if (data is EncodeRequest) {
          final int sampleCount = data.leftChannel.length;

          if (int16LeftCapacity < sampleCount) {
            if (int16LeftBuf != null) calloc.free(int16LeftBuf!);
            int16LeftBuf = calloc<ffi.Int16>(sampleCount);
            int16LeftCapacity = sampleCount;
          }
          int16LeftBuf!.asTypedList(sampleCount).setAll(0, data.leftChannel);

          ffi.Pointer<ffi.Int16>? ptrRight;
          if (data.rightChannel != null) {
            if (int16RightCapacity < sampleCount) {
              if (int16RightBuf != null) calloc.free(int16RightBuf!);
              int16RightBuf = calloc<ffi.Int16>(sampleCount);
              int16RightCapacity = sampleCount;
            }
            int16RightBuf!
                .asTypedList(sampleCount)
                .setAll(0, data.rightChannel!);
            ptrRight = int16RightBuf;
          }

          final int requiredMp3BufSize = (1.25 * sampleCount + 7500).ceil();
          if (mp3BufCapacity < requiredMp3BufSize) {
            if (mp3Buf != null) calloc.free(mp3Buf!);
            mp3Buf = calloc<ffi.Uint8>(requiredMp3BufSize);
            mp3BufCapacity = requiredMp3BufSize;
          }

          int encodedSize = bindings.lame_encode_buffer(
              flags,
              int16LeftBuf!.cast<ffi.Short>(),
              (ptrRight ?? ffi.Pointer<ffi.Int16>.fromAddress(0))
                  .cast<ffi.Short>(),
              sampleCount,
              mp3Buf!.cast<ffi.UnsignedChar>(),
              mp3BufCapacity);
          if (encodedSize < 0) {
            throw LameMp3EncoderException(
              encodedSize,
              errorMessage: 'lame_encode_buffer failed',
            );
          }

          final result = Uint8List(encodedSize);
          result.setAll(0, mp3Buf!.asTypedList(encodedSize));

          final EncodeResponse response =
              EncodeResponse(id: data.id, result: result);
          options.sendPort.send(response);
          return;
        }

        if (data is EncodeFloat64Request) {
          final int sampleCount = data.leftChannel.length;

          if (float64LeftCapacity < sampleCount) {
            if (float64LeftBuf != null) calloc.free(float64LeftBuf!);
            float64LeftBuf = calloc<ffi.Double>(sampleCount);
            float64LeftCapacity = sampleCount;
          }
          float64LeftBuf!
              .asTypedList(sampleCount)
              .setAll(0, data.leftChannel);

          ffi.Pointer<ffi.Double>? ptrRight;
          if (data.rightChannel != null) {
            if (float64RightCapacity < sampleCount) {
              if (float64RightBuf != null) calloc.free(float64RightBuf!);
              float64RightBuf = calloc<ffi.Double>(sampleCount);
              float64RightCapacity = sampleCount;
            }
            float64RightBuf!
                .asTypedList(sampleCount)
                .setAll(0, data.rightChannel!);
            ptrRight = float64RightBuf;
          }

          // See LAME API doc
          final int requiredMp3BufSize = (1.25 * sampleCount + 7500).ceil();
          if (mp3BufCapacity < requiredMp3BufSize) {
            if (mp3Buf != null) calloc.free(mp3Buf!);
            mp3Buf = calloc<ffi.Uint8>(requiredMp3BufSize);
            mp3BufCapacity = requiredMp3BufSize;
          }

          int encodedSize = bindings.lame_encode_buffer_ieee_double(
              flags,
              float64LeftBuf!,
              ptrRight ?? ffi.Pointer<ffi.Double>.fromAddress(0),
              sampleCount,
              mp3Buf!.cast<ffi.UnsignedChar>(),
              mp3BufCapacity);
          if (encodedSize < 0) {
            throw LameMp3EncoderException(
              encodedSize,
              errorMessage: 'lame_encode_buffer_ieee_double failed',
            );
          }

          final result = Uint8List(encodedSize);
          result.setAll(0, mp3Buf!.asTypedList(encodedSize));

          final EncodeResponse response =
              EncodeResponse(id: data.id, result: result);
          options.sendPort.send(response);
          return;
        }

        if (data is FlushRequest) {
          const int requiredMp3BufSize = 7200; // See LAME API doc
          if (mp3BufCapacity < requiredMp3BufSize) {
            if (mp3Buf != null) calloc.free(mp3Buf!);
            mp3Buf = calloc<ffi.Uint8>(requiredMp3BufSize);
            mp3BufCapacity = requiredMp3BufSize;
          }

          int encodedSize =
              bindings.lame_encode_flush(flags, mp3Buf!.cast<ffi.UnsignedChar>(),
                  mp3BufCapacity);
          if (encodedSize < 0) {
            throw LameMp3EncoderException(
              encodedSize,
              errorMessage: 'lame_encode_flush failed',
            );
          }

          final result = Uint8List(encodedSize);
          result.setAll(0, mp3Buf!.asTypedList(encodedSize));

          final EncodeResponse response =
              EncodeResponse(id: data.id, result: result);
          options.sendPort.send(response);
          return;
        }

        if (data is _CloseRequest) {
          bindings.lame_close(flags);

          if (int16LeftBuf != null) calloc.free(int16LeftBuf!);
          if (int16RightBuf != null) calloc.free(int16RightBuf!);
          if (float64LeftBuf != null) calloc.free(float64LeftBuf!);
          if (float64RightBuf != null) calloc.free(float64RightBuf!);
          if (mp3Buf != null) calloc.free(mp3Buf!);

          workerReceivePort.close();
          Isolate.exit();
        }

        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

      // Send the the port to the main isolate on which we can receive requests.
      options.sendPort.send(workerReceivePort.sendPort);
    },
        EncoderWorkerOptions(
            numChannels: numChannels,
            sampleRate: sampleRate,
            bitRate: bitRate,
            sendPort: receivePort.sendPort,
            lameLoader: lameLoader));

    return EncoderWorker._(
        receivePort: receivePort,
        sendPort: await completer.future,
        responseCallback: responseCallback);
  }

  void sendRequest(BaseEncoderRequest? request) {
    sendPort.send(request);
  }

  void close() {
    final _CloseRequest request = _CloseRequest();
    sendPort.send(request);
    receivePort.close();
  }
}

class EncoderWorkerOptions {
  final int numChannels;
  final int sampleRate;
  final int bitRate;
  final SendPort sendPort;
  final LameLibraryLoader lameLoader;

  EncoderWorkerOptions(
      {required this.numChannels,
      required this.sampleRate,
      required this.bitRate,
      required this.sendPort,
      required this.lameLoader});
}

class BaseEncoderRequest {
  final int id;
  const BaseEncoderRequest(this.id);
}

class EncodeRequest extends BaseEncoderRequest {
  final Int16List leftChannel;
  final Int16List? rightChannel;

  const EncodeRequest(
      {required int id, required this.leftChannel, this.rightChannel})
      : super(id);
}

class EncodeFloat64Request extends BaseEncoderRequest {
  final Float64List leftChannel;
  final Float64List? rightChannel;

  const EncodeFloat64Request(
      {required int id, required this.leftChannel, this.rightChannel})
      : super(id);
}

class FlushRequest extends BaseEncoderRequest {
  const FlushRequest(int id) : super(id);
}

class _CloseRequest {}

class EncodeResponse {
  final int id;
  final Uint8List result;

  EncodeResponse({required this.id, required this.result});
}
