import 'dart:convert';

/// Detects stuck model loops where the same token or tool call repeats.
class ResponseLoopGuard {
  ResponseLoopGuard({
    this.maxRepeatedTextTokens = 32,
    this.maxRepeatedToolCalls = 4,
  });

  final int maxRepeatedTextTokens;
  final int maxRepeatedToolCalls;

  String? _lastTextSignature;
  int _repeatedTextTokens = 0;
  String? _lastToolSignature;
  int _repeatedToolCalls = 0;

  String? recordTextToken(String token) {
    final signature = _normalize(token);
    if (signature.isEmpty) return null;

    if (signature == _lastTextSignature) {
      _repeatedTextTokens++;
    } else {
      _lastTextSignature = signature;
      _repeatedTextTokens = 1;
    }

    if (_repeatedTextTokens >= maxRepeatedTextTokens) {
      return 'Model repeated text token "$signature" '
          '$_repeatedTextTokens times. Stopping to avoid a loop.';
    }
    return null;
  }

  String? recordToolCall(String name, Map<String, dynamic> args) {
    final signature = '$name:${_canonicalJson(args)}';
    if (signature == _lastToolSignature) {
      _repeatedToolCalls++;
    } else {
      _lastToolSignature = signature;
      _repeatedToolCalls = 1;
    }

    _lastTextSignature = null;
    _repeatedTextTokens = 0;

    if (_repeatedToolCalls >= maxRepeatedToolCalls) {
      return 'Model repeated tool call "$name" with same args '
          '$_repeatedToolCalls times. Stopping to avoid a loop.';
    }
    return null;
  }

  String _normalize(String token) {
    return token.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _canonicalJson(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return jsonEncode(value);
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      final entries = keys.map((key) => '"$key":${_canonicalJson(value[key])}');
      return '{${entries.join(',')}}';
    }
    return jsonEncode(value.toString());
  }
}
