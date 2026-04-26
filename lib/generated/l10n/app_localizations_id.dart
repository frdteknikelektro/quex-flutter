// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'Quex';

  @override
  String get appSubtitle => 'Ujian Cepat';

  @override
  String get appTagline => 'Latihan membuat Sempurna';

  @override
  String get ready => 'Siap! 🎉';

  @override
  String downloadingBrain(int percent) {
    return 'Mengunduh otak… $percent% 🧠';
  }

  @override
  String get oopsSomethingWentWrong => 'Ups, terjadi kesalahan';

  @override
  String get tryAgain => 'Coba lagi';

  @override
  String get cancelling => 'Membatalkan…';

  @override
  String downloadingModel(String percent) {
    return 'Mengunduh model $percent%';
  }

  @override
  String get cancelDownload => 'Batalkan unduhan';

  @override
  String get home => 'Beranda';

  @override
  String get profile => 'Profil';

  @override
  String get settings => 'Pengaturan';

  @override
  String get cancel => 'Batal';

  @override
  String get clear => 'Hapus';

  @override
  String get save => 'Simpan';

  @override
  String get delete => 'Hapus';

  @override
  String get edit => 'Edit';

  @override
  String get switchButton => 'Ganti';

  @override
  String get continueButton => 'Lanjut';

  @override
  String get loading => 'Memuat...';

  @override
  String get error => 'Error';

  @override
  String get retry => 'Coba Lagi';

  @override
  String get grade => 'Kelas';

  @override
  String get session => 'Sesi';

  @override
  String get material => 'Materi';

  @override
  String get quiz => 'Kuis';

  @override
  String get language => 'Bahasa';

  @override
  String get languageAuto => 'Otomatis';

  @override
  String get languageEnglish => 'Inggris';

  @override
  String get languageIndonesian => 'Indonesia';

  @override
  String get pageNotFound => 'Halaman tidak ditemukan';

  @override
  String get goHome => 'Ke beranda';

  @override
  String get newSession => 'Sesi baru';

  @override
  String get whoStudying => 'Siapa yang belajar?';

  @override
  String get pickProfile => 'Pilih profil Anda untuk mulai belajar! 🚀';

  @override
  String get addNewProfile => 'Tambah Profil Baru';

  @override
  String get editProfile => 'Edit Profil';

  @override
  String get name => 'Nama';

  @override
  String get whatCallYou => 'Bagaimana kami memanggil Anda?';

  @override
  String get pickCharacter => 'Pilih karakter';

  @override
  String get gradeLevel => 'Tingkat Kelas';

  @override
  String get totalSessions => 'Total sesi';

  @override
  String get clearAllSessions => 'Hapus semua sesi';

  @override
  String get removeStudyData => 'Hapus semua data belajar';

  @override
  String get clearAllSessionsQuestion => 'Hapus semua sesi?';

  @override
  String get clearAllSessionsConfirm => 'Ini akan menghapus permanen semua sesi belajar, materi, kuis, dan riwayat chat untuk profil ini.';

  @override
  String get allSessionsCleared => 'Semua sesi dihapus';

  @override
  String get deleteProfile => 'Hapus profil';

  @override
  String removeProfileData(String name) {
    return 'Hapus \"$name\" dan semua data';
  }

  @override
  String get deleteProfileQuestion => 'Hapus profil?';

  @override
  String deleteProfileConfirm(String name) {
    return 'Ini akan menghapus permanen \"$name\" dan SEMUA data terkait.';
  }

  @override
  String get typeProfileName => 'Ketik nama profil untuk mengkonfirmasi:';

  @override
  String get switchProfile => 'Ganti Profil';

  @override
  String get noProfileFound => 'Profil tidak ditemukan';

  @override
  String get createFirstProfile => 'Buat profil pertama Anda';

  @override
  String get letsGetStarted => 'Mari mulai! 🚀';

  @override
  String get defaultQuestionsPerQuiz => 'Pertanyaan default per kuis';

  @override
  String get createAndStartStudying => 'Buat & Mulai Belajar';
}
