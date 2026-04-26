import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id')
  ];

  /// App name displayed on splash screen
  ///
  /// In en, this message translates to:
  /// **'Quex'**
  String get appTitle;

  /// App subtitle on splash screen
  ///
  /// In en, this message translates to:
  /// **'Quick Exam'**
  String get appSubtitle;

  /// Slogan on splash screen
  ///
  /// In en, this message translates to:
  /// **'Practice makes Perfect'**
  String get appTagline;

  /// Success message when model download is complete
  ///
  /// In en, this message translates to:
  /// **'Ready! 🎉'**
  String get ready;

  /// Download progress message with percentage
  ///
  /// In en, this message translates to:
  /// **'Downloading brain… {percent}% 🧠'**
  String downloadingBrain(int percent);

  /// Error message on splash screen
  ///
  /// In en, this message translates to:
  /// **'Oops, something went wrong'**
  String get oopsSomethingWentWrong;

  /// Button to retry after error
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Cancelling action text in app shell
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get cancelling;

  /// Model download progress in app shell
  ///
  /// In en, this message translates to:
  /// **'Downloading model {percent}%'**
  String downloadingModel(String percent);

  /// Button to cancel download in app shell
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// Navigation label for home screen
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// Navigation label for profile screen
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Navigation label for settings screen
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Button to cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button to clear/delete items
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Button to save changes
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Button to delete an item
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Button to edit an item
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Button to switch to something
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get switchButton;

  /// Button to continue to next step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// Loading indicator text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Error title
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Button to retry a failed action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Grade level label
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get grade;

  /// Study session label
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// Study material label
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get material;

  /// Quiz label
  ///
  /// In en, this message translates to:
  /// **'Quiz'**
  String get quiz;

  /// Language setting label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Auto-detect language option
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get languageAuto;

  /// English language option
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Indonesian language option
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get languageIndonesian;

  /// Error message when route is not found
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get pageNotFound;

  /// Button to navigate to home screen
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get goHome;

  /// Button to create new session
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSession;

  /// Title for profile selection screen
  ///
  /// In en, this message translates to:
  /// **'Who\'s studying?'**
  String get whoStudying;

  /// Subtitle for profile selection screen
  ///
  /// In en, this message translates to:
  /// **'Pick your profile to start learning! 🚀'**
  String get pickProfile;

  /// Button to add new profile
  ///
  /// In en, this message translates to:
  /// **'Add New Profile'**
  String get addNewProfile;

  /// Title for editing profile
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// Name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// Placeholder for name field
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get whatCallYou;

  /// Label for character/emoji selection
  ///
  /// In en, this message translates to:
  /// **'Pick a character'**
  String get pickCharacter;

  /// Label for grade level selection
  ///
  /// In en, this message translates to:
  /// **'Grade Level'**
  String get gradeLevel;

  /// Label showing total session count
  ///
  /// In en, this message translates to:
  /// **'Total sessions'**
  String get totalSessions;

  /// Button to clear all sessions
  ///
  /// In en, this message translates to:
  /// **'Clear all sessions'**
  String get clearAllSessions;

  /// Subtitle for clear sessions action
  ///
  /// In en, this message translates to:
  /// **'Remove all study data'**
  String get removeStudyData;

  /// Confirmation dialog title for clearing sessions
  ///
  /// In en, this message translates to:
  /// **'Clear all sessions?'**
  String get clearAllSessionsQuestion;

  /// Confirmation message for clearing sessions
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all study sessions, materials, quizzes, and chat history for this profile.'**
  String get clearAllSessionsConfirm;

  /// Success message after clearing sessions
  ///
  /// In en, this message translates to:
  /// **'All sessions cleared'**
  String get allSessionsCleared;

  /// Button to delete profile
  ///
  /// In en, this message translates to:
  /// **'Delete profile'**
  String get deleteProfile;

  /// Subtitle for delete profile action
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" and all data'**
  String removeProfileData(String name);

  /// Confirmation dialog title for deleting profile
  ///
  /// In en, this message translates to:
  /// **'Delete profile?'**
  String get deleteProfileQuestion;

  /// Confirmation message for deleting profile
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\" and ALL associated data.'**
  String deleteProfileConfirm(String name);

  /// Instruction for profile deletion confirmation
  ///
  /// In en, this message translates to:
  /// **'Type the profile name to confirm:'**
  String get typeProfileName;

  /// Button to switch to another profile
  ///
  /// In en, this message translates to:
  /// **'Switch Profile'**
  String get switchProfile;

  /// Error message when no profile exists
  ///
  /// In en, this message translates to:
  /// **'No profile found'**
  String get noProfileFound;

  /// Title for creating first profile
  ///
  /// In en, this message translates to:
  /// **'Create your first profile'**
  String get createFirstProfile;

  /// Subtitle for first profile creation
  ///
  /// In en, this message translates to:
  /// **'Let\'s get started! 🚀'**
  String get letsGetStarted;

  /// Label for default question count setting
  ///
  /// In en, this message translates to:
  /// **'Default questions per quiz'**
  String get defaultQuestionsPerQuiz;

  /// Button to create profile and start
  ///
  /// In en, this message translates to:
  /// **'Create & Start Studying'**
  String get createAndStartStudying;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'id': return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
