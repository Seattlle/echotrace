import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'wx_key_logger.dart';

class WxKeyService {
  static Future<String> extractDllToTemp() async {
    try {
      final dllData = await rootBundle.load('assets/dll/wx_key.dll');

      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dllPath = path.join(
        tempDir.path,
        'wx_key_controller_$timestamp.dll',
      );
      final dllFile = File(dllPath);

      await dllFile.writeAsBytes(dllData.buffer.asUint8List(), flush: true);
      await WxKeyLogger.success('DLL已提取到: $dllPath');

      _cleanupOldDllFiles(tempDir);
      return dllPath;
    } catch (e, stackTrace) {
      await WxKeyLogger.error('提取DLL失败', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> _cleanupOldDllFiles(Directory tempDir) async {
    try {
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          if (fileName.startsWith('wx_key_controller_') &&
              fileName.endsWith('.dll')) {
            try {
              final stat = await entity.stat();
              final age = DateTime.now().difference(stat.modified);
              if (age.inHours >= 1) {
                await entity.delete();
                await WxKeyLogger.info('已清理旧DLL: $fileName');
              }
            } catch (e) {
              // 忽略单个文件删除失败
            }
          }
        }
      }
    } catch (e) {
      await WxKeyLogger.warning('清理旧DLL文件失败: $e');
    }
  }
}

