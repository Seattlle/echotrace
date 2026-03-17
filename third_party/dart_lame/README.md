<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages). 
-->

Dart native bindings to LAME (MP3 encoder)

## Features
- Encode WAV (PCM-16 or PCM IEEE Double) to MP3

## Getting started

To use this library, you must have `libmp3lame` installed on your system.
Please make sure the following library is available on your system or place 
it under your program's working directory.
- Windows: `mp3lame.dll`
- Linux: `libmp3lame.so`
- macOS: `libmp3lame.dylib`

Alternatively, you can manually load `libmp3lame`:
```dart
import 'dart:ffi' as ffi;
import 'package:dart_lame/dart_lame.dart' as lame;

class CustomLoader extends lame.LameLibraryLoader {
  @override
  ffi.DynamicLibrary load() {
    return ffi.DynamicLibrary.open("path_to_libmp3lame");
  }
}

lame.lameLoader = CustomLoader(); 
```

**For Flutter user, please use [flutter_lame](https://github.com/BestOwl/flutter_lame) instead.**
## Usage

```dart
final File f = File("output.mp3");
final IOSink sink = f.openWrite();
final LameMp3Encoder encoder = LameMp3Encoder(sampleRate: 44100, numChannels: 2);


Float64List leftChannelSamples;
Float64List rightChannelSamples;
// Get samples from file or from microphone.

final mp3Frame = await encoder.encode(
  leftChannel: leftChannelSamples,
  rightChannel: rightChannelSamples);
sink.add(mp3Frame);
// continue until all samples have been encoded

// finally, flush encoder buffer
final lastMp3Frame = await encoder.flush();
sink.add(lastMp3Frame);
```

## Performance notes (Windows)

- `LameMp3Encoder` uses a worker isolate and copies PCM buffers between isolates.
- If you already run encoding in a background isolate, use `LameMp3EncoderSync` to avoid the extra isolate hop:

```dart
final encoder = LameMp3EncoderSync(sampleRate: 44100, numChannels: 1);
final frame = encoder.encode(leftChannel: pcm16Samples);
sink.add(frame);
sink.add(encoder.flush());
encoder.close();
```

For a complete example, please go to `/example` folder.
