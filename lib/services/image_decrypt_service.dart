import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'bulk_worker_pool.dart';
import 'image_decrypt_core.dart';

/// 微信图片解密服务
/// 本服务实现借鉴了 recarto404/WxDatDecrypt 
class ImageDecryptService {
  static const String _defaultV1AesKey = 'cfcd208495d565ef';

  BulkWorkerPool? bulkPool;

  /// 解密微信 V3 版本的 .dat 文件
  /// [inputPath] 输入文件路径
  /// [xorKey] XOR 密钥
  Uint8List decryptDatV3(String inputPath, int xorKey) {
    return ImageDecryptCore.decryptDatV3(inputPath, xorKey);
  }

  /// 解密微信 V4 版本的 .dat 文件
  /// [inputPath] 输入文件路径
  /// [xorKey] XOR 密钥
  /// [aesKey] AES 密钥（16字节）
  Uint8List decryptDatV4(String inputPath, int xorKey, Uint8List aesKey) {
    return ImageDecryptCore.decryptDatV4(inputPath, xorKey, aesKey);
  }

  /// 判断 .dat 文件的加密版本
  /// 返回：0=V3, 1=V4-V1签名, 2=V4-V2签名
  int getDatVersion(String inputPath) {
    return ImageDecryptCore.getDatVersion(inputPath);
  }

  /// 自动检测版本并解密（异步版本）
  /// [inputPath] 输入文件路径
  /// [outputPath] 输出文件路径
  /// [xorKey] XOR 密钥
  /// [aesKey] AES 密钥（仅V4需要）
  Future<void> decryptDatAutoAsync(
    String inputPath,
    String outputPath,
    int xorKey,
    Uint8List? aesKey,
  ) async {
    final pool = bulkPool;
    if (pool != null && !pool.isClosed) {
      await pool.decryptDatAuto(
        inputPath: inputPath,
        outputPath: outputPath,
        xorKey: xorKey,
        aesKey: aesKey,
      );
      return;
    }

    // 放到 Isolate 避免大文件同步读取/解密阻塞 UI。
    await Isolate.run(() {
      final service = ImageDecryptService();
      final version = service.getDatVersion(inputPath);

      Uint8List decryptedData;
      switch (version) {
        case 0:
          decryptedData = service.decryptDatV3(inputPath, xorKey);
          break;
        case 1:
          decryptedData = service.decryptDatV4(
            inputPath,
            xorKey,
            asciiKey16(_defaultV1AesKey),
          );
          break;
        default:
          final keyToUse = aesKey;
          if (keyToUse == null || keyToUse.length != 16) {
            throw Exception('V4版本需要16字节AES密钥');
          }
          decryptedData = service.decryptDatV4(inputPath, xorKey, keyToUse);
          break;
      }

      final outputFile = File(outputPath);
      outputFile.writeAsBytesSync(decryptedData, flush: true);
    });
  }

  /// 自动检测版本并解密（同步版本，保持向后兼容）
  /// [inputPath] 输入文件路径
  /// [outputPath] 输出文件路径
  /// [xorKey] XOR 密钥
  /// [aesKey] AES 密钥（仅V4需要）
  void decryptDatAuto(
    String inputPath,
    String outputPath,
    int xorKey,
    Uint8List? aesKey,
  ) {
    final version = getDatVersion(inputPath);

    Uint8List decryptedData;
    switch (version) {
      case 0:
        decryptedData = decryptDatV3(inputPath, xorKey);
        break;
      case 1:
        decryptedData = decryptDatV4(
          inputPath,
          xorKey,
          asciiKey16(_defaultV1AesKey),
        );
        break;
      default:
        final keyToUse = aesKey;
        if (keyToUse == null || keyToUse.length != 16) {
          throw Exception('V4版本需要16字节AES密钥');
        }
        decryptedData = decryptDatV4(inputPath, xorKey, keyToUse);
        break;
    }

    // 同步写入输出文件
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(decryptedData, flush: true);
  }

  /// 将字符串转换为AES密钥（16字节）
  /// y.encode()[:16]
  /// 将字符串的每个字符作为ASCII字节，取前16字节
  static Uint8List hexToBytes16(String keyString) {
    // 去除空格，保留原始大小写
    final cleanKey = keyString.trim();

    if (cleanKey.isEmpty) {
      throw Exception('密钥不能为空');
    }

    if (cleanKey.length < 16) {
      throw Exception('AES密钥至少需要16个字符');
    }

    // 直接将字符串的每个字符转为ASCII字节
    final stringBytes = cleanKey.codeUnits;
    final bytes = Uint8List(16);

    for (int i = 0; i < 16; i++) {
      bytes[i] = stringBytes[i];
    }

    return bytes;
  }

  /// 将 16 字节 ASCII 字符串转为密钥（直接取前16字节）
  static Uint8List asciiKey16(String keyString) {
    return ImageDecryptCore.asciiKey16(keyString);
  }

  /// 从十六进制字符串转换XOR密钥
  static int hexToXorKey(String hexString) {
    if (hexString.isEmpty) {
      throw Exception('十六进制字符串不能为空');
    }

    // 去除可能的0x前缀
    final cleanHex = hexString.toLowerCase().replaceAll('0x', '');

    // 只取前2个字符（1字节）
    final hex = cleanHex.length >= 2 ? cleanHex.substring(0, 2) : cleanHex;
    return int.parse(hex, radix: 16);
  }
}
