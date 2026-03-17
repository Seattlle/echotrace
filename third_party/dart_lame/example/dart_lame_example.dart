import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:dart_lame/dart_lame.dart';
import 'package:wav/wav.dart';

void main(List<String> arguments) async {
  print("dart_lame example");

  final parser = ArgParser()
    ..addOption("format",
        abbr: "f",
        allowed: ["wav", "pcm16"],
        help:
            "Input file format. Note: only accept mono channel file if the format is pcm16",
        defaultsTo: "wav")
    ..addOption("sample-rate",
        abbr: "s",
        help:
            "Sample rate of the input file. Mandatory if the input format is pcm16")
    ..addOption("input", abbr: "i", help: "Input file", mandatory: true)
    ..addOption("output",
        abbr: "o", help: "Output mp3 file", defaultsTo: "output.mp3");
  final argResults = parser.parse(arguments);
  print('LAME version: ${getLameVersion()}');

  final String inputPath = argResults["input"];
  print("Input file: $inputPath");

  print("Encoding...");

  final String outputPath = argResults["output"];
  final File f = File(outputPath);
  final IOSink sink = f.openWrite();
  try {
    if (argResults["format"] == "wav") {
      final wav = await Wav.readFile(inputPath);
      await encodeWav(wav, sink);
    } else {
      String? sampleRate = argResults["sample-rate"];
      if (sampleRate == null) {
        throw ArgumentError("--sample-rate is required");
      }
      await encodePcm(inputPath, sink, int.parse(sampleRate));
    }
  } finally {
    sink.close();
  }

  print("Successfully encoded mp3 file: ${f.absolute}");
}

Future encodeWav(Wav wav, IOSink sink) async {
  final encoder = LameMp3Encoder(
      sampleRate: wav.samplesPerSecond, numChannels: wav.channels.length);
  try {
    final left = wav.channels[0];
    Float64List? right;
    if (wav.channels.length > 1) {
      right = wav.channels[1];
    }

    for (int i = 0; i < left.length; i += wav.samplesPerSecond) {
      final mp3Frame = await encoder.encodeDouble(
          leftChannel: left.sublist(i, i + wav.samplesPerSecond),
          rightChannel: right?.sublist(i, i + wav.samplesPerSecond));
      sink.add(mp3Frame);
    }
    sink.add(await encoder.flush());
  } finally {
    encoder.close();
  }
}

Future encodePcm(String inputPath, IOSink sink, int sampleRate) async {
  final encoder = LameMp3Encoder(sampleRate: sampleRate, numChannels: 1);

  final File inputFile = File(inputPath);
  final Completer readCompleter = Completer();
  final Completer encodeCompleter = Completer();

  int counter = 0;

  final StreamSubscription<List<int>> sub = inputFile.openRead().listen(
      (event) async {
    counter++;
    final Uint8List mp3frame = await encoder.encode(
        leftChannel: Uint8List.fromList(event).buffer.asInt16List());
    sink.add(mp3frame);
    counter--;

    if (readCompleter.isCompleted) {
      if (counter == 0) {
        encodeCompleter.complete();
      }
    }
  },
      onDone: () => readCompleter.complete(),
      onError: (e) => readCompleter.completeError(e));

  try {
    await readCompleter.future;
    await encodeCompleter.future;
    final lastMp3Frame = await encoder.flush();
    sink.add(lastMp3Frame);
  } finally {
    sub.cancel();
    encoder.close();
  }
}
