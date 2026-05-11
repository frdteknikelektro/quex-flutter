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
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
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

  /// Message shown while model is being warmed up after download
  ///
  /// In en, this message translates to:
  /// **'Warming up...'**
  String get warmingUp;

  /// Download progress message with percentage
  ///
  /// In en, this message translates to:
  /// **'Downloading brain… {percent}% 🧠'**
  String downloadingBrain(int percent);

  /// Model variant info shown below download progress
  ///
  /// In en, this message translates to:
  /// **'Gemma 4 {variant} ({size})'**
  String downloadingModelVariant(String variant, String size);

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

  /// Error message when sessions fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load sessions: {error}'**
  String homeFailedToLoadSessions(String error);

  /// Label for recent sessions list
  ///
  /// In en, this message translates to:
  /// **'Recent Sessions'**
  String get homeRecentSessions;

  /// Error message when profiles fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load profiles: {error}'**
  String homeFailedToLoadProfiles(String error);

  /// Morning greeting
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGoodMorning;

  /// Afternoon greeting
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGoodAfternoon;

  /// Evening greeting
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGoodEvening;

  /// Button to show fewer sessions
  ///
  /// In en, this message translates to:
  /// **'See less'**
  String get homeSeeLess;

  /// Button to show more sessions
  ///
  /// In en, this message translates to:
  /// **'See more'**
  String get homeSeeMore;

  /// Label for today's date
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get homeToday;

  /// Label for yesterday's date
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get homeYesterday;

  /// Empty state title for no sessions
  ///
  /// In en, this message translates to:
  /// **'Let\'s start learning!'**
  String get homeLetsStartLearning;

  /// Empty state subtitle for no sessions
  ///
  /// In en, this message translates to:
  /// **'Create your very first study session and blast off into a world of fun!'**
  String get homeCreateFirstSession;

  /// Button to create first session
  ///
  /// In en, this message translates to:
  /// **'Start my adventure!'**
  String get homeStartMyAdventure;

  /// Empty state title when no profiles exist
  ///
  /// In en, this message translates to:
  /// **'No profiles yet'**
  String get homeNoProfilesYet;

  /// Empty state subtitle when no profiles exist
  ///
  /// In en, this message translates to:
  /// **'Switch to a profile to start a new study flow.'**
  String get homeSwitchToProfile;

  /// Validation error when session title is empty
  ///
  /// In en, this message translates to:
  /// **'Add a session title first.'**
  String get newSessionAddTitleFirst;

  /// Label for session title field
  ///
  /// In en, this message translates to:
  /// **'Session title'**
  String get newSessionTitle;

  /// Hint text for session title field
  ///
  /// In en, this message translates to:
  /// **'e.g. Fractions practice'**
  String get newSessionTitleHint;

  /// Label for emoji picker
  ///
  /// In en, this message translates to:
  /// **'Pick an emoji'**
  String get newSessionPickEmoji;

  /// Display grade number
  ///
  /// In en, this message translates to:
  /// **'Grade {grade}'**
  String newSessionGrade(int grade);

  /// Button text while creating session
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get newSessionCreating;

  /// Error message when session fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load session: {error}'**
  String sessionDetailFailedToLoad(String error);

  /// Error message when session doesn't exist
  ///
  /// In en, this message translates to:
  /// **'Session not found'**
  String get sessionDetailNotFound;

  /// Button to generate quiz
  ///
  /// In en, this message translates to:
  /// **'Generate quiz'**
  String get sessionDetailGenerateQuiz;

  /// Session grade and creation date
  ///
  /// In en, this message translates to:
  /// **'Grade {grade}  •  {date}'**
  String sessionDetailGradeAndDate(int grade, String date);

  /// Subtitle when no materials exist
  ///
  /// In en, this message translates to:
  /// **'Add notes and references'**
  String get sessionDetailAddNotes;

  /// Subtitle when there is 1 material
  ///
  /// In en, this message translates to:
  /// **'1 study material'**
  String get sessionDetailOneMaterial;

  /// Subtitle with material count
  ///
  /// In en, this message translates to:
  /// **'{count} study materials'**
  String sessionDetailMaterialsCount(int count);

  /// Label for study materials section
  ///
  /// In en, this message translates to:
  /// **'Study Materials'**
  String get sessionDetailStudyMaterials;

  /// Label for chat with AI section
  ///
  /// In en, this message translates to:
  /// **'Chat with AI'**
  String get sessionDetailChatWithAI;

  /// Subtitle for chat with AI
  ///
  /// In en, this message translates to:
  /// **'Ask questions about your notes'**
  String get sessionDetailChatSubtitle;

  /// Title for material picker sheet
  ///
  /// In en, this message translates to:
  /// **'Which materials to chat about?'**
  String get sessionDetailWhichMaterials;

  /// Subtitle for material picker sheet
  ///
  /// In en, this message translates to:
  /// **'Quex will use only these in the conversation.'**
  String get sessionDetailQuexWillUse;

  /// Material kind label for text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get sessionDetailMaterialKindText;

  /// Material kind label for document
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get sessionDetailMaterialKindDocument;

  /// Material kind label for photo
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get sessionDetailMaterialKindPhoto;

  /// Button text when no materials selected
  ///
  /// In en, this message translates to:
  /// **'Select at least one material'**
  String get sessionDetailSelectAtLeastOne;

  /// Button to start chat with selected materials
  ///
  /// In en, this message translates to:
  /// **'Start chat ({count})'**
  String sessionDetailStartChat(int count);

  /// Label for recent quizzes section
  ///
  /// In en, this message translates to:
  /// **'Recent Quizzes'**
  String get sessionDetailRecentQuizzes;

  /// Quiz score display
  ///
  /// In en, this message translates to:
  /// **'Score {score}%'**
  String sessionDetailScore(int score);

  /// Quiz status when not completed
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get sessionDetailInProgress;

  /// Number of questions in quiz
  ///
  /// In en, this message translates to:
  /// **'{count} questions'**
  String sessionDetailQuestionsCount(int count);

  /// Message when no materials exist for quiz
  ///
  /// In en, this message translates to:
  /// **'Add study materials first, then generate a quiz.'**
  String get sessionDetailAddMaterialsFirst;

  /// Empty state title for quiz section
  ///
  /// In en, this message translates to:
  /// **'Ready to make a quiz?'**
  String get sessionDetailReadyToMakeQuiz;

  /// Title for edit session bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Edit Session'**
  String get sessionDetailEditSession;

  /// Confirmation dialog title for deleting material
  ///
  /// In en, this message translates to:
  /// **'Delete material?'**
  String get materialDeleteQuestion;

  /// Confirmation message for deleting material
  ///
  /// In en, this message translates to:
  /// **'This note will be permanently removed.'**
  String get materialDeleteConfirm;

  /// Error message when session fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load session: {error}'**
  String materialFailedToLoadSession(String error);

  /// Error message when session doesn't exist
  ///
  /// In en, this message translates to:
  /// **'Session not found'**
  String get materialSessionNotFound;

  /// Error message when materials fail to load
  ///
  /// In en, this message translates to:
  /// **'Could not load files: {error}'**
  String materialCouldNotLoadFiles(String error);

  /// Button to add material
  ///
  /// In en, this message translates to:
  /// **'Add material'**
  String get materialAddMaterial;

  /// Error message when file fails to open
  ///
  /// In en, this message translates to:
  /// **'Could not open: {message}'**
  String materialCouldNotOpen(String message);

  /// Empty state title for no materials
  ///
  /// In en, this message translates to:
  /// **'Your study folder is empty'**
  String get materialFolderEmpty;

  /// Empty state subtitle for no materials
  ///
  /// In en, this message translates to:
  /// **'Tap \"Add material\" to drop in notes, documents, or photos.'**
  String get materialFolderEmptySubtitle;

  /// Title for add material bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Add to Study Folder'**
  String get materialAddToFolder;

  /// Button to pick from camera
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get materialCamera;

  /// Button to pick from gallery
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get materialGallery;

  /// Label for title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get materialTitle;

  /// Button to pick PDF file
  ///
  /// In en, this message translates to:
  /// **'Pick PDF'**
  String get materialPickPdf;

  /// Button to add more files
  ///
  /// In en, this message translates to:
  /// **'Add more'**
  String get materialAddMore;

  /// Label for notes/content field
  ///
  /// In en, this message translates to:
  /// **'Notes / content'**
  String get materialNotesContent;

  /// Hint text for notes field
  ///
  /// In en, this message translates to:
  /// **'Paste notes or type content here.'**
  String get materialNotesHint;

  /// Button to save file
  ///
  /// In en, this message translates to:
  /// **'Save file'**
  String get materialSaveFile;

  /// Material kind label for photo
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get materialKindPhoto;

  /// Material kind label for PDF
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get materialKindPdf;

  /// Material kind label for text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get materialKindText;

  /// Validation error when no photos selected
  ///
  /// In en, this message translates to:
  /// **'Add at least one photo.'**
  String get materialAddAtLeastOnePhoto;

  /// Validation error when title is empty
  ///
  /// In en, this message translates to:
  /// **'Add a title.'**
  String get materialAddTitle;

  /// Validation error when no PDF selected
  ///
  /// In en, this message translates to:
  /// **'Pick at least one PDF.'**
  String get materialPickAtLeastOnePdf;

  /// Validation error when title or content is empty
  ///
  /// In en, this message translates to:
  /// **'Add a title and content.'**
  String get materialAddTitleAndContent;

  /// Number of photos
  ///
  /// In en, this message translates to:
  /// **'{count} photo(s)'**
  String materialPhotosCount(int count);

  /// Subtitle for text material
  ///
  /// In en, this message translates to:
  /// **'Text  ·  {date}'**
  String materialTextSubtitle(String date);

  /// Error message when material fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load material: {error}'**
  String materialDetailCouldNotLoad(String error);

  /// Error message when material doesn't exist
  ///
  /// In en, this message translates to:
  /// **'Material not found'**
  String get materialDetailNotFound;

  /// Title when editing material
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get materialDetailEditing;

  /// Hint text for empty content field
  ///
  /// In en, this message translates to:
  /// **'Start writing…'**
  String get materialDetailStartWriting;

  /// Placeholder text when material has no content
  ///
  /// In en, this message translates to:
  /// **'_No content yet. Tap ✏️ to add notes._'**
  String get materialDetailNoContent;

  /// Error message when no images found
  ///
  /// In en, this message translates to:
  /// **'No images found'**
  String get materialDetailNoImages;

  /// Button text while opening file
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get materialDetailOpening;

  /// Button to open file in external app
  ///
  /// In en, this message translates to:
  /// **'Open in external app'**
  String get materialDetailOpenExternal;

  /// Error message when file is missing
  ///
  /// In en, this message translates to:
  /// **'File missing on disk. It may have been removed.'**
  String get materialDetailFileMissing;

  /// Error message when file fails to open
  ///
  /// In en, this message translates to:
  /// **'Could not open file: {message}'**
  String materialDetailCouldNotOpenFile(String message);

  /// Label for added date
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get materialDetailAdded;

  /// Label for file location
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get materialDetailLocation;

  /// Word count for text material
  ///
  /// In en, this message translates to:
  /// **'{count} words'**
  String materialDetailWords(int count);

  /// Title for rename dialog
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get materialActionsRename;

  /// Error message when PDF fails to open
  ///
  /// In en, this message translates to:
  /// **'Could not open PDF: {error}'**
  String pdfPickerCouldNotOpen(String error);

  /// Error message when pages fail to save
  ///
  /// In en, this message translates to:
  /// **'Failed to save pages: {error}'**
  String pdfPickerFailedToSave(String error);

  /// Loading message for PDF pages
  ///
  /// In en, this message translates to:
  /// **'Loading pages...'**
  String get pdfPickerLoading;

  /// Subtitle showing page count
  ///
  /// In en, this message translates to:
  /// **'{count} pages — tap to select'**
  String pdfPickerPagesCount(int count);

  /// Button text when no pages selected
  ///
  /// In en, this message translates to:
  /// **'Select pages to continue'**
  String get pdfPickerSelectPages;

  /// Button text with page count
  ///
  /// In en, this message translates to:
  /// **'Add {count} page(s)'**
  String pdfPickerAddPages(int count);

  /// Page number label
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String pdfPickerPage(int number);

  /// Error message when model fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load model: {error}'**
  String chatCouldNotLoadModel(String error);

  /// Error message when chat session fails to start
  ///
  /// In en, this message translates to:
  /// **'Failed to start chat session. Please try again.'**
  String get chatFailedToStartSession;

  /// Error message when session is interrupted
  ///
  /// In en, this message translates to:
  /// **'Session interrupted. Please try again.'**
  String get chatSessionInterrupted;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String chatError(String error);

  /// Error message when session doesn't exist
  ///
  /// In en, this message translates to:
  /// **'Session not found'**
  String get chatSessionNotFound;

  /// Confirmation dialog title for resetting chat
  ///
  /// In en, this message translates to:
  /// **'Reset chat?'**
  String get chatResetQuestion;

  /// Confirmation message for resetting chat
  ///
  /// In en, this message translates to:
  /// **'All messages will be deleted.'**
  String get chatResetConfirm;

  /// Button to reset chat
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get chatReset;

  /// Label when AI is thinking
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get chatThinking;

  /// Label for thought process section
  ///
  /// In en, this message translates to:
  /// **'Thought process'**
  String get chatThoughtProcess;

  /// Empty state title for chat
  ///
  /// In en, this message translates to:
  /// **'Ask Quex anything'**
  String get chatAskQuex;

  /// Empty state subtitle for chat
  ///
  /// In en, this message translates to:
  /// **'Ask about your notes, get a summary, or request quiz hints.'**
  String get chatAskQuexSubtitle;

  /// Quick prompt label for summarization
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get chatQuickSummarize;

  /// Quick prompt label for quiz hints
  ///
  /// In en, this message translates to:
  /// **'Quiz hints'**
  String get chatQuickQuizHints;

  /// Quick prompt label for simple explanation
  ///
  /// In en, this message translates to:
  /// **'Explain simply'**
  String get chatQuickExplainSimply;

  /// Suggestion chip label
  ///
  /// In en, this message translates to:
  /// **'Ask about \"{topic}\"'**
  String chatAskAbout(String topic);

  /// Label for session in tips panel
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get chatSession;

  /// Label for suggested topics in tips panel
  ///
  /// In en, this message translates to:
  /// **'Suggested topics'**
  String get chatSuggestedTopics;

  /// Hint text for chat input field
  ///
  /// In en, this message translates to:
  /// **'Ask Quex…'**
  String get chatAskQuexHint;

  /// Label in user bubble when a voice message was sent
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get chatVoiceMessage;

  /// Tooltip on mic button
  ///
  /// In en, this message translates to:
  /// **'Hold to speak'**
  String get chatMicHold;

  /// Snackbar when mic permission refused
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied. Enable it in Settings.'**
  String get chatMicPermissionDenied;

  /// Snackbar on recording error
  ///
  /// In en, this message translates to:
  /// **'Recording failed. Please try again.'**
  String get chatMicError;

  /// Placeholder text shown in input field while recording
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get chatListening;

  /// Loading overlay text while waiting for first response
  ///
  /// In en, this message translates to:
  /// **'Waiting for response...'**
  String get chatWaitingForResponse;

  /// Label for thinking mode toggle
  ///
  /// In en, this message translates to:
  /// **'Thinking mode'**
  String get chatThinkingMode;

  /// Description for thinking mode toggle
  ///
  /// In en, this message translates to:
  /// **'Show AI\'s thought process'**
  String get chatThinkingModeDescription;

  /// Confirmation dialog title for enabling thinking mode
  ///
  /// In en, this message translates to:
  /// **'Enable thinking mode?'**
  String get chatThinkingModeConfirm;

  /// Confirmation message for enabling thinking mode
  ///
  /// In en, this message translates to:
  /// **'This will clear the current conversation and restart the chat with thinking enabled. Continue?'**
  String get chatThinkingModeConfirmMessage;

  /// Confirmation dialog title for disabling thinking mode
  ///
  /// In en, this message translates to:
  /// **'Disable thinking mode?'**
  String get chatThinkingModeDisableConfirm;

  /// Confirmation message for disabling thinking mode
  ///
  /// In en, this message translates to:
  /// **'This will clear the current conversation and restart the chat with thinking disabled. Continue?'**
  String get chatThinkingModeDisableMessage;

  /// Label for token count
  ///
  /// In en, this message translates to:
  /// **'tokens'**
  String get chatTokens;

  /// Label for thinking mode toggle
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get chatThinkingLabel;

  /// Title for quiz detail screen
  ///
  /// In en, this message translates to:
  /// **'Quiz Questions'**
  String get quizDetailTitle;

  /// Error message in quiz detail
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String quizDetailError(String error);

  /// Error message when quiz not found
  ///
  /// In en, this message translates to:
  /// **'Quiz not found'**
  String get quizDetailNotFound;

  /// Message when quiz may be deleted
  ///
  /// In en, this message translates to:
  /// **'This quiz may have been deleted.'**
  String get quizDetailDeleted;

  /// Button to finish quiz
  ///
  /// In en, this message translates to:
  /// **'Finish Quiz'**
  String get quizDetailFinish;

  /// Date label for today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get quizDetailToday;

  /// Date label for yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get quizDetailYesterday;

  /// Number of questions
  ///
  /// In en, this message translates to:
  /// **'{count} Questions'**
  String quizDetailQuestionsCount(int count);

  /// Number of answered questions
  ///
  /// In en, this message translates to:
  /// **'{count} answered'**
  String quizDetailAnswered(int count);

  /// Error message when question chat preload fails
  ///
  /// In en, this message translates to:
  /// **'Failed to preload chat session: {error}'**
  String questionChatFailedToPreload(String error);

  /// Error message when question not found
  ///
  /// In en, this message translates to:
  /// **'Question not found'**
  String get questionChatNotFound;

  /// Title for question chat screen
  ///
  /// In en, this message translates to:
  /// **'Question {number}'**
  String questionChatTitle(int number);

  /// Score message for correct answer
  ///
  /// In en, this message translates to:
  /// **'Correct! 🎉 No explanation needed.'**
  String get questionChatScoreCorrect;

  /// Score message for partial credit
  ///
  /// In en, this message translates to:
  /// **'Partial credit — keep going!'**
  String get questionChatScorePartial;

  /// Score message for incorrect answer
  ///
  /// In en, this message translates to:
  /// **'Not quite — let\'s keep discussing'**
  String get questionChatScoreIncorrect;

  /// Label for question card
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get questionChatQuestionLabel;

  /// Hint text for question chat input field
  ///
  /// In en, this message translates to:
  /// **'Talk to Quex…'**
  String get questionChatTalkToQuex;

  /// Error message when summary fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load summary: {error}'**
  String summaryFailedToLoad(String error);

  /// Error message when quiz not found
  ///
  /// In en, this message translates to:
  /// **'Quiz not found'**
  String get summaryQuizNotFound;

  /// Error message when session fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load session: {error}'**
  String summaryFailedToLoadSession(String error);

  /// Title for summary screen
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summaryTitle;

  /// Button to go to chat
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get summaryChat;

  /// Default session title
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get summarySession;

  /// Section header for results
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get summaryResults;

  /// Subtitle for results section
  ///
  /// In en, this message translates to:
  /// **'Review the quiz and keep the learning loop going.'**
  String get summaryResultsSubtitle;

  /// Status when quiz is completed
  ///
  /// In en, this message translates to:
  /// **'Quiz completed'**
  String get summaryQuizCompleted;

  /// Status when quiz is in progress
  ///
  /// In en, this message translates to:
  /// **'Quiz still in progress'**
  String get summaryQuizInProgress;

  /// Of total count
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String summaryOf(int total);

  /// Label for correct count
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get summaryCorrect;

  /// Label for total count
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get summaryTotal;

  /// Section header for next steps
  ///
  /// In en, this message translates to:
  /// **'Next steps'**
  String get summaryNextSteps;

  /// Subtitle for next steps section
  ///
  /// In en, this message translates to:
  /// **'Keep the session moving forward.'**
  String get summaryNextStepsSubtitle;

  /// Button to discuss quiz
  ///
  /// In en, this message translates to:
  /// **'Discuss'**
  String get summaryDiscuss;

  /// Button to retry quiz
  ///
  /// In en, this message translates to:
  /// **'Retry quiz'**
  String get summaryRetryQuiz;

  /// Button to go to session details
  ///
  /// In en, this message translates to:
  /// **'Session details'**
  String get summarySessionDetails;

  /// Section header for review
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get summaryReview;

  /// Subtitle for review section
  ///
  /// In en, this message translates to:
  /// **'Focus on the questions that need another pass.'**
  String get summaryReviewSubtitle;

  /// Message when no questions were missed
  ///
  /// In en, this message translates to:
  /// **'No missed questions. Nice work.'**
  String get summaryNoMissed;

  /// Label for user's answer
  ///
  /// In en, this message translates to:
  /// **'Your answer: {answer}'**
  String summaryYourAnswer(String answer);

  /// Prompt to chat for more info
  ///
  /// In en, this message translates to:
  /// **'Chat with Quex to learn more.'**
  String get summaryChatToLearn;

  /// Error when no materials exist
  ///
  /// In en, this message translates to:
  /// **'Add study materials first.'**
  String get quizGenAddMaterialsFirst;

  /// Error message when quiz generation fails
  ///
  /// In en, this message translates to:
  /// **'Quiz generation failed: {message}'**
  String quizGenFailed(String message);

  /// Status text for material selection
  ///
  /// In en, this message translates to:
  /// **'Pick your materials'**
  String get quizGenPickMaterials;

  /// Status text while loading model
  ///
  /// In en, this message translates to:
  /// **'Loading brain...'**
  String get quizGenLoadingBrain;

  /// Status text when quiz is complete
  ///
  /// In en, this message translates to:
  /// **'Quiz is ready! 🎉'**
  String get quizGenReady;

  /// Status text while extracting questions
  ///
  /// In en, this message translates to:
  /// **'Extracting existing questions...'**
  String get quizGenExtracting;

  /// Status text while generating quiz
  ///
  /// In en, this message translates to:
  /// **'Generating quiz...'**
  String get quizGenGenerating;

  /// Status text while AI is thinking
  ///
  /// In en, this message translates to:
  /// **'Quex is thinking...'**
  String get quizGenThinking;

  /// Status when existing questions found
  ///
  /// In en, this message translates to:
  /// **'Found existing questions'**
  String get quizGenFoundQuestions;

  /// Status when no existing questions
  ///
  /// In en, this message translates to:
  /// **'No existing questions found'**
  String get quizGenNoQuestions;

  /// Default status text
  ///
  /// In en, this message translates to:
  /// **'Getting ready...'**
  String get quizGenGettingReady;

  /// Title for material selection
  ///
  /// In en, this message translates to:
  /// **'Which materials to quiz on?'**
  String get quizGenWhichMaterials;

  /// Subtitle for material selection
  ///
  /// In en, this message translates to:
  /// **'Quex will scan these for existing questions.'**
  String get quizGenScanMaterials;

  /// Button text while loading model
  ///
  /// In en, this message translates to:
  /// **'Loading model…'**
  String get quizGenLoadingModel;

  /// Button text when no materials selected
  ///
  /// In en, this message translates to:
  /// **'Select materials first'**
  String get quizGenSelectFirst;

  /// Button to generate quiz
  ///
  /// In en, this message translates to:
  /// **'Generate quiz ({count})'**
  String quizGenGenerate(int count);

  /// Title when questions found
  ///
  /// In en, this message translates to:
  /// **'Found existing questions'**
  String get quizGenFoundTitle;

  /// Title when no questions
  ///
  /// In en, this message translates to:
  /// **'No existing questions'**
  String get quizGenNoQuestionsTitle;

  /// Description when questions found
  ///
  /// In en, this message translates to:
  /// **'These questions were found in your materials. Quex will use these to generate your quiz.'**
  String get quizGenFoundDescription;

  /// Description when no questions
  ///
  /// In en, this message translates to:
  /// **'No quiz questions were found in your materials. Quex will generate questions from scratch.'**
  String get quizGenNoQuestionsDescription;

  /// Button to continue to generation
  ///
  /// In en, this message translates to:
  /// **'Continue to generate quiz'**
  String get quizGenContinue;

  /// Title for quiz debug screen
  ///
  /// In en, this message translates to:
  /// **'Generated Quiz'**
  String get quizDebugTitle;

  /// Section header for generated questions
  ///
  /// In en, this message translates to:
  /// **'Questions Generated'**
  String get quizDebugQuestionsGenerated;

  /// Count of questions ready to review
  ///
  /// In en, this message translates to:
  /// **'{count} question{s} ready to review.'**
  String quizDebugReadyToReview(int count, String s);

  /// Question type label
  ///
  /// In en, this message translates to:
  /// **'Multiple Choice'**
  String get quizDebugMultipleChoice;

  /// Question type label
  ///
  /// In en, this message translates to:
  /// **'Text Answer'**
  String get quizDebugTextAnswer;

  /// Button to view quiz
  ///
  /// In en, this message translates to:
  /// **'View Quiz'**
  String get quizDebugViewQuiz;

  /// TTS phrase spoken when AI enters thinking mode
  ///
  /// In en, this message translates to:
  /// **'Let me think for a moment…'**
  String get chatTtsSayThinking;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
