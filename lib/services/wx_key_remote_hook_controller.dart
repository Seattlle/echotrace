import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'wx_key_logger.dart';

typedef InitializeHookNative = Bool Function(Uint32 targetPid);
typedef InitializeHookDart = bool Function(int targetPid);

typedef PollKeyDataNative = Bool Function(
  Pointer<Utf8> keyBuffer,
  Int32 bufferSize,
);
typedef PollKeyDataDart = bool Function(Pointer<Utf8> keyBuffer, int bufferSize);

typedef GetStatusMessageNative = Bool Function(
  Pointer<Utf8> statusBuffer,
  Int32 bufferSize,
  Pointer<Int32> outLevel,
);
typedef GetStatusMessageDart = bool Function(
  Pointer<Utf8> statusBuffer,
  int bufferSize,
  Pointer<Int32> outLevel,
);

typedef CleanupHookNative = Bool Function();
typedef CleanupHookDart = bool Function();

typedef GetLastErrorMsgNative = Pointer<Utf8> Function();
typedef GetLastErrorMsgDart = Pointer<Utf8> Function();

class RemoteHookController {
  static DynamicLibrary? _dll;
  static InitializeHookDart? _initializeHook;
  static PollKeyDataDart? _pollKeyData;
  static GetStatusMessageDart? _getStatusMessage;
  static CleanupHookDart? _cleanupHook;
  static GetLastErrorMsgDart? _getLastErrorMsg;

  static Timer? _pollingTimer;
  static Function(String)? _onKeyReceived;
  static Function(String, int)? _onStatus;

  static bool initialize(String dllPath) {
    try {
      WxKeyLogger.info('加载控制器DLL: $dllPath');

      if (!File(dllPath).existsSync()) {
        WxKeyLogger.error('DLL文件不存在: $dllPath');
        return false;
      }

      _dll = DynamicLibrary.open(dllPath);
      WxKeyLogger.success('DLL加载成功');

      _initializeHook =
          _dll!.lookupFunction<InitializeHookNative, InitializeHookDart>(
        'InitializeHook',
      );

      _pollKeyData = _dll!.lookupFunction<PollKeyDataNative, PollKeyDataDart>(
        'PollKeyData',
      );

      _getStatusMessage =
          _dll!.lookupFunction<GetStatusMessageNative, GetStatusMessageDart>(
        'GetStatusMessage',
      );

      _cleanupHook =
          _dll!.lookupFunction<CleanupHookNative, CleanupHookDart>(
        'CleanupHook',
      );

      _getLastErrorMsg =
          _dll!.lookupFunction<GetLastErrorMsgNative, GetLastErrorMsgDart>(
        'GetLastErrorMsg',
      );

      WxKeyLogger.success('所有导出函数加载成功');
      return true;
    } catch (e) {
      WxKeyLogger.error('初始化DLL失败: $e');
      return false;
    }
  }

  static bool installHook({
    required int targetPid,
    required Function(String) onKeyReceived,
    Function(String, int)? onStatus,
  }) {
    try {
      if (_dll == null || _initializeHook == null) {
        WxKeyLogger.error('DLL未初始化，请先调用initialize()');
        return false;
      }

      WxKeyLogger.info('开始安装远程Hook，目标PID: $targetPid');

      _onKeyReceived = onKeyReceived;
      _onStatus = onStatus;

      final success = _initializeHook!(targetPid);

      if (success) {
        WxKeyLogger.success('远程Hook安装成功');
        _startPolling();
      } else {
        final error = getLastErrorMessage();
        WxKeyLogger.error('远程Hook安装失败: $error');
      }

      return success;
    } catch (e) {
      WxKeyLogger.error('安装Hook异常: $e');
      return false;
    }
  }

  static void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollData();
    });
    WxKeyLogger.info('已启动轮询定时器');
  }

  static void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    WxKeyLogger.info('已停止轮询定时器');
  }

  static void _pollData() {
    if (_pollKeyData == null || _getStatusMessage == null) {
      return;
    }

    try {
      final keyBuffer = calloc<Uint8>(65);
      try {
        if (_pollKeyData!(keyBuffer.cast<Utf8>(), 65)) {
          final keyString = _decodeUtf8String(keyBuffer, 65);
          WxKeyLogger.success('轮询到密钥数据: $keyString');

          if (_onKeyReceived != null) {
            _onKeyReceived!(keyString);
          }
        }
      } finally {
        calloc.free(keyBuffer);
      }

      for (int i = 0; i < 5; i++) {
        final statusBuffer = calloc<Uint8>(256);
        final levelPtr = calloc<Int32>();

        try {
          if (_getStatusMessage!(statusBuffer.cast<Utf8>(), 256, levelPtr)) {
            final statusString = _decodeUtf8String(statusBuffer, 256);
            final level = levelPtr.value;

            switch (level) {
              case 0:
                WxKeyLogger.info('[DLL] $statusString');
                break;
              case 1:
                WxKeyLogger.success('[DLL] $statusString');
                break;
              case 2:
                WxKeyLogger.error('[DLL] $statusString');
                break;
            }

            if (_onStatus != null) {
              _onStatus!(statusString, level);
            }
          } else {
            break;
          }
        } finally {
          calloc.free(statusBuffer);
          calloc.free(levelPtr);
        }
      }
    } catch (e) {
      WxKeyLogger.error('轮询数据异常: $e');
    }
  }

  static bool uninstallHook() {
    try {
      _stopPolling();

      if (_dll == null || _cleanupHook == null) {
        WxKeyLogger.warning('DLL未初始化');
        return false;
      }

      WxKeyLogger.info('开始卸载Hook');
      final success = _cleanupHook!();

      if (success) {
        WxKeyLogger.success('Hook卸载成功');
      } else {
        WxKeyLogger.error('Hook卸载失败');
      }

      _onKeyReceived = null;
      _onStatus = null;

      return success;
    } catch (e) {
      WxKeyLogger.error('卸载Hook异常: $e');
      return false;
    }
  }

  static String getLastErrorMessage() {
    try {
      if (_dll == null || _getLastErrorMsg == null) {
        return '未知错误';
      }

      final errorPtr = _getLastErrorMsg!();
      if (errorPtr == nullptr) {
        return '无错误';
      }

      return _decodeUtf8String(errorPtr.cast<Uint8>(), 512);
    } catch (e) {
      return '获取错误信息失败: $e';
    }
  }

  static void dispose() {
    uninstallHook();
    _dll = null;
    _initializeHook = null;
    _pollKeyData = null;
    _getStatusMessage = null;
    _cleanupHook = null;
    _getLastErrorMsg = null;
  }

  static String _decodeUtf8String(Pointer<Uint8> ptr, int maxLength) {
    try {
      final bytes = ptr.asTypedList(maxLength);
      int length = 0;
      for (int i = 0; i < bytes.length; i++) {
        if (bytes[i] == 0) {
          length = i;
          break;
        }
      }
      if (length == 0) {
        length = bytes.length;
      }
      return utf8.decode(bytes.sublist(0, length));
    } catch (e) {
      return '';
    }
  }
}

