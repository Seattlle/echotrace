import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:path/path.dart' as path;
import 'package:pointycastle/export.dart';
import 'package:file_picker/file_picker.dart';
import 'wx_key_dll_injector.dart';
import 'wx_key_logger.dart';

class ImageKeyResult {
  final int? xorKey;
  final String? aesKey;
  final String? error;
  final bool success;
  final bool needManualSelection;

  ImageKeyResult.success(this.xorKey, this.aesKey)
      : success = true,
        error = null,
        needManualSelection = false;

  ImageKeyResult.failure(this.error, {this.needManualSelection = false})
      : success = false,
        xorKey = null,
        aesKey = null;
}

class ImageKeyService {
  static Future<String?> getWeChatCacheDirectory({
    String? rootPath,
    String? preferredWxid,
  }) async {
    final directories = await findWeChatCacheDirectories(
      rootPath: rootPath,
      preferredWxid: preferredWxid,
    );
    if (directories.isEmpty) {
      return null;
    }
    return directories.first;
  }

  static Future<List<String>> findWeChatCacheDirectories({
    String? rootPath,
    String? preferredWxid,
  }) async {
    try {
      Directory wechatFilesDir;
      if (rootPath != null && rootPath.trim().isNotEmpty) {
        wechatFilesDir = Directory(rootPath);
      } else {
        final documentsPath = Platform.environment['USERPROFILE'];
        if (documentsPath == null) {
          return [];
        }
        final wechatFilesPath =
            path.join(documentsPath, 'Documents', 'xwechat_files');
        wechatFilesDir = Directory(wechatFilesPath);
      }

      if (!await wechatFilesDir.exists()) {
        return [];
      }

      if (await _directoryHasDbStorage(wechatFilesDir) ||
          await _directoryHasImageCache(wechatFilesDir)) {
        return [wechatFilesDir.path];
      }

      final highConfidence = <String>[];
      final lowConfidence = <String>[];

      final normalizedPreferred = _normalizeWxid(preferredWxid);
      if (normalizedPreferred != null && normalizedPreferred.isNotEmpty) {
        final preferredDir = await _findPreferredWxidDir(
          wechatFilesDir,
          normalizedPreferred,
        );
        if (preferredDir != null) {
          return [preferredDir];
        }
      }

      await for (var entity
          in wechatFilesDir.list(recursive: false, followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }

        final dirName = path.basename(entity.path);
        if (!_isPotentialAccountDirectory(dirName)) {
          continue;
        }

        final hasDbStorage = await _directoryHasDbStorage(entity);
        final hasImageCache = await _directoryHasImageCache(entity);

        if (hasDbStorage || hasImageCache) {
          highConfidence.add(entity.path);
        } else {
          lowConfidence.add(entity.path);
        }
      }

      if (highConfidence.isNotEmpty) {
        highConfidence.sort(
          (a, b) => path.basename(a).compareTo(path.basename(b)),
        );
        return highConfidence;
      }

      lowConfidence.sort(
        (a, b) => path.basename(a).compareTo(path.basename(b)),
      );
      return lowConfidence;
    } catch (e, _) {
      return [];
    }
  }

  static String? _normalizeWxid(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final cleaned = trimmed.replaceFirst(RegExp(r'_[a-zA-Z0-9]{4}$'), '');
    final lower = cleaned.toLowerCase();
    if (!lower.startsWith('wxid_')) return lower;
    final match =
        RegExp(r'^(wxid_[^_]+)', caseSensitive: false).firstMatch(cleaned);
    if (match != null) return match.group(1)!.toLowerCase();
    return lower;
  }

  static Future<String?> _findPreferredWxidDir(
    Directory rootDir,
    String normalizedPreferred,
  ) async {
    await for (var entity
        in rootDir.list(recursive: false, followLinks: false)) {
      if (entity is! Directory) continue;
      final dirName = path.basename(entity.path);
      final normalizedDir = _normalizeWxid(dirName);
      if (normalizedDir == null) continue;
      if (normalizedDir == normalizedPreferred) {
        return entity.path;
      }
    }
    return null;
  }

  static bool _isPotentialAccountDirectory(String dirName) {
    final lower = dirName.toLowerCase();
    if (lower.startsWith('all') ||
        lower.startsWith('applet') ||
        lower.startsWith('backup') ||
        lower.startsWith('wmpf')) {
      return false;
    }

    return dirName.startsWith('wxid_') || dirName.length > 5;
  }

  static Future<bool> _directoryHasDbStorage(Directory directory) async {
    try {
      final dbStoragePath = path.join(directory.path, 'db_storage');
      final dbStorageDir = Directory(dbStoragePath);
      return await dbStorageDir.exists();
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _directoryHasImageCache(Directory directory) async {
    try {
      final imagePath = path.join(directory.path, 'FileStorage', 'Image');
      final imageDir = Directory(imagePath);
      return await imageDir.exists();
    } catch (e) {
      return false;
    }
  }

  static Future<List<File>> _findTemplateDatFiles(String userDir) async {
    final files = <File>[];
    try {
      const int maxFiles = 32;
      final userDirEntity = Directory(userDir);
      if (!await userDirEntity.exists()) {
        return [];
      }

      await for (var entity in userDirEntity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          if (fileName.endsWith('_t.dat')) {
            files.add(entity);
            if (files.length >= maxFiles) {
              break;
            }
          }
        }
      }

      if (files.isEmpty) {
        return [];
      }

      files.sort((a, b) {
        final pathA = a.path;
        final pathB = b.path;
        final regExp = RegExp(r'(\d{4}-\d{2})');
        final matchA = regExp.firstMatch(pathA);
        final matchB = regExp.firstMatch(pathB);
        if (matchA != null && matchB != null) {
          return matchB.group(1)!.compareTo(matchA.group(1)!);
        }
        return 0;
      });

      return files.take(16).toList();
    } catch (e, _) {
      return [];
    }
  }

  static Future<int?> _getXorKey(List<File> templateFiles) async {
    try {
      final lastBytesMap = <String, int>{};

      for (var file in templateFiles) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.length >= 2) {
            final lastTwo = bytes.sublist(bytes.length - 2);
            final key = '${lastTwo[0]}_${lastTwo[1]}';
            lastBytesMap[key] = (lastBytesMap[key] ?? 0) + 1;
          }
        } catch (e) {
          continue;
        }
      }

      if (lastBytesMap.isEmpty) {
        return null;
      }

      var maxCount = 0;
      String? mostCommon;
      lastBytesMap.forEach((key, count) {
        if (count > maxCount) {
          maxCount = count;
          mostCommon = key;
        }
      });

      if (mostCommon != null) {
        final parts = mostCommon!.split('_');
        final x = int.parse(parts[0]);
        final y = int.parse(parts[1]);

        final xorKey = x ^ 0xFF;
        final check = y ^ 0xD9;

        if (xorKey == check) {
          return xorKey;
        }
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  static Future<Uint8List?> _getCiphertextFromTemplate(
    List<File> templateFiles,
  ) async {
    for (final file in templateFiles) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length < 0x1F) {
          continue;
        }

        final header = bytes.sublist(0, 6);
        if (header[0] == 0x07 &&
            header[1] == 0x08 &&
            header[2] == 0x56 &&
            header[3] == 0x32 &&
            header[4] == 0x08 &&
            header[5] == 0x07) {
          return bytes.sublist(0xF, 0x1F);
        }
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  static bool _verifyKey(Uint8List encrypted, Uint8List aesKey) {
    try {
      final key = aesKey.sublist(0, 16);
      final cipher = ECBBlockCipher(AESEngine());
      cipher.init(false, KeyParameter(key));

      final decrypted = Uint8List(encrypted.length);
      for (int i = 0; i < encrypted.length; i += 16) {
        cipher.processBlock(
          encrypted,
          i,
          decrypted,
          i,
        );
      }

      return decrypted.length >= 3 &&
          decrypted[0] == 0xFF &&
          decrypted[1] == 0xD8 &&
          decrypted[2] == 0xFF;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> _getAesKeyFromMemory(
    int pid,
    Uint8List ciphertext,
    void Function(String message)? onProgress,
  ) async {
    try {
      await WxKeyLogger.info('开始内存搜索，目标进程: $pid');

      final hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
      if (hProcess == 0) {
        final lastError = GetLastError();
        await WxKeyLogger.error('无法打开进程进行内存搜索，错误码: $lastError');
        return null;
      }

      try {
        final memoryRegions = _getMemoryRegions(hProcess);
        await WxKeyLogger.info('找到 ${memoryRegions.length} 个内存区域');
        final totalRegions = memoryRegions.length;
        if (totalRegions == 0) {
          onProgress?.call('未找到可扫描的内存区域');
        }

        var scannedCount = 0;
        var skippedCount = 0;
        const chunkSize = 4 * 1024 * 1024;
        const overlap = 65;

        for (final region in memoryRegions) {
          final baseAddress = region.$1;
          final regionSize = region.$2;

          if (regionSize > 100 * 1024 * 1024) {
            skippedCount++;
            await WxKeyLogger.warning(
              '跳过过大内存区域: 0x${baseAddress.toRadixString(16)} size=$regionSize',
            );
            continue;
          }

          scannedCount++;
          if (scannedCount % 10 == 0) {
            onProgress?.call('正在扫描微信内存... ($scannedCount/$totalRegions)');
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }

          var offset = 0;
          Uint8List? trailing;

          while (offset < regionSize) {
            final remaining = regionSize - offset;
            final currentChunkSize =
                remaining > chunkSize ? chunkSize : remaining;
            final chunk = _readProcessMemory(
              hProcess,
              baseAddress + offset,
              currentChunkSize,
            );

            if (chunk == null || chunk.isEmpty) {
              await WxKeyLogger.warning(
                '跳过无法读取的内存块: base=0x${(baseAddress + offset).toRadixString(16)} size=$currentChunkSize',
              );
              offset += currentChunkSize;
              trailing = null;
              continue;
            }

            Uint8List dataToScan;
            if (trailing != null && trailing.isNotEmpty) {
              dataToScan = Uint8List(trailing.length + chunk.length);
              dataToScan.setAll(0, trailing);
              dataToScan.setAll(trailing.length, chunk);
            } else {
              dataToScan = chunk;
            }

            for (var i = 0; i < dataToScan.length - 34; i++) {
              final byte = dataToScan[i];
              if (_isAlphaNumAscii(byte)) {
                continue;
              }

              var isValid = true;
              for (var j = 1; j <= 32; j++) {
                if (i + j >= dataToScan.length ||
                    !_isAlphaNumAscii(dataToScan[i + j])) {
                  isValid = false;
                  break;
                }
              }

              if (isValid) {
                if (i + 33 < dataToScan.length &&
                    _isAlphaNumAscii(dataToScan[i + 33])) {
                  isValid = false;
                }
              }

              if (isValid) {
                try {
                  final keyBytes = dataToScan.sublist(i + 1, i + 33);
                  if (_verifyKey(ciphertext, keyBytes)) {
                    await WxKeyLogger.success('在第 $scannedCount 个区域找到AES密钥');
                    onProgress?.call('已找到AES密钥，正在校验...');
                    CloseHandle(hProcess);
                    return String.fromCharCodes(keyBytes);
                  }
                } catch (e) {
                  await WxKeyLogger.warning('校验密钥时出现异常: $e');
                }
              }
            }

            for (var i = 0; i < dataToScan.length - 65; i++) {
              if (!_isUtf16AsciiKey(dataToScan, i)) {
                continue;
              }

              try {
                final keyBytes = Uint8List(32);
                for (var j = 0; j < 32; j++) {
                  keyBytes[j] = dataToScan[i + (j * 2)];
                }

                if (_verifyKey(ciphertext, keyBytes)) {
                  await WxKeyLogger.success(
                    '在第 $scannedCount 个区域找到AES密钥(UTF-16)',
                  );
                  onProgress?.call('已找到AES密钥，正在校验...');
                  CloseHandle(hProcess);
                  return String.fromCharCodes(keyBytes);
                }
              } catch (e) {
                await WxKeyLogger.warning('校验UTF-16密钥时出现异常: $e');
              }
            }

            final start = dataToScan.length - overlap;
            trailing = dataToScan.sublist(start < 0 ? 0 : start);
            offset += currentChunkSize;
          }
        }

        await WxKeyLogger.warning(
          '内存搜索完成但未找到密钥，扫描: $scannedCount, 跳过: $skippedCount',
        );
        CloseHandle(hProcess);
        return null;
      } catch (e) {
        await WxKeyLogger.error('内存搜索异常: $e');
        CloseHandle(hProcess);
        return null;
      }
    } catch (e) {
      await WxKeyLogger.error('获取内存密钥失败: $e');
      return null;
    }
  }

  static bool _isAlphaNumAscii(int byte) {
    return (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x30 && byte <= 0x39);
  }

  static bool _isUtf16AsciiKey(Uint8List data, int start) {
    if (start + 64 > data.length) {
      return false;
    }

    for (var j = 0; j < 32; j++) {
      final charByte = data[start + (j * 2)];
      final nullByte = data[start + (j * 2) + 1];
      if (nullByte != 0x00 || !_isAlphaNumAscii(charByte)) {
        return false;
      }
    }

    return true;
  }

  static List<(int, int)> _getMemoryRegions(int hProcess) {
    final regions = <(int, int)>[];
    var address = 0;
    final mbi = calloc<MEMORY_BASIC_INFORMATION>();

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final virtualQueryEx = kernel32.lookupFunction<
          IntPtr Function(
            IntPtr,
            Pointer,
            Pointer<MEMORY_BASIC_INFORMATION>,
            IntPtr,
          ),
          int Function(
            int,
            Pointer,
            Pointer<MEMORY_BASIC_INFORMATION>,
            int,
          )>('VirtualQueryEx');

      while (address >= 0 && address < 0x7FFFFFFFFFFF) {
        final result = virtualQueryEx(
          hProcess,
          Pointer.fromAddress(address),
          mbi,
          sizeOf<MEMORY_BASIC_INFORMATION>(),
        );

        if (result == 0) {
          break;
        }

        if (mbi.ref.State == MEM_COMMIT &&
            _isReadableProtect(mbi.ref.Protect) &&
            _isCandidateRegionType(mbi.ref.Type)) {
          regions.add((mbi.ref.BaseAddress.address, mbi.ref.RegionSize));
        }

        final nextAddress = address + mbi.ref.RegionSize;
        if (nextAddress <= address) {
          break;
        }
        address = nextAddress;
      }
    } finally {
      free(mbi);
    }

    return regions;
  }

  static bool _isReadableProtect(int protect) {
    if (protect == PAGE_NOACCESS) {
      return false;
    }
    if ((protect & PAGE_GUARD) != 0) {
      return false;
    }
    return true;
  }

  static bool _isCandidateRegionType(int type) {
    return type == MEM_PRIVATE || type == MEM_MAPPED || type == MEM_IMAGE;
  }

  static Uint8List? _readProcessMemory(
    int hProcess,
    int address,
    int size,
  ) {
    try {
      final buffer = calloc<Uint8>(size);
      final bytesRead = calloc<SIZE_T>();

      try {
        final result = ReadProcessMemory(
          hProcess,
          Pointer.fromAddress(address),
          buffer,
          size,
          bytesRead,
        );

        final readCount = result != 0 ? bytesRead.value : 0;
        if (result == 0 || readCount == 0) {
          return null;
        }

        return Uint8List.fromList(buffer.asTypedList(readCount));
      } finally {
        free(buffer);
        free(bytesRead);
      }
    } catch (e) {
      unawaited(WxKeyLogger.error('读取进程内存失败: $e'));
      return null;
    }
  }

  static Future<String?> selectWeChatCacheDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '请选择微信账号目录（与微信-设置-账号与存储-存储位置一致）',
      );

      return selectedDirectory;
    } catch (e) {
      return null;
    }
  }

  static Future<ImageKeyResult> getImageKeys({
    String? manualDirectory,
    String? rootPath,
    String? preferredWxid,
    void Function(String message)? onProgress,
  }) async {
    try {
      await WxKeyLogger.info('开始获取图片密钥');
      onProgress?.call('正在定位微信缓存目录...');

      String? cacheDir;

      if (manualDirectory != null && manualDirectory.isNotEmpty) {
        cacheDir = manualDirectory;
      } else {
        cacheDir = await getWeChatCacheDirectory(
          rootPath: rootPath,
          preferredWxid: preferredWxid,
        );
      }

      if (cacheDir == null) {
        await WxKeyLogger.error('未找到微信缓存目录');
        return ImageKeyResult.failure(
          '未找到微信缓存目录，请手动选择目录',
          needManualSelection: true,
        );
      }
      await WxKeyLogger.info('找到缓存目录: $cacheDir');
      onProgress?.call('正在收集模板文件...');

      final templateFiles = await _findTemplateDatFiles(cacheDir);
      if (templateFiles.isEmpty) {
        await WxKeyLogger.error('未找到模板文件');
        return ImageKeyResult.failure('未找到模板文件，可能该微信账号没有图片缓存');
      }
      await WxKeyLogger.info('找到 ${templateFiles.length} 个模板文件');
      onProgress?.call('找到 ${templateFiles.length} 个模板文件，正在计算XOR密钥...');

      final xorKey = await _getXorKey(templateFiles);
      if (xorKey == null) {
        await WxKeyLogger.error('无法获取XOR密钥');
        return ImageKeyResult.failure('无法获取XOR密钥');
      }
      await WxKeyLogger.info(
        '成功获取XOR密钥: ${xorKey.toRadixString(16).padLeft(2, '0')}',
      );
      onProgress?.call('XOR密钥获取成功，正在读取加密数据...');

      final ciphertext = await _getCiphertextFromTemplate(templateFiles);
      if (ciphertext == null) {
        await WxKeyLogger.error('无法读取加密数据');
        return ImageKeyResult.failure('无法读取加密数据');
      }
      await WxKeyLogger.info('成功读取 ${ciphertext.length} 字节加密数据');
      onProgress?.call('成功读取加密数据，正在检查微信进程...');

      final pids = DllInjector.findProcessIds('Weixin.exe');
      if (pids.isEmpty) {
        await WxKeyLogger.error('微信进程未运行');
        return ImageKeyResult.failure('微信进程未运行');
      }
      await WxKeyLogger.info('找到微信进程 PID: ${pids.first}');
      onProgress?.call('已定位微信进程，正在扫描内存获取AES密钥...');

      await WxKeyLogger.info('开始从内存中搜索AES密钥');
      final aesKey = await _getAesKeyFromMemory(
        pids.first,
        ciphertext,
        onProgress,
      ).timeout(const Duration(seconds: 45), onTimeout: () async {
        await WxKeyLogger.error('内存搜索超时，可能被系统权限或安全软件阻止');
        return null;
      });
      if (aesKey == null) {
        await WxKeyLogger.error('无法从内存中获取AES密钥');
        return ImageKeyResult.failure(
          '无法从内存中获取AES密钥。\n'
          '建议操作步骤：\n'
          '1. 彻底关闭当前登录的微信。\n'
          '2. 重新启动微信并登录。\n'
          '3. 打开朋友圈，寻找带图片的动态。\n'
          '4. 点击图片，再点击右上角打开大图。\n'
          '5. 重复步骤3和4，大概2-3次即可。\n'
          '6. 迅速回到工具内获取图片密钥。',
        );
      }
      await WxKeyLogger.success('成功获取AES密钥: ${aesKey.substring(0, 16)}');

      await WxKeyLogger.success('图片密钥获取完成');
      return ImageKeyResult.success(xorKey, aesKey.substring(0, 16));
    } catch (e, stackTrace) {
      await WxKeyLogger.error('获取密钥失败', e, stackTrace);
      return ImageKeyResult.failure('获取密钥失败: $e');
    }
  }
}
