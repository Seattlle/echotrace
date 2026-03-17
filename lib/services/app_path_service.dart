import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'config_service.dart';

/// 应用路径服务：统一解析可配置的文档目录
class AppPathService {
  static String? _cachedDocumentsPath;
  static String? _cachedCustomDocumentsPath;

  static Future<String> getDocumentsPath({ConfigService? configService}) async {
    final config = configService ?? ConfigService();
    final custom = (await config.getDocumentsPath())?.trim();
    if (custom != null && custom.isNotEmpty) {
      if (_cachedCustomDocumentsPath != custom) {
        _cachedCustomDocumentsPath = custom;
        _cachedDocumentsPath = custom;
      }
      return custom;
    }

    if (_cachedDocumentsPath != null && _cachedCustomDocumentsPath == null) {
      return _cachedDocumentsPath!;
    }

    final docs = await _resolveDocumentsDirectory(preferEnv: false);
    _cachedDocumentsPath = docs.path;
    _cachedCustomDocumentsPath = null;
    return docs.path;
  }

  static Future<String> getSystemDocumentsPath() async {
    final docs = await _resolveDocumentsDirectory(preferEnv: true);
    return docs.path;
  }

  static Future<Directory> getDocumentsDirectory({
    ConfigService? configService,
  }) async {
    final path = await getDocumentsPath(configService: configService);
    return Directory(path);
  }

  static void setCustomDocumentsPath(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      clearCache();
      return;
    }
    _cachedDocumentsPath = trimmed;
    _cachedCustomDocumentsPath = trimmed;
  }

  static void clearCache() {
    _cachedDocumentsPath = null;
    _cachedCustomDocumentsPath = null;
  }

  static Future<Directory> _resolveDocumentsDirectory({
    required bool preferEnv,
  }) async {
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPlatformDirectoryException {
      return _fallbackDocumentsDirectory(preferEnv: preferEnv);
    } catch (_) {
      return _fallbackDocumentsDirectory(preferEnv: preferEnv);
    }
  }

  static Future<Directory> _fallbackDocumentsDirectory({
    required bool preferEnv,
  }) async {
    final envPath = _documentsPathFromEnv();
    if (preferEnv && envPath != null) {
      return Directory(envPath);
    }

    try {
      return await getApplicationSupportDirectory();
    } on MissingPlatformDirectoryException {
      // Fall through to env/system temp fallback.
    } catch (_) {
      // Fall through to env/system temp fallback.
    }

    if (!preferEnv && envPath != null) {
      return Directory(envPath);
    }

    return Directory.systemTemp;
  }

  static String? _documentsPathFromEnv() {
    String? home;
    if (Platform.isWindows) {
      home = Platform.environment['USERPROFILE'];
      if ((home == null || home.isEmpty) &&
          Platform.environment['HOMEDRIVE'] != null &&
          Platform.environment['HOMEPATH'] != null) {
        home =
            '${Platform.environment['HOMEDRIVE']}${Platform.environment['HOMEPATH']}';
      }
    } else {
      home = Platform.environment['HOME'];
    }

    if (home == null || home.trim().isEmpty) {
      return null;
    }

    return '$home${Platform.pathSeparator}Documents';
  }
}
