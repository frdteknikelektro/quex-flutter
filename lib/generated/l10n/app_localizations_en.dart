// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Quex';

  @override
  String get appSubtitle => 'Quick Exam';

  @override
  String get appTagline => 'Practice makes Perfect';

  @override
  String get ready => 'Ready! 🎉';

  @override
  String downloadingBrain(int percent) {
    return 'Downloading brain… $percent% 🧠';
  }

  @override
  String get oopsSomethingWentWrong => 'Oops, something went wrong';

  @override
  String get tryAgain => 'Try again';

  @override
  String get cancelling => 'Cancelling…';

  @override
  String downloadingModel(String percent) {
    return 'Downloading model $percent%';
  }

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get home => 'Home';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get switchButton => 'Switch';

  @override
  String get continueButton => 'Continue';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Error';

  @override
  String get retry => 'Retry';

  @override
  String get grade => 'Grade';

  @override
  String get session => 'Session';

  @override
  String get material => 'Material';

  @override
  String get quiz => 'Quiz';

  @override
  String get language => 'Language';

  @override
  String get languageAuto => 'Auto';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageIndonesian => 'Indonesian';

  @override
  String get pageNotFound => 'Page not found';

  @override
  String get goHome => 'Go home';

  @override
  String get newSession => 'New session';

  @override
  String get whoStudying => 'Who\'s studying?';

  @override
  String get pickProfile => 'Pick your profile to start learning! 🚀';

  @override
  String get addNewProfile => 'Add New Profile';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get name => 'Name';

  @override
  String get whatCallYou => 'What should we call you?';

  @override
  String get pickCharacter => 'Pick a character';

  @override
  String get gradeLevel => 'Grade Level';

  @override
  String get totalSessions => 'Total sessions';

  @override
  String get clearAllSessions => 'Clear all sessions';

  @override
  String get removeStudyData => 'Remove all study data';

  @override
  String get clearAllSessionsQuestion => 'Clear all sessions?';

  @override
  String get clearAllSessionsConfirm => 'This will permanently delete all study sessions, materials, quizzes, and chat history for this profile.';

  @override
  String get allSessionsCleared => 'All sessions cleared';

  @override
  String get deleteProfile => 'Delete profile';

  @override
  String removeProfileData(String name) {
    return 'Remove \"$name\" and all data';
  }

  @override
  String get deleteProfileQuestion => 'Delete profile?';

  @override
  String deleteProfileConfirm(String name) {
    return 'This will permanently delete \"$name\" and ALL associated data.';
  }

  @override
  String get typeProfileName => 'Type the profile name to confirm:';

  @override
  String get switchProfile => 'Switch Profile';

  @override
  String get noProfileFound => 'No profile found';

  @override
  String get createFirstProfile => 'Create your first profile';

  @override
  String get letsGetStarted => 'Let\'s get started! 🚀';

  @override
  String get defaultQuestionsPerQuiz => 'Default questions per quiz';

  @override
  String get createAndStartStudying => 'Create & Start Studying';
}
