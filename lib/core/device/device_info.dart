import 'package:flutter/foundation.dart';
import 'package:system_info_plus/system_info_plus.dart';

/// Device information utility for hardware detection.
class DeviceInfo {
  static int? _cachedRamGB;
  static int? _cachedRamMB;

  /// Get physical RAM in MB (exact, not rounded).
  /// Caches result after first call (platform channel calls are expensive).
  static Future<int> getPhysicalRamMB() async {
    if (_cachedRamMB != null) {
      return _cachedRamMB!;
    }

    try {
      final physicalMemoryMB = await SystemInfoPlus.physicalMemory;
      if (physicalMemoryMB == null) {
        debugPrint('[DeviceInfo] physicalMemory is null');
        return 0;
      }
      _cachedRamMB = physicalMemoryMB;
      return _cachedRamMB!;
    } catch (e) {
      debugPrint('[DeviceInfo] Failed to get RAM: $e');
      return 0;
    }
  }

  /// Get physical RAM in GB.
  /// Caches result after first call (platform channel calls are expensive).
  static Future<int> getPhysicalRamGB() async {
    if (_cachedRamGB != null) {
      return _cachedRamGB!;
    }

    try {
      final physicalMemoryMB = await SystemInfoPlus.physicalMemory;
      if (physicalMemoryMB == null) {
        debugPrint('[DeviceInfo] physicalMemory is null');
        return 0;
      }
      _cachedRamGB = (physicalMemoryMB / 1024).round();
      return _cachedRamGB!;
    } catch (e) {
      // Fallback to 0 if detection fails (will default to E2B)
      debugPrint('[DeviceInfo] Failed to get RAM: $e');
      return 0;
    }
  }

  /// Clear cached RAM value (useful for testing).
  static void clearCache() {
    _cachedRamGB = null;
    _cachedRamMB = null;
  }
}
