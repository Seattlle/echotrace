import 'dart:ffi';
import 'dart:io';

/// CPU 信息工具（Windows 优先使用 WinAPI，避免 Platform.numberOfProcessors 偶发不准）。
class CpuInfo {
  static int get logicalProcessors {
    final fallback = Platform.numberOfProcessors;
    if (!Platform.isWindows) return fallback;

    // 1) WinAPI: GetActiveProcessorCount(ALL_PROCESSOR_GROUPS)
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getActiveProcessorCount = kernel32.lookupFunction<
          Uint32 Function(Uint16),
          int Function(int)>('GetActiveProcessorCount');
      const allProcessorGroups = 0xFFFF;
      final count = getActiveProcessorCount(allProcessorGroups);
      if (count > 0) return count;
    } catch (_) {}

    // 2) 环境变量（通常能给出逻辑处理器数）
    final env = Platform.environment['NUMBER_OF_PROCESSORS'];
    final parsed = env == null ? null : int.tryParse(env);
    if (parsed != null && parsed > 0) return parsed;

    return fallback;
  }
}

