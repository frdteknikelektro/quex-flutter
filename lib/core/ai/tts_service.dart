import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService {
  static const _mutedKey = 'tts_muted';

  final FlutterTts _tts = FlutterTts();
  bool _muted = false;

  bool get isMuted => _muted;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _muted = prefs.getBool(_mutedKey) ?? false;
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> setLocale(String locale) => _tts.setLanguage(locale);

  Future<void> speak(String text) async {
    if (_muted || text.isEmpty) return;
    final plain = sanitizeForSpeech(text);
    if (plain.isEmpty) return;
    await _tts.stop();
    await _tts.speak(plain);
  }

  Future<void> stop() async => _tts.stop();

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (value) await _tts.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutedKey, value);
  }

  Future<void> dispose() async => _tts.stop();

  @visibleForTesting
  static String sanitizeForSpeech(String text) {
    if (text.isEmpty) return '';

    var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    normalized = _decodeCommonEntities(normalized);

    final lines = normalized.split('\n');
    final buffer = StringBuffer();
    var inCodeFence = false;
    var previousEndedWithPunctuation = false;
    var previousWasTableRow = false;
    var firstContentLine = true;

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      final currentIsTableRow =
          trimmed.contains('|') && !_isTableSeparator(trimmed);

      if (_isFenceLine(trimmed)) {
        inCodeFence = !inCodeFence;
        continue;
      }

      if (trimmed.isEmpty) {
        continue;
      }

      if (inCodeFence) {
        continue;
      }

      var line = trimmed;
      if (_isHorizontalRule(line) || _isTableSeparator(line)) {
        continue;
      }

      line = line.replaceFirst(RegExp(r'^>+\s*'), '');
      line = line.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      line = line.replaceFirst(RegExp(r'^\s*[-*+]\s+'), '');
      line = line.replaceFirst(RegExp(r'^\s*\d+[.)]\s+'), '');
      line = line.replaceAll(RegExp(r'^(\||\s)+|(\||\s)+$'), '');
      line = line.replaceAll('|', ' ');

      line = _stripInlineMarkdown(line);
      line = _stripEmoji(line);
      line = line.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

      if (line.isEmpty) continue;

      if (!firstContentLine) {
        final joinWithSpace = previousEndedWithPunctuation ||
            (previousWasTableRow && currentIsTableRow);
        buffer.write(joinWithSpace ? ' ' : '. ');
      }

      buffer.write(line);
      previousEndedWithPunctuation = _endsWithSentencePunctuation(line);
      previousWasTableRow = currentIsTableRow;
      firstContentLine = false;
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAllMapped(
          RegExp(r'\s+([,.;:!?])'),
          (match) => match.group(1) ?? '',
        )
        .trim();
  }

  static bool _isFenceLine(String line) => RegExp(r'^(```|~~~)').hasMatch(line);

  static bool _isHorizontalRule(String line) =>
      RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$').hasMatch(line);

  static bool _isTableSeparator(String line) =>
      RegExp(r'^\|?[\s:\-\|]+\|?$').hasMatch(line) &&
      line.contains('-') &&
      line.contains('|');

  static String _decodeCommonEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  static bool _endsWithSentencePunctuation(String text) =>
      text.endsWith('.') ||
      text.endsWith('!') ||
      text.endsWith('?') ||
      text.endsWith(':');

  static String _stripInlineMarkdown(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'!\[(.*?)\]\((.*?)\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\[(.*?)\]\((.*?)\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'`{1,3}([\s\S]+?)`{1,3}', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\*\*\*(.+?)\*\*\*', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\*\*(.+?)\*\*', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'__(.+?)__', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\*(.+?)\*', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'_(.+?)_', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'~~(.+?)~~', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\\\(([\s\S]+?)\\\)', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\\\[([\s\S]+?)\\\]', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\$\$([\s\S]+?)\$\$', dotAll: true),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\\([\\`*_{}\[\]()#+\-.!|>~$])'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\$'), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '')
        .replaceAll(RegExp(r'www\.\S+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[*_~]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static String _stripEmoji(String text) {
    return text
        // Remove common emoji ranges and presentation modifiers.
        .replaceAll(
          RegExp(
            r'[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'[\u{FE0F}\u{200D}]', unicode: true), '')
        .replaceAll(RegExp(r'[#*0-9]\u{FE0F}\u{20E3}', unicode: true), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}
