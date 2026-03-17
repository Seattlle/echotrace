// CLI 导出入口：解析命令行参数，初始化 AppState，批量导出会话为 JSON/HTML/Excel
import 'dart:io';
import 'dart:async';

import 'package:flutter/widgets.dart';
import '../providers/app_state.dart';
import '../services/app_path_service.dart';
import '../services/chat_export_service.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import '../services/decrypt_service.dart';
import '../services/go_decrypt_ffi.dart';
import '../services/logger_service.dart';
import '../utils/path_utils.dart';
import '../models/message.dart';

class CliExportRunner {
  File? _logFile;
  bool _cancelled = false;
  StreamSubscription<ProcessSignal>? _sigIntSub;
  StreamSubscription<ProcessSignal>? _sigTermSub;

  Future<int?> tryHandle(List<String> args) async {
    final parsed = _parseArgs(args);
    if (parsed == null) {
      return null; // 未检测到 CLI 参数，继续正常启动 UI
    }

    // 初始化 CLI 本地日志文件，方便无控制台输出时排查
    final logPath = PathUtils.join(
      Directory.systemTemp.path,
      'echotrace_cli.log',
    );
    _logFile = File(logPath);
    _log('CLI 参数: ${args.join(' ')}, 日志: $logPath');

    if (parsed.showHelp) {
      _printUsage();
      return 0;
    }

    if (parsed.error != null) {
      stderr.writeln('参数错误: ${parsed.error}');
      _printUsage();
      return 1;
    }

    if (!Platform.isWindows) {
      stderr.writeln('当前命令行导出仅支持 Windows 平台');
      return 1;
    }

    // 进入 CLI 模式的显式提示，便于在无日志时确认程序已启动
    _log('EchoTrace CLI 模式已启动，正在初始化...');

    try {
      _setupSignalHandlers();

      WidgetsFlutterBinding.ensureInitialized();
      await logger.initialize();
      final config = ConfigService();
      await config.saveDatabaseMode('backup');

      if (parsed.update) {
        return await _runIncrementalUpdate(config);
      }

      final options = parsed.options;
      if (options == null) {
        stderr.writeln('未检测到有效的导出参数');
        return 1;
      }

      _log('EchoTrace 导出开始...');
      _log(
        '解析结果 -> 目录: ${options.exportDir}, 格式: ${options.format}, 全部时间: ${options.useAllTime}, '
        '开始: ${options.start}, 结束: ${options.end}',
      );

      // 初始化应用状态（包含数据库与配置）
      final appState = AppState();
      _log('正在初始化应用状态/数据库...');
      await appState.initialize();
      _log('应用状态初始化完成');

      final databaseService = appState.databaseService;
      if (!databaseService.isConnected) {
        _logError('数据库未连接，请先在应用内完成解密或配置实时数据库。');
        return 1;
      }

      // 准备导出目录
      final exportDir = Directory(options.exportDir);
      await exportDir.create(recursive: true);
      _log('导出目录: ${exportDir.path}');

      // 获取会话列表
      _log('正在读取会话列表...');
      final sessions = await databaseService.getSessions();
      if (sessions.isEmpty) {
        _log('未找到任何会话，已退出。');
        return 0;
      }

      // 计算时间范围
      final now = DateTime.now();
      int latestTs = 0;
      for (final session in sessions) {
        if (session.lastTimestamp > latestTs) {
          latestTs = session.lastTimestamp;
        }
      }
      final latestDate = latestTs > 0
          ? DateTime.fromMillisecondsSinceEpoch(latestTs * 1000)
          : now;
      final startTimestamp = options.useAllTime
          ? 0
          : _startOfDay(options.start ?? now).millisecondsSinceEpoch ~/ 1000;
      final endTimestamp = options.useAllTime
          ? latestDate.millisecondsSinceEpoch ~/ 1000
          : _endOfDay(options.end ?? latestDate).millisecondsSinceEpoch ~/ 1000;

      _log(
        '导出格式: ${options.format} | 时间范围: ${options.useAllTime ? "全部" : "${_fmtDate(options.start ?? latestDate)} 至 ${_fmtDate(options.end ?? latestDate)}"}',
      );

      final exportService = ChatExportService(databaseService);

      var successCount = 0;
      var failedCount = 0;
      var skippedEmpty = 0;
      var totalMessages = 0;

      for (final session in sessions) {
        if (_cancelled) {
          _logError('检测到中断，停止导出');
          break;
        }
        final displayName = session.displayName ?? session.username;
        _log('处理中: $displayName');

        final messages = await _loadMessages(
          databaseService,
          session.username,
          startTimestamp,
          endTimestamp,
        );

        if (messages.isEmpty) {
          skippedEmpty++;
          _log('  - 无消息，跳过');
          continue;
        }

        final sanitizedName = _sanitizeFileName(displayName);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = PathUtils.join(
          exportDir.path,
          '${sanitizedName}_$timestamp${_fileExtension(options.format)}',
        );

        bool success = false;
        switch (options.format) {
          case 'json':
            success = await exportService.exportToJson(
              session,
              messages,
              filePath: filePath,
            );
            break;
          case 'html':
            success = await exportService.exportToHtml(
              session,
              messages,
              filePath: filePath,
            );
            break;
          case 'excel':
            success = await exportService.exportToExcel(
              session,
              messages,
              filePath: filePath,
            );
            break;
        }

        if (success) {
          successCount++;
          totalMessages += messages.length;
          _log('   已导出 ${messages.length} 条消息 -> $filePath');
        } else {
          failedCount++;
          _logError('   导出失败: $displayName');
        }
      }

      if (_cancelled) {
        _logError('导出已被中断');
        return 1;
      }

      _log('导出完成: 成功 $successCount 个，会话消息 $totalMessages 条');
      if (skippedEmpty > 0) {
        _log('无消息跳过: $skippedEmpty 个');
      }
      if (failedCount > 0) {
        _logError('失败: $failedCount 个会话');
      }

      return failedCount == 0 ? 0 : 1;
    } catch (e, stack) {
      _logError('CLI 导出发生异常: $e');
      _logError(stack.toString());
      return 1;
    } finally {
      await _disposeSignalHandlers();
    }
  }

  _CliParseResult? _parseArgs(List<String> args) {
    if (args.isEmpty) {
      return null;
    }

    final wantsHelp = args.any((a) => a == '-h' || a == '--help');
    final wantsUpdate = args.any((a) => a == '--update' || a == '-u');
    final exportIndex =
        args.indexWhere((a) => a == '-e' || a == '--export' || a == '-export');

    if (!wantsUpdate && exportIndex == -1) {
      if (wantsHelp) {
        return _CliParseResult(showHelp: true);
      }
      return null;
    }

    if (wantsHelp) {
      return _CliParseResult(showHelp: true);
    }

    String? exportDir;
    String format = 'json';
    DateTime? start;
    DateTime? end;
    var useAllTime = true;

    if (exportIndex != -1) {
      if (exportIndex == args.length - 1) {
        return _CliParseResult(
          error: '请在 -e 后提供导出目录路径',
        );
      }
      exportDir = args[exportIndex + 1];
    }

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--format' && i + 1 < args.length) {
        format = args[i + 1].toLowerCase();
        if (!_isSupportedFormat(format)) {
          return _CliParseResult(error: '不支持的格式: $format');
        }
      } else if (arg == '--start' && i + 1 < args.length) {
        start = _parseDate(args[i + 1]);
        if (start == null) {
          return _CliParseResult(error: '无法解析开始日期: ${args[i + 1]}');
        }
        useAllTime = false;
      } else if (arg == '--end' && i + 1 < args.length) {
        end = _parseDate(args[i + 1]);
        if (end == null) {
          return _CliParseResult(error: '无法解析结束日期: ${args[i + 1]}');
        }
        useAllTime = false;
      } else if (arg == '--all') {
        useAllTime = true;
        start = null;
        end = null;
      }
    }

    if (!useAllTime && end != null && start != null && end.isBefore(start)) {
      return _CliParseResult(error: '结束日期不能早于开始日期');
    }

    return _CliParseResult(
      update: wantsUpdate,
      options: exportDir == null
          ? null
          : _CliExportOptions(
              exportDir: exportDir,
              format: format,
              start: start,
              end: end,
              useAllTime: useAllTime,
            ),
    );
  }

  void _printUsage() {
    stdout.writeln('EchoTrace 命令行模式 (仅 Windows)');
    stdout.writeln('导出：echotrace.exe -e <导出目录> [--format json|html|excel] [--start YYYY-MM-DD] [--end YYYY-MM-DD] [--all]');
    stdout.writeln('增量更新：echotrace.exe --update');
    stdout.writeln('示例: echotrace.exe -e C:\\\\Exports --format html --all');
  }

  static String _sanitizeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '_');
  }

  static String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static bool _isSupportedFormat(String format) {
    return format == 'json' || format == 'html' || format == 'excel';
  }

  static String _fileExtension(String format) {
    switch (format) {
      case 'html':
        return '.html';
      case 'excel':
        return '.xlsx';
      case 'json':
      default:
        return '.json';
    }
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  static DateTime? _parseDate(String input) {
    try {
      return DateTime.parse(input);
    } catch (_) {
      return null;
    }
  }

  Future<int> _runIncrementalUpdate(ConfigService config) async {
    _log('EchoTrace CLI 增量更新模式已启动，正在初始化...');

    final documentsDir = await AppPathService.getDocumentsDirectory(
      configService: config,
    );
    final documentsPath = documentsDir.path;
    final systemDocumentsPath = await AppPathService.getSystemDocumentsPath();

    String? configuredPath = await config.getDatabasePath();
    final manualWxid = await config.getManualWxid();

    if (configuredPath == null || configuredPath.isEmpty) {
      configuredPath = '$systemDocumentsPath${Platform.pathSeparator}xwechat_files';
    }

    _log('数据库路径: $configuredPath');
    _log('文档路径: $documentsPath');

    final allFiles = await _scanDatabasePath(
      configuredPath,
      documentsPath,
      manualWxid: manualWxid,
    );

    final toUpdate = allFiles.where((f) => f.needsUpdate).toList();
    if (toUpdate.isEmpty) {
      _log('未发现需要增量更新的数据库文件');
      return 0;
    }

    _log('发现 ${toUpdate.length} 个需要更新的数据库文件');

    final key = await config.getDecryptKey();
    if (key == null || key.isEmpty) {
      _logError('未配置解密密钥，请在应用设置中配置');
      return 1;
    }

    final decryptService = DecryptService();
    await decryptService.initialize();

    // 初始化 AppState 以确保配置等可用，并尝试关闭数据库释放文件句柄
    final appState = AppState();
    _log('正在初始化应用状态/数据库（用于释放锁）...');
    await appState.initialize();
    await appState.databaseService.close();
    _log('已关闭数据库连接，等待文件句柄释放...');
    await Future.delayed(const Duration(milliseconds: 2000));

    final goFfi = GoDecryptFFI();

    var successCount = 0;
    var failCount = 0;

    for (final file in toUpdate) {
      if (_cancelled) {
        _logError('检测到中断，停止增量更新');
        break;
      }

      _log('更新: ${file.fileName} (账号: ${file.wxidName})');

      try {
        final closeErr = goFfi.closeSelfFileHandles(file.originalPath);
        if (closeErr != null) {
          _log('  关闭文件句柄失败（可能未打开）: $closeErr');
        }
      } catch (e) {
        _log('  关闭句柄时发生异常: $e');
      }

      String decryptedTempPath;
      try {
        decryptedTempPath = await decryptService.decryptDatabase(
          file.originalPath,
          key,
          (current, total) {
            if (total <= 0) return;
            final percent = (current / total * 100).clamp(0, 100).toStringAsFixed(0);
            _log('  解密进度: $percent%');
          },
        );
      } catch (e) {
        _logError('  解密失败: $e');
        failCount++;
        continue;
      }

      final replaced = await _replaceDecryptedFile(
        decryptedTempPath,
        file.decryptedPath,
        goFfi,
      );

      try {
        await File(decryptedTempPath).delete();
      } catch (_) {}

      if (replaced) {
        successCount++;
        _log('  更新成功');
      } else {
        failCount++;
        _logError('  更新失败');
      }
    }

    _log('增量更新完成: 成功 $successCount，失败 $failCount');
    return failCount == 0 ? 0 : 1;
  }

  Future<bool> _replaceDecryptedFile(
    String sourceTempPath,
    String targetPath,
    GoDecryptFFI goFfi,
  ) async {
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      var deleted = false;
      for (var i = 0; i < 10; i++) {
        try {
          await targetFile.delete();
          deleted = true;
          break;
        } catch (_) {
          await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
        }
      }

      if (!deleted && await targetFile.exists()) {
        final unlockErr = goFfi.forceUnlockFile(targetPath);
        if (unlockErr == null) {
          try {
            await targetFile.delete();
            deleted = true;
          } catch (_) {}
        }
      }

      if (!deleted && await targetFile.exists()) {
        final oldPath = '$targetPath.old.${DateTime.now().millisecondsSinceEpoch}';
        try {
          await targetFile.rename(oldPath);
          deleted = true;
        } catch (_) {}
      }

      if (!deleted && await targetFile.exists()) {
        _logError('  无法删除或重命名旧文件，跳过');
        return false;
      }
    } else {
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
    }

    try {
      await File(sourceTempPath).copy(targetPath);
      return true;
    } catch (e) {
      _logError('  复制文件失败: $e');
      return false;
    }
  }

  Future<List<_DatabaseFileInfo>> _scanDatabasePath(
    String basePath,
    String documentsPath, {
    String? manualWxid,
  }) async {
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return [];
    }

    final pathParts = basePath.split(Platform.pathSeparator);
    final lastPart = pathParts.isNotEmpty ? pathParts.last : '';
    final normalizedManual = _normalizeWxid(manualWxid);

    final results = <_DatabaseFileInfo>[];

    if (lastPart == 'db_storage') {
      // 用户直接指定 db_storage 目录
      String accountName = 'unknown';
      if (pathParts.length >= 2) {
        final parentDirName = pathParts[pathParts.length - 2];
        accountName = _cleanAccountDirName(parentDirName);
      }
      if (normalizedManual != null && _normalizeWxid(accountName) != normalizedManual) {
        _log('选择的 db_storage 账号与配置 wxid 不匹配，已跳过扫描');
        return [];
      }
      results.addAll(
        await _scanDbStorageDirectory(baseDir, accountName, documentsPath),
      );
    } else {
      var foundAnyAccount = false;
      await for (final entity in baseDir.list()) {
        if (entity is! Directory) continue;
        final accountDirName = entity.path.split(Platform.pathSeparator).last;
        final cleanedAccountName = _cleanAccountDirName(accountDirName);
        if (normalizedManual != null &&
            _normalizeWxid(cleanedAccountName) != normalizedManual) {
          continue;
        }

        final dbStoragePath =
            '${entity.path}${Platform.pathSeparator}db_storage';
        final dbStorageDir = Directory(dbStoragePath);
        if (await dbStorageDir.exists()) {
          foundAnyAccount = true;
          _log('发现账号目录: $accountDirName -> 清理后: $cleanedAccountName (包含 db_storage)');
          results.addAll(
            await _scanDbStorageDirectory(
              dbStorageDir,
              cleanedAccountName,
              documentsPath,
            ),
          );
        }
      }

      if (!foundAnyAccount && normalizedManual != null) {
        _log('未找到账号目录，尝试使用手动输入的 wxid: $manualWxid');
        await for (final entity in baseDir.list()) {
          if (entity is! Directory) continue;

          final dbStoragePath =
              '${entity.path}${Platform.pathSeparator}db_storage';
          final dbStorageDir = Directory(dbStoragePath);
          if (!await dbStorageDir.exists()) continue;

          final dirName = entity.path.split(Platform.pathSeparator).last;
          if (normalizedManual != null && _normalizeWxid(dirName) != normalizedManual) {
            continue;
          }

          _log('使用手动 wxid 扫描数据库: $manualWxid');
          results.addAll(
            await _scanDbStorageDirectory(
              dbStorageDir,
              manualWxid,
              documentsPath,
            ),
          );
          break;
        }
      }
    }

    return results;
  }

  Future<List<_DatabaseFileInfo>> _scanDbStorageDirectory(
    Directory dbStorageDir,
    String accountName,
    String documentsPath,
  ) async {
    final dbFiles = await _findAllDbFiles(dbStorageDir);
    final results = <_DatabaseFileInfo>[];

    for (final dbFile in dbFiles) {
      final fileName = dbFile.path.split(Platform.pathSeparator).last;
      final originalStat = await dbFile.stat();
      final originalModified = originalStat.modified;

      final ourWorkDir = Directory(
        '$documentsPath${Platform.pathSeparator}EchoTrace',
      );
      final decryptedFileName = '${fileName.split('.').first}.db';
      final decryptedFilePath =
          '${ourWorkDir.path}${Platform.pathSeparator}$accountName${Platform.pathSeparator}$decryptedFileName';
      final decryptedFile = File(decryptedFilePath);

      final isDecrypted = await decryptedFile.exists();
      DateTime? decryptedModified;
      if (isDecrypted) {
        final decryptedStat = await decryptedFile.stat();
        decryptedModified = decryptedStat.modified;
      }

      results.add(
        _DatabaseFileInfo(
          originalPath: dbFile.path,
          fileName: fileName,
          wxidName: accountName,
          decryptedPath: decryptedFilePath,
          originalModified: originalModified,
          decryptedModified: decryptedModified,
        ),
      );
    }

    return results;
  }

  String _cleanAccountDirName(String dirName) {
    final trimmed = dirName.trim();
    if (trimmed.isEmpty) return trimmed;

    if (trimmed.toLowerCase().startsWith('wxid_')) {
      final match = RegExp(r'^(wxid_[^_]+)', caseSensitive: false)
          .firstMatch(trimmed);
      if (match != null) return match.group(1)!;
      return trimmed;
    }

    final suffixMatch =
        RegExp(r'^(.+)_([a-zA-Z0-9]{4})$').firstMatch(trimmed);
    if (suffixMatch != null) return suffixMatch.group(1)!;

    return trimmed;
  }

  String? _normalizeWxid(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.toLowerCase().startsWith('wxid_')) {
      final suffixMatch =
          RegExp(r'^(.+)_([a-zA-Z0-9]{4})$').firstMatch(trimmed);
      if (suffixMatch != null) return suffixMatch.group(1);
      return trimmed;
    }

    final match =
        RegExp(r'^(wxid_[^_]+)', caseSensitive: false).firstMatch(trimmed);
    if (match != null) return match.group(1)!.toLowerCase();
    return trimmed.toLowerCase();
  }

  Future<List<File>> _findAllDbFiles(Directory dir) async {
    final List<File> dbFiles = [];

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.db')) {
          dbFiles.add(entity);
        }
      }
    } catch (e) {
      // Ignore errors
    }

    return dbFiles;
  }

  Future<List<Message>> _loadMessages(
    DatabaseService databaseService,
    String sessionId,
    int startTimestamp,
    int endTimestamp,
  ) async {
    // 备份模式：直接按时间查询
    if (databaseService.mode == DatabaseMode.decrypted) {
      return databaseService.getMessagesByDate(
        sessionId,
        startTimestamp,
        endTimestamp,
        ascending: true,
      );
    }

    // 实时模式：分页读取全部消息，再按时间过滤
    const batchSize = 500;
    var offset = 0;
    final results = <Message>[];
    final seenLocalIds = <int>{};

    int? totalCount;
    try {
      totalCount = await databaseService.getMessageCount(sessionId);
    } catch (_) {}

    while (true) {
      if (totalCount != null && offset >= totalCount) {
        break;
      }

      final batch = await databaseService.getMessages(
        sessionId,
        limit: batchSize,
        offset: offset,
      );

      if (batch.isEmpty) break;

      for (final m in batch) {
        if (m.createTime < startTimestamp || m.createTime > endTimestamp) {
          continue;
        }
        if (seenLocalIds.add(m.localId)) {
          results.add(m);
        }
      }

      offset += batch.length;
      if (batch.length < batchSize) break;
    }

    results.sort((a, b) {
      if (a.createTime != b.createTime) {
        return a.createTime.compareTo(b.createTime);
      }
      return a.localId.compareTo(b.localId);
    });
    return results;
  }

  void _log(String message) {
    final line = '[CLI] $message';
    stdout.writeln(line);
    _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  void _logError(String message) {
    final line = '[CLI][ERR] $message';
    stderr.writeln(line);
    _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  void _setupSignalHandlers() {
    _sigIntSub = ProcessSignal.sigint.watch().listen((_) {
      _cancelled = true;
      _logError('收到 Ctrl+C/SIGINT，准备中止...');
    });
    if (!Platform.isWindows) {
      try {
        _sigTermSub = ProcessSignal.sigterm.watch().listen((_) {
          _cancelled = true;
          _logError('收到 SIGTERM，准备中止...');
        });
      } catch (_) {
        // SIGTERM 可能不支持，忽略
      }
    }
  }

  Future<void> _disposeSignalHandlers() async {
    await _sigIntSub?.cancel();
    await _sigTermSub?.cancel();
  }
}

class _CliExportOptions {
  _CliExportOptions({
    required this.exportDir,
    required this.format,
    required this.useAllTime,
    this.start,
    this.end,
  });

  final String exportDir;
  final String format;
  final bool useAllTime;
  final DateTime? start;
  final DateTime? end;
}

class _CliParseResult {
  _CliParseResult({
    this.options,
    this.update = false,
    this.error,
    this.showHelp = false,
  });

  final _CliExportOptions? options;
  final bool update;
  final String? error;
  final bool showHelp;

  String get exportDir => options?.exportDir ?? '';
  String get format => options?.format ?? 'json';
  bool get useAllTime => options?.useAllTime ?? true;
  DateTime? get start => options?.start;
  DateTime? get end => options?.end;
}

/// 用于 CLI 增量更新的数据库文件信息
class _DatabaseFileInfo {
  _DatabaseFileInfo({
    required this.originalPath,
    required this.fileName,
    required this.wxidName,
    required this.decryptedPath,
    required this.originalModified,
    this.decryptedModified,
  });

  final String originalPath;
  final String fileName;
  final String wxidName;
  final String decryptedPath;
  final DateTime originalModified;
  final DateTime? decryptedModified;

  bool get isDecrypted => decryptedModified != null;
  bool get needsUpdate {
    if (!isDecrypted) return false;
    if (decryptedModified == null) return false;
    return originalModified.isAfter(decryptedModified!);
  }
}
