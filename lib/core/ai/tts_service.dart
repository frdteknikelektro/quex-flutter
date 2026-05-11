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
    final plain = _stripMarkdown(text);
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

  static String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*', dotAll: true), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*', dotAll: true), r'$1')
        .replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}', dotAll: true), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1')
        .replaceAll(RegExp(r'!?\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'\n{2,}'), '. ')
        .replaceAll('\n', ' ')
        .trim();
  }
}
