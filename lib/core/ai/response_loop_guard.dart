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
  final List<String> _recentTextTokens = [];
  String? _lastToolSignature;
  int _repeatedToolCalls = 0;

  String? recordTextToken(
    String token, {
    bool suspicious = false,
  }) {
    final signature = _normalize(token);
    if (signature.isEmpty) return null;

    _recentTextTokens.add(signature);
    if (_recentTextTokens.length > 32) {
      _recentTextTokens.removeAt(0);
    }

    final repeatedSequence = _detectRepeatedSequence(
      minRepeats: suspicious ? 3 : 4,
      minWindow: suspicious ? 2 : 3,
    );
    if (repeatedSequence != null) {
      return suspicious
          ? 'Model repeated likely tool-call text sequence '
              '"$repeatedSequence". Stopping to avoid a loop.'
          : 'Model repeated text sequence "$repeatedSequence". '
              'Stopping to avoid a loop.';
    }

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
    _recentTextTokens.clear();

    if (_repeatedToolCalls >= maxRepeatedToolCalls) {
      return 'Model repeated tool call "$name" with same args '
          '$_repeatedToolCalls times. Stopping to avoid a loop.';
    }
    return null;
  }

  String _normalize(String token) {
    return token.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _detectRepeatedSequence({
    required int minRepeats,
    required int minWindow,
  }) {
    const maxWindow = 8;
    final tokens = _recentTextTokens;
    if (tokens.length < minWindow * minRepeats) return null;

    for (var window = minWindow;
        window <= maxWindow && window * minRepeats <= tokens.length;
        window++) {
      final pattern = tokens.sublist(tokens.length - window);
      var repeats = 1;
      var cursor = tokens.length - window;

      while (cursor - window >= 0) {
        final previous = tokens.sublist(cursor - window, cursor);
        if (!_listEquals(previous, pattern)) break;
        repeats++;
        cursor -= window;
      }

      if (repeats >= minRepeats && _looksMeaningful(pattern)) {
        return pattern.join(' ');
      }
    }
    return null;
  }

  bool _looksMeaningful(List<String> pattern) {
    if (pattern.length < 2) return false;

    final unique = pattern.toSet();
    if (unique.length < 2) return false;

    return pattern.any((token) => RegExp(r'[A-Za-z0-9]').hasMatch(token));
  }

  bool _listEquals(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
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
