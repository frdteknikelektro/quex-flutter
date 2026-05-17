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
  String get appSubtitle => 'Quick Exam';

  @override
  String get appTagline => 'Latihan hingga Sempurna';

  @override
  String poweredByDownloadedModel(String model) {
    return 'Powered by $model';
  }

  @override
  String get warmingUp => 'Memanaskan...';

  @override
  String downloadingBrain(int percent) {
    return 'Mengunduh otak… $percent% 🧠';
  }

  @override
  String downloadingModelVariant(String variant, String size) {
    return 'Gemma 4 $variant ($size)';
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
  String get clearAllSessionsConfirm =>
      'Ini akan menghapus permanen semua sesi belajar, materi, kuis, dan riwayat chat untuk profil ini.';

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
  String get deleteAIModel => 'Hapus Model AI';

  @override
  String get deleteAIModelSubtitle => 'Hapus otak AI dan data';

  @override
  String get deleteAIModelQuestion => 'Hapus Model AI?';

  @override
  String get deleteAIModelConfirm =>
      'Ini akan menghapus otak model AI yang telah diunduh. Anda harus mengunduhnya kembali untuk menggunakan Quex lagi.';

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

  @override
  String homeFailedToLoadSessions(String error) {
    return 'Gagal memuat sesi: $error';
  }

  @override
  String get homeRecentSessions => 'Sesi Terbaru';

  @override
  String homeFailedToLoadProfiles(String error) {
    return 'Gagal memuat profil: $error';
  }

  @override
  String get homeGoodMorning => 'Selamat pagi';

  @override
  String get homeGoodAfternoon => 'Selamat siang';

  @override
  String get homeGoodEvening => 'Selamat malam';

  @override
  String get homeSeeLess => 'Lihat lebih sedikit';

  @override
  String get homeSeeMore => 'Lihat lebih banyak';

  @override
  String get homeToday => 'Hari ini';

  @override
  String get homeYesterday => 'Kemarin';

  @override
  String get homeLetsStartLearning => 'Mari mulai belajar!';

  @override
  String get homeCreateFirstSession =>
      'Buat sesi belajar pertama Anda dan meluncur ke dunia yang menyenangkan!';

  @override
  String get homeStartMyAdventure => 'Mulai petualangan saya!';

  @override
  String get homeNoProfilesYet => 'Belum ada profil';

  @override
  String get homeSwitchToProfile =>
      'Beralih ke profil untuk memulai alur belajar baru.';

  @override
  String get newSessionAddTitleFirst => 'Tambahkan judul sesi terlebih dahulu.';

  @override
  String get newSessionTitle => 'Judul sesi';

  @override
  String get newSessionTitleHint => 'contoh. Latihan pecahan';

  @override
  String get newSessionPickEmoji => 'Pilih emoji';

  @override
  String newSessionGrade(int grade) {
    return 'Kelas $grade';
  }

  @override
  String get newSessionCreating => 'Membuat...';

  @override
  String sessionDetailFailedToLoad(String error) {
    return 'Gagal memuat sesi: $error';
  }

  @override
  String get sessionDetailNotFound => 'Sesi tidak ditemukan';

  @override
  String get sessionDetailGenerateQuiz => 'Buat kuis';

  @override
  String sessionDetailGradeAndDate(int grade, String date) {
    return 'Kelas $grade  •  $date';
  }

  @override
  String get sessionDetailAddNotes => 'Tambahkan catatan dan referensi';

  @override
  String get sessionDetailOneMaterial => '1 materi belajar';

  @override
  String sessionDetailMaterialsCount(int count) {
    return '$count materi belajar';
  }

  @override
  String get sessionDetailStudyMaterials => 'Materi Belajar';

  @override
  String get sessionDetailChatWithAI => 'Chat dengan AI';

  @override
  String get sessionDetailChatSubtitle => 'Tanyakan tentang catatan Anda';

  @override
  String get sessionDetailWhichMaterials => 'Materi mana yang ingin dibahas?';

  @override
  String get sessionDetailQuexWillUse =>
      'Quex hanya akan menggunakan materi ini dalam percakapan.';

  @override
  String get sessionDetailMaterialKindText => 'Teks';

  @override
  String get sessionDetailMaterialKindDocument => 'Dokumen';

  @override
  String get sessionDetailMaterialKindPhoto => 'Foto';

  @override
  String get sessionDetailSelectAtLeastOne => 'Pilih setidaknya satu materi';

  @override
  String sessionDetailStartChat(int count) {
    return 'Mulai chat ($count)';
  }

  @override
  String get sessionDetailRecentQuizzes => 'Kuis Terbaru';

  @override
  String sessionDetailScore(int score) {
    return 'Skor $score%';
  }

  @override
  String get sessionDetailInProgress => 'Sedang berlangsung';

  @override
  String sessionDetailQuestionsCount(int count) {
    return '$count pertanyaan';
  }

  @override
  String get sessionDetailAddMaterialsFirst =>
      'Tambahkan materi belajar terlebih dahulu, lalu buat kuis.';

  @override
  String get sessionDetailReadyToMakeQuiz => 'Siap membuat kuis?';

  @override
  String get sessionDetailEditSession => 'Edit Sesi';

  @override
  String get materialDeleteQuestion => 'Hapus materi?';

  @override
  String get materialDeleteConfirm => 'Catatan ini akan dihapus permanen.';

  @override
  String materialFailedToLoadSession(String error) {
    return 'Gagal memuat sesi: $error';
  }

  @override
  String get materialSessionNotFound => 'Sesi tidak ditemukan';

  @override
  String materialCouldNotLoadFiles(String error) {
    return 'Gagal memuat file: $error';
  }

  @override
  String get materialAddMaterial => 'Tambah materi';

  @override
  String materialCouldNotOpen(String message) {
    return 'Tidak dapat membuka: $message';
  }

  @override
  String get materialFolderEmpty => 'Folder belajar Anda kosong';

  @override
  String get materialFolderEmptySubtitle =>
      'Ketuk \"Tambah materi\" untuk memasukkan catatan, dokumen, atau foto.';

  @override
  String get materialAddToFolder => 'Tambah ke Folder Belajar';

  @override
  String get materialCamera => 'Kamera';

  @override
  String get materialGallery => 'Galeri';

  @override
  String get materialTitle => 'Judul';

  @override
  String get materialPickPdf => 'Pilih PDF';

  @override
  String get materialAddMore => 'Tambah lagi';

  @override
  String get materialNotesContent => 'Catatan / konten';

  @override
  String get materialNotesHint => 'Tempel catatan atau ketik konten di sini.';

  @override
  String get materialSaveFile => 'Simpan file';

  @override
  String get materialKindPhoto => 'Foto';

  @override
  String get materialKindPdf => 'PDF';

  @override
  String get materialKindText => 'Teks';

  @override
  String get materialAddAtLeastOnePhoto => 'Tambahkan setidaknya satu foto.';

  @override
  String get materialAddTitle => 'Tambahkan judul.';

  @override
  String get materialPickAtLeastOnePdf => 'Pilih setidaknya satu PDF.';

  @override
  String get materialAddTitleAndContent => 'Tambahkan judul dan konten.';

  @override
  String materialPhotosCount(int count) {
    return '$count foto';
  }

  @override
  String materialTextSubtitle(String date) {
    return 'Teks  ·  $date';
  }

  @override
  String materialDetailCouldNotLoad(String error) {
    return 'Gagal memuat materi: $error';
  }

  @override
  String get materialDetailNotFound => 'Materi tidak ditemukan';

  @override
  String get materialDetailEditing => 'Mengedit';

  @override
  String get materialDetailStartWriting => 'Mulai menulis…';

  @override
  String get materialDetailNoContent =>
      '_Belum ada konten. Ketuk ✏️ untuk menambahkan catatan._';

  @override
  String get materialDetailNoImages => 'Tidak ada gambar ditemukan';

  @override
  String get materialDetailOpening => 'Membuka…';

  @override
  String get materialDetailOpenExternal => 'Buka di aplikasi eksternal';

  @override
  String get materialDetailFileMissing =>
      'File hilang dari disk. Mungkin telah dihapus.';

  @override
  String materialDetailCouldNotOpenFile(String message) {
    return 'Tidak dapat membuka file: $message';
  }

  @override
  String get materialDetailAdded => 'Ditambahkan';

  @override
  String get materialDetailLocation => 'Lokasi';

  @override
  String materialDetailWords(int count) {
    return '$count kata';
  }

  @override
  String get materialActionsRename => 'Ganti Nama';

  @override
  String pdfPickerCouldNotOpen(String error) {
    return 'Tidak dapat membuka PDF: $error';
  }

  @override
  String pdfPickerFailedToSave(String error) {
    return 'Gagal menyimpan halaman: $error';
  }

  @override
  String get pdfPickerLoading => 'Memuat halaman...';

  @override
  String pdfPickerPagesCount(int count) {
    return '$count halaman — ketuk untuk memilih';
  }

  @override
  String get pdfPickerSelectPages => 'Pilih halaman untuk melanjutkan';

  @override
  String pdfPickerAddPages(int count) {
    return 'Tambah $count halaman';
  }

  @override
  String pdfPickerPage(int number) {
    return 'Halaman $number';
  }

  @override
  String chatCouldNotLoadModel(String error) {
    return 'Tidak dapat memuat model: $error';
  }

  @override
  String get chatFailedToStartSession =>
      'Gagal memulai sesi chat. Silakan coba lagi.';

  @override
  String get chatSessionInterrupted => 'Sesi terganggu. Silakan coba lagi.';

  @override
  String chatError(String error) {
    return 'Error: $error';
  }

  @override
  String get chatSessionNotFound => 'Sesi tidak ditemukan';

  @override
  String get chatResetQuestion => 'Reset chat?';

  @override
  String get chatResetConfirm => 'Semua pesan akan dihapus.';

  @override
  String get chatReset => 'Reset';

  @override
  String get chatThinking => 'Berpikir…';

  @override
  String get chatThoughtProcess => 'Proses berpikir';

  @override
  String get chatAskQuex => 'Tanya apa saja ke Quex';

  @override
  String get chatAskQuexSubtitle =>
      'Tanyakan tentang catatan Anda, dapatkan ringkasan, atau minta petunjuk kuis.';

  @override
  String get chatQuickSummarize => 'Ringkas';

  @override
  String get chatQuickQuizHints => 'Petunjuk kuis';

  @override
  String get chatQuickExplainSimply => 'Jelaskan dengan sederhana';

  @override
  String chatAskAbout(String topic) {
    return 'Tanya tentang \"$topic\"';
  }

  @override
  String get chatSession => 'Sesi';

  @override
  String get chatSuggestedTopics => 'Topik yang disarankan';

  @override
  String get chatAskQuexHint => 'Tanya Quex…';

  @override
  String get chatVoiceMessage => 'Pesan suara';

  @override
  String get chatMicHold => 'Tahan untuk berbicara';

  @override
  String get chatMicPermissionDenied =>
      'Izin mikrofon ditolak. Aktifkan di Pengaturan.';

  @override
  String get chatMicError => 'Rekaman gagal. Silakan coba lagi.';

  @override
  String get chatListening => 'Mendengarkan...';

  @override
  String get chatWaitingForResponse => 'Menunggu respons...';

  @override
  String get chatThinkingMode => 'Mode berpikir';

  @override
  String get chatThinkingModeDescription => 'Tampilkan proses berpikir AI';

  @override
  String get chatThinkingModeConfirm => 'Aktifkan mode berpikir?';

  @override
  String get chatThinkingModeConfirmMessage =>
      'Ini akan menghapus percakapan saat ini dan memulai ulang chat dengan mode berpikir aktif. Lanjutkan?';

  @override
  String get chatThinkingModeDisableConfirm => 'Nonaktifkan mode berpikir?';

  @override
  String get chatThinkingModeDisableMessage =>
      'Ini akan menghapus percakapan saat ini dan memulai ulang chat dengan mode berpikir nonaktif. Lanjutkan?';

  @override
  String get chatTokens => 'token';

  @override
  String get chatThinkingLabel => 'Berpikir';

  @override
  String get quizDetailTitle => 'Pertanyaan Kuis';

  @override
  String quizDetailError(String error) {
    return 'Error: $error';
  }

  @override
  String get quizDetailNotFound => 'Kuis tidak ditemukan';

  @override
  String get quizDetailDeleted => 'Kuis ini mungkin telah dihapus.';

  @override
  String get quizDetailFinish => 'Selesaikan Kuis';

  @override
  String get quizDetailToday => 'Hari ini';

  @override
  String get quizDetailYesterday => 'Kemarin';

  @override
  String quizDetailQuestionsCount(int count) {
    return '$count Pertanyaan';
  }

  @override
  String quizDetailAnswered(int count) {
    return '$count dijawab';
  }

  @override
  String questionChatFailedToPreload(String error) {
    return 'Gagal memuat sesi chat: $error';
  }

  @override
  String get questionChatNotFound => 'Pertanyaan tidak ditemukan';

  @override
  String questionChatTitle(int number) {
    return 'Pertanyaan $number';
  }

  @override
  String get questionChatScoreCorrect => 'Benar! 🎉';

  @override
  String get questionChatScorePartial => 'Nilai sebagian — teruslah!';

  @override
  String get questionChatScoreIncorrect => 'Belum tepat — mari kita diskusikan';

  @override
  String get questionChatQuestionLabel => 'Pertanyaan';

  @override
  String get questionChatTapAnswer => 'Ketuk jawaban';

  @override
  String get questionChatChooseAnswer => 'Pilih jawaban';

  @override
  String get questionChatTalkToQuex => 'Bicara dengan Quex…';

  @override
  String summaryFailedToLoad(String error) {
    return 'Gagal memuat ringkasan: $error';
  }

  @override
  String get summaryQuizNotFound => 'Kuis tidak ditemukan';

  @override
  String summaryFailedToLoadSession(String error) {
    return 'Gagal memuat sesi: $error';
  }

  @override
  String get summaryTitle => 'Ringkasan';

  @override
  String get summaryChat => 'Chat';

  @override
  String get summarySession => 'Sesi';

  @override
  String get summaryResults => 'Hasil';

  @override
  String get summaryResultsSubtitle =>
      'Tinjau kuis dan teruskan loop pembelajaran.';

  @override
  String get summaryQuizCompleted => 'Kuis selesai';

  @override
  String get summaryQuizInProgress => 'Kuis masih berlangsung';

  @override
  String summaryOf(int total) {
    return 'dari $total';
  }

  @override
  String get summaryCorrect => 'Benar';

  @override
  String get summaryTotal => 'Total';

  @override
  String get summaryNextSteps => 'Langkah selanjutnya';

  @override
  String get summaryNextStepsSubtitle => 'Teruskan sesi ke depan.';

  @override
  String get summaryDiscuss => 'Diskusi';

  @override
  String get summaryRetryQuiz => 'Ulangi kuis';

  @override
  String get summarySessionDetails => 'Detail sesi';

  @override
  String get summaryReview => 'Tinjau';

  @override
  String get summaryReviewSubtitle =>
      'Fokus pada pertanyaan yang perlu ditinjau ulang.';

  @override
  String get summaryNoMissed => 'Tidak ada pertanyaan terlewat. Bagus sekali.';

  @override
  String summaryYourAnswer(String answer) {
    return 'Jawaban Anda: $answer';
  }

  @override
  String get summaryChatToLearn =>
      'Chat dengan Quex untuk belajar lebih lanjut.';

  @override
  String get quizGenAddMaterialsFirst =>
      'Tambahkan materi belajar terlebih dahulu.';

  @override
  String quizGenFailed(String message) {
    return 'Gagal membuat kuis: $message';
  }

  @override
  String get quizGenPickMaterials => 'Pilih materi Anda';

  @override
  String get quizGenLoadingBrain => 'Memuat otak...';

  @override
  String get quizGenReady => 'Kuis siap! 🎉';

  @override
  String get quizGenExtracting => 'Mengekstrak pertanyaan yang ada...';

  @override
  String get quizGenGenerating => 'Membuat kuis...';

  @override
  String get quizGenThinking => 'Quex sedang berpikir...';

  @override
  String get quizGenFoundQuestions => 'Pertanyaan yang ditemukan';

  @override
  String get quizGenNoQuestions => 'Tidak ada pertanyaan yang ditemukan';

  @override
  String get quizGenGettingReady => 'Bersiap...';

  @override
  String get quizGenWhichMaterials => 'Materi mana yang akan dikuis?';

  @override
  String get quizGenScanMaterials =>
      'Quex akan memindai ini untuk pertanyaan yang ada.';

  @override
  String get quizGenLoadingModel => 'Memuat model…';

  @override
  String get quizGenSelectFirst => 'Pilih materi terlebih dahulu';

  @override
  String quizGenGenerate(int count) {
    return 'Buat kuis ($count)';
  }

  @override
  String get quizGenFoundTitle => 'Pertanyaan yang ditemukan';

  @override
  String get quizGenNoQuestionsTitle => 'Tidak ada pertanyaan';

  @override
  String get quizGenFoundDescription =>
      'Pertanyaan ini ditemukan dalam materi Anda. Quex akan menggunakan ini untuk membuat kuis Anda.';

  @override
  String get quizGenNoQuestionsDescription =>
      'Tidak ada pertanyaan kuis yang ditemukan dalam materi Anda. Quex akan membuat pertanyaan dari awal.';

  @override
  String get quizGenContinue => 'Lanjutkan untuk membuat kuis';

  @override
  String get quizDebugTitle => 'Kuis yang Dibuat';

  @override
  String get quizDebugQuestionsGenerated => 'Pertanyaan yang Dibuat';

  @override
  String quizDebugReadyToReview(int count, String s) {
    return '$count pertanyaan$s siap ditinjau.';
  }

  @override
  String get quizDebugMultipleChoice => 'Pilihan Ganda';

  @override
  String get quizDebugTextAnswer => 'Jawaban Teks';

  @override
  String get quizDebugViewQuiz => 'Lihat Kuis';

  @override
  String get chatTtsSayThinking => 'Tunggu ya, aku berpikir dulu…';
}
