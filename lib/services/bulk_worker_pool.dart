import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_lame/flutter_lame.dart';

import 'image_decrypt_core.dart';

/// 在批量任务期间复用 Isolate，避免每个文件都新建 Isolate 带来的卡顿。
///
/// 仅用于 Windows（当前项目面向 Windows），但实现本身是跨平台的。
class BulkWorkerPool {
  BulkWorkerPool._(this._size);

  final int _size;
  final List<_Worker> _workers = [];
  final List<_Worker> _idle = [];
  final Queue<_PendingTask> _queue = Queue<_PendingTask>();
  bool _closed = false;

  static Future<BulkWorkerPool> start({required int size}) async {
    final pool = BulkWorkerPool._(size);
    await pool._start();
    return pool;
  }

  bool get isClosed => _closed;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final worker in _workers) {
      worker.send(_WorkerMessage.shutdown());
    }
    for (final worker in _workers) {
      await worker.dispose();
    }
    _workers.clear();
    _idle.clear();
    _queue.clear();
  }

  Future<void> encodePcmToMp3({
    required String inputPcmPath,
    required String outputMp3Path,
    required int sampleRate,
    required int channels,
  }) {
    return _schedule<void>(
      _WorkerMessage.encodePcmToMp3(
        inputPcmPath: inputPcmPath,
        outputMp3Path: outputMp3Path,
        sampleRate: sampleRate,
        channels: channels,
      ),
      (payload) {},
    );
  }

  Future<void> decryptDatAuto({
    required String inputPath,
    required String outputPath,
    required int xorKey,
    required Uint8List? aesKey,
  }) {
    return _schedule<void>(
      _WorkerMessage.decryptDatAuto(
        inputPath: inputPath,
        outputPath: outputPath,
        xorKey: xorKey,
        aesKey: aesKey,
      ),
      (payload) {},
    );
  }

  Future<void> _start() async {
    final futures = <Future<_Worker>>[];
    for (var i = 0; i < _size; i++) {
      futures.add(_Worker.spawn());
    }
    final workers = await Future.wait(futures);
    _workers.addAll(workers);
    _idle.addAll(workers);
  }

  Future<T> _schedule<T>(_WorkerMessage message, T Function(Object?) parse) {
    if (_closed) {
      return Future.error(StateError('BulkWorkerPool is closed'));
    }
    final completer = Completer<T>();
    final task = _PendingTask<T>(message, parse, completer);
    _queue.add(task);
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_closed) return;
    while (_idle.isNotEmpty && _queue.isNotEmpty) {
      final worker = _idle.removeLast();
      final task = _queue.removeFirst();
      worker
          .run(task.message)
          .then((result) {
            try {
              task.completer.complete(task.parse(result));
            } catch (e, st) {
              task.completer.completeError(e, st);
            }
          })
          .catchError((e, st) {
            task.completer.completeError(e, st);
          })
          .whenComplete(() {
            if (!_closed) {
              _idle.add(worker);
              _pump();
            }
          });
    }
  }
}

class _PendingTask<T> {
  _PendingTask(this.message, this.parse, this.completer);

  final _WorkerMessage message;
  final T Function(Object?) parse;
  final Completer<T> completer;
}

class _Worker {
  _Worker._(this._isolate, this._sendPort, this._recv);

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _recv;

  static Future<_Worker> spawn() async {
    final recv = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, recv.sendPort);
    final sendPort = await recv.first as SendPort;
    return _Worker._(isolate, sendPort, recv);
  }

  void send(_WorkerMessage msg) {
    _sendPort.send(msg.toMap());
  }

  Future<Object?> run(_WorkerMessage msg) async {
    final reply = ReceivePort();
    _sendPort.send(msg.toMap(reply: reply.sendPort));
    final res = await reply.first;
    reply.close();
    if (res is Map && res['ok'] == true) {
      return res['result'];
    }
    final error = (res is Map ? res['error'] : null) ?? 'unknown error';
    throw Exception(error);
  }

  Future<void> dispose() async {
    _recv.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _WorkerMessage {
  _WorkerMessage._(this.type, this.args);

  final String type;
  final Map<String, Object?> args;

  factory _WorkerMessage.shutdown() => _WorkerMessage._('shutdown', const {});

  factory _WorkerMessage.encodePcmToMp3({
    required String inputPcmPath,
    required String outputMp3Path,
    required int sampleRate,
    required int channels,
  }) {
    return _WorkerMessage._('encodePcmToMp3', {
      'inputPcmPath': inputPcmPath,
      'outputMp3Path': outputMp3Path,
      'sampleRate': sampleRate,
      'channels': channels,
    });
  }

  factory _WorkerMessage.decryptDatAuto({
    required String inputPath,
    required String outputPath,
    required int xorKey,
    required Uint8List? aesKey,
  }) {
    return _WorkerMessage._('decryptDatAuto', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'xorKey': xorKey,
      'aesKey': aesKey,
    });
  }

  Map<String, Object?> toMap({SendPort? reply}) => {
    'type': type,
    'args': args,
    if (reply != null) 'reply': reply,
  };
}

@pragma('vm:entry-point')
void _workerMain(SendPort parentPort) {
  final recv = ReceivePort();
  parentPort.send(recv.sendPort);

  recv.listen((message) async {
    if (message is! Map) return;
    final type = message['type'];
    final args = message['args'];
    final reply = message['reply'];
    if (type is! String) return;

    if (type == 'shutdown') {
      recv.close();
      return;
    }

    if (reply is! SendPort) return;

    try {
      if (type == 'encodePcmToMp3') {
        final m = Map<String, Object?>.from(args as Map);
        await _encodePcmToMp3InIsolate(
          inputPcmPath: m['inputPcmPath'] as String,
          outputMp3Path: m['outputMp3Path'] as String,
          sampleRate: m['sampleRate'] as int,
          channels: m['channels'] as int,
        );
        reply.send({'ok': true, 'result': null});
        return;
      }

      if (type == 'decryptDatAuto') {
        final m = Map<String, Object?>.from(args as Map);
        final aesKey = m['aesKey'] as Uint8List?;
        final version = ImageDecryptCore.getDatVersion(
          m['inputPath'] as String,
        );
        Uint8List decryptedData;
        switch (version) {
          case 0:
            decryptedData = ImageDecryptCore.decryptDatV3(
              m['inputPath'] as String,
              m['xorKey'] as int,
            );
            break;
          case 1:
            decryptedData = ImageDecryptCore.decryptDatV4(
              m['inputPath'] as String,
              m['xorKey'] as int,
              ImageDecryptCore.asciiKey16(ImageDecryptCore.defaultV1AesKey),
            );
            break;
          default:
            if (aesKey == null || aesKey.length != 16) {
              throw Exception('V4版本需要16字节AES密钥');
            }
            decryptedData = ImageDecryptCore.decryptDatV4(
              m['inputPath'] as String,
              m['xorKey'] as int,
              aesKey,
            );
        }
        File(
          m['outputPath'] as String,
        ).writeAsBytesSync(decryptedData, flush: true);
        reply.send({'ok': true, 'result': null});
        return;
      }

      reply.send({'ok': false, 'error': 'unknown task: $type'});
    } catch (e) {
      reply.send({'ok': false, 'error': e.toString()});
    }
  });
}

Future<void> _encodePcmToMp3InIsolate({
  required String inputPcmPath,
  required String outputMp3Path,
  required int sampleRate,
  required int channels,
}) async {
  final pcmFile = File(inputPcmPath);
  if (!pcmFile.existsSync()) {
    throw Exception('未找到 PCM 文件: $inputPcmPath');
  }

  final encoder = LameMp3EncoderSync(
    sampleRate: sampleRate,
    numChannels: channels,
  );
  final sink = File(outputMp3Path).openWrite();
  Uint8List? pendingByte;

  try {
    await for (final chunk in pcmFile.openRead()) {
      if (chunk.isEmpty) continue;
      Uint8List data;
      if (pendingByte != null && pendingByte.isNotEmpty) {
        data = Uint8List(pendingByte.length + chunk.length)
          ..setRange(0, pendingByte.length, pendingByte)
          ..setRange(
            pendingByte.length,
            pendingByte.length + chunk.length,
            chunk,
          );
        pendingByte = null;
      } else {
        data = Uint8List.fromList(chunk);
      }

      final evenLength = data.length & ~1;
      if (evenLength != data.length) {
        pendingByte = data.sublist(data.length - 1);
      }
      if (evenLength == 0) continue;

      final sampleCount = evenLength ~/ 2;
      final samples = Int16List.view(
        data.buffer,
        data.offsetInBytes,
        sampleCount,
      );

      final frame = encoder.encode(leftChannel: samples);
      if (frame.isNotEmpty) sink.add(frame);
    }

    final last = encoder.flush();
    if (last.isNotEmpty) sink.add(last);
    await sink.flush();
  } finally {
    await sink.close();
    try {
      encoder.close();
    } catch (_) {}
  }

  final out = File(outputMp3Path);
  if (!out.existsSync() || out.lengthSync() == 0) {
    throw Exception('MP3 编码失败: 未生成输出文件');
  }
}
