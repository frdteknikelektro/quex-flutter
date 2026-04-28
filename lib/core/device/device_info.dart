import 'package:system_info_plus/system_info_plus.dart';

/// Device information utility for hardware detection.
class DeviceInfo {
  static int? _cachedRamGB;

  /// Get physical RAM in GB.
  /// Caches result after first call (platform channel calls are expensive).
  static Future<int> getPhysicalRamGB() async {
    if (_cachedRamGB != null) {
      return _cachedRamGB!;
    }

    try {
      final physicalMemoryMB = await SystemInfoPlus.physicalMemory;
      if (physicalMemoryMB == null) {
        print('[DeviceInfo] physicalMemory is null');
        return 0;
      }
      _cachedRamGB = (physicalMemoryMB / 1024).round();
      return _cachedRamGB!;
    } catch (e) {
      // Fallback to 0 if detection fails (will default to E2B)
      print('[DeviceInfo] Failed to get RAM: $e');
      return 0;
    }
  }

  /// Clear cached RAM value (useful for testing).
  static void clearCache() {
    _cachedRamGB = null;
  }
}
