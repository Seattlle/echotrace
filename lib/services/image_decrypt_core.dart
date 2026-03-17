import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';

/// 图片解密核心（无 UI/无线程池依赖，便于在 Isolate 中复用）。
class ImageDecryptCore {
  static const String defaultV1AesKey = 'cfcd208495d565ef';

  /// 返回：0=V3, 1=V4-V1签名, 2=V4-V2签名
  static int getDatVersion(String inputPath) {
    final file = File(inputPath);
    if (!file.existsSync()) {
      throw Exception('文件不存在');
    }

    final bytes = file.readAsBytesSync();
    if (bytes.length < 6) {
      return 0;
    }

    final signature = bytes.sublist(0, 6);
    if (_compareBytes(signature, [0x07, 0x08, 0x56, 0x31, 0x08, 0x07])) {
      return 1;
    }
    if (_compareBytes(signature, [0x07, 0x08, 0x56, 0x32, 0x08, 0x07])) {
      return 2;
    }
    return 0;
  }

  static Uint8List decryptDatV3(String inputPath, int xorKey) {
    final data = File(inputPath).readAsBytesSync();
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ xorKey;
    }
    return result;
  }

  static Uint8List decryptDatV4(String inputPath, int xorKey, Uint8List aesKey) {
    final bytes = File(inputPath).readAsBytesSync();
    if (bytes.length < 0xF) {
      throw Exception('文件太小，无法解析');
    }

    final header = bytes.sublist(0, 0xF);
    final data = bytes.sublist(0xF);

    final aesSize = _bytesToInt32(header.sublist(6, 10));
    final xorSize = _bytesToInt32(header.sublist(10, 14));

    final alignedAesSize = aesSize + (16 - (aesSize % 16));
    if (alignedAesSize > data.length) {
      throw Exception('文件格式异常：AES 数据长度超过文件实际长度');
    }

    final aesData = data.sublist(0, alignedAesSize);

    Uint8List unpaddedData = Uint8List(0);
    if (aesData.isNotEmpty) {
      final cipher = AESEngine();
      cipher.init(false, KeyParameter(aesKey));
      final decryptedData = Uint8List(aesData.length);
      for (int offset = 0; offset < aesData.length; offset += 16) {
        cipher.processBlock(aesData, offset, decryptedData, offset);
      }
      unpaddedData = _strictRemovePadding(decryptedData);
    }

    final remainingData = data.sublist(alignedAesSize);
    if (xorSize < 0 || xorSize > remainingData.length) {
      throw Exception('文件格式异常：XOR 数据长度不合法');
    }

    Uint8List rawData;
    Uint8List xoredData;

    if (xorSize > 0) {
      final rawLength = remainingData.length - xorSize;
      if (rawLength < 0) {
        throw Exception('文件格式异常：原始数据长度小于XOR长度');
      }
      rawData = remainingData.sublist(0, rawLength);
      final xorData = remainingData.sublist(rawLength);
      xoredData = Uint8List(xorData.length);
      for (int i = 0; i < xorData.length; i++) {
        xoredData[i] = xorData[i] ^ xorKey;
      }
    } else {
      rawData = remainingData;
      xoredData = Uint8List(0);
    }

    final result =
        Uint8List(unpaddedData.length + rawData.length + xoredData.length);
    var writeOffset = 0;
    if (unpaddedData.isNotEmpty) {
      result.setRange(0, unpaddedData.length, unpaddedData);
      writeOffset += unpaddedData.length;
    }
    if (rawData.isNotEmpty) {
      result.setRange(writeOffset, writeOffset + rawData.length, rawData);
      writeOffset += rawData.length;
    }
    if (xoredData.isNotEmpty) {
      result.setRange(writeOffset, writeOffset + xoredData.length, xoredData);
    }
    return result;
  }

  static Uint8List asciiKey16(String keyString) {
    final bytes = keyString.codeUnits;
    if (bytes.length < 16) {
      throw Exception('AES密钥至少需要16个字符');
    }
    return Uint8List.fromList(bytes.sublist(0, 16));
  }

  static Uint8List _strictRemovePadding(Uint8List data) {
    if (data.isEmpty) {
      throw Exception('解密结果为空，填充非法');
    }

    final paddingLength = data[data.length - 1];
    if (paddingLength == 0 ||
        paddingLength > 16 ||
        paddingLength > data.length) {
      throw Exception('PKCS7 填充长度非法');
    }

    for (int i = data.length - paddingLength; i < data.length; i++) {
      if (data[i] != paddingLength) {
        throw Exception('PKCS7 填充内容非法');
      }
    }

    return data.sublist(0, data.length - paddingLength);
  }

  static int _bytesToInt32(List<int> bytes) {
    if (bytes.length != 4) {
      throw Exception('需要4个字节');
    }
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }

  static bool _compareBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

