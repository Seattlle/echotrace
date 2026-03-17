import 'logger_service.dart';

/// 轻量日志服务（用于密钥提取流程，统一写入全局日志）
class WxKeyLogger {
  static Future<void> init() async {
    await logger.initialize();
    await info('密钥服务启动');
  }

  static Future<void> close() async {
    await info('密钥服务关闭');
  }

  static Future<void> info(String message) async {
    await logger.info('WxKey', message);
  }

  static Future<void> success(String message) async {
    await logger.info('WxKey', message);
  }

  static Future<void> warning(String message) async {
    await logger.warning('WxKey', message);
  }

  static Future<void> error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) async {
    await logger.error('WxKey', message, error, stackTrace);
  }
}

