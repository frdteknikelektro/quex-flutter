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
  String get warmingUp => 'Warming up...';

  @override
  String downloadingBrain(int percent) {
    return 'Downloading brain… $percent% 🧠';
  }

  @override
  String downloadingModelVariant(String variant, String size) {
    return 'Gemma 4 $variant ($size)';
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
  String get clearAllSessionsConfirm =>
      'This will permanently delete all study sessions, materials, quizzes, and chat history for this profile.';

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

  @override
  String homeFailedToLoadSessions(String error) {
    return 'Failed to load sessions: $error';
  }

  @override
  String get homeRecentSessions => 'Recent Sessions';

  @override
  String homeFailedToLoadProfiles(String error) {
    return 'Failed to load profiles: $error';
  }

  @override
  String get homeGoodMorning => 'Good morning';

  @override
  String get homeGoodAfternoon => 'Good afternoon';

  @override
  String get homeGoodEvening => 'Good evening';

  @override
  String get homeSeeLess => 'See less';

  @override
  String get homeSeeMore => 'See more';

  @override
  String get homeToday => 'Today';

  @override
  String get homeYesterday => 'Yesterday';

  @override
  String get homeLetsStartLearning => 'Let\'s start learning!';

  @override
  String get homeCreateFirstSession =>
      'Create your very first study session and blast off into a world of fun!';

  @override
  String get homeStartMyAdventure => 'Start my adventure!';

  @override
  String get homeNoProfilesYet => 'No profiles yet';

  @override
  String get homeSwitchToProfile =>
      'Switch to a profile to start a new study flow.';

  @override
  String get newSessionAddTitleFirst => 'Add a session title first.';

  @override
  String get newSessionTitle => 'Session title';

  @override
  String get newSessionTitleHint => 'e.g. Fractions practice';

  @override
  String get newSessionPickEmoji => 'Pick an emoji';

  @override
  String newSessionGrade(int grade) {
    return 'Grade $grade';
  }

  @override
  String get newSessionCreating => 'Creating...';

  @override
  String sessionDetailFailedToLoad(String error) {
    return 'Failed to load session: $error';
  }

  @override
  String get sessionDetailNotFound => 'Session not found';

  @override
  String get sessionDetailGenerateQuiz => 'Generate quiz';

  @override
  String sessionDetailGradeAndDate(int grade, String date) {
    return 'Grade $grade  •  $date';
  }

  @override
  String get sessionDetailAddNotes => 'Add notes and references';

  @override
  String get sessionDetailOneMaterial => '1 study material';

  @override
  String sessionDetailMaterialsCount(int count) {
    return '$count study materials';
  }

  @override
  String get sessionDetailStudyMaterials => 'Study Materials';

  @override
  String get sessionDetailChatWithAI => 'Chat with AI';

  @override
  String get sessionDetailChatSubtitle => 'Ask questions about your notes';

  @override
  String get sessionDetailWhichMaterials => 'Which materials to chat about?';

  @override
  String get sessionDetailQuexWillUse =>
      'Quex will use only these in the conversation.';

  @override
  String get sessionDetailMaterialKindText => 'Text';

  @override
  String get sessionDetailMaterialKindDocument => 'Document';

  @override
  String get sessionDetailMaterialKindPhoto => 'Photo';

  @override
  String get sessionDetailSelectAtLeastOne => 'Select at least one material';

  @override
  String sessionDetailStartChat(int count) {
    return 'Start chat ($count)';
  }

  @override
  String get sessionDetailRecentQuizzes => 'Recent Quizzes';

  @override
  String sessionDetailScore(int score) {
    return 'Score $score%';
  }

  @override
  String get sessionDetailInProgress => 'In progress';

  @override
  String sessionDetailQuestionsCount(int count) {
    return '$count questions';
  }

  @override
  String get sessionDetailAddMaterialsFirst =>
      'Add study materials first, then generate a quiz.';

  @override
  String get sessionDetailReadyToMakeQuiz => 'Ready to make a quiz?';

  @override
  String get sessionDetailEditSession => 'Edit Session';

  @override
  String get materialDeleteQuestion => 'Delete material?';

  @override
  String get materialDeleteConfirm => 'This note will be permanently removed.';

  @override
  String materialFailedToLoadSession(String error) {
    return 'Failed to load session: $error';
  }

  @override
  String get materialSessionNotFound => 'Session not found';

  @override
  String materialCouldNotLoadFiles(String error) {
    return 'Could not load files: $error';
  }

  @override
  String get materialAddMaterial => 'Add material';

  @override
  String materialCouldNotOpen(String message) {
    return 'Could not open: $message';
  }

  @override
  String get materialFolderEmpty => 'Your study folder is empty';

  @override
  String get materialFolderEmptySubtitle =>
      'Tap \"Add material\" to drop in notes, documents, or photos.';

  @override
  String get materialAddToFolder => 'Add to Study Folder';

  @override
  String get materialCamera => 'Camera';

  @override
  String get materialGallery => 'Gallery';

  @override
  String get materialTitle => 'Title';

  @override
  String get materialPickPdf => 'Pick PDF';

  @override
  String get materialAddMore => 'Add more';

  @override
  String get materialNotesContent => 'Notes / content';

  @override
  String get materialNotesHint => 'Paste notes or type content here.';

  @override
  String get materialSaveFile => 'Save file';

  @override
  String get materialKindPhoto => 'Photo';

  @override
  String get materialKindPdf => 'PDF';

  @override
  String get materialKindText => 'Text';

  @override
  String get materialAddAtLeastOnePhoto => 'Add at least one photo.';

  @override
  String get materialAddTitle => 'Add a title.';

  @override
  String get materialPickAtLeastOnePdf => 'Pick at least one PDF.';

  @override
  String get materialAddTitleAndContent => 'Add a title and content.';

  @override
  String materialPhotosCount(int count) {
    return '$count photo(s)';
  }

  @override
  String materialTextSubtitle(String date) {
    return 'Text  ·  $date';
  }

  @override
  String materialDetailCouldNotLoad(String error) {
    return 'Could not load material: $error';
  }

  @override
  String get materialDetailNotFound => 'Material not found';

  @override
  String get materialDetailEditing => 'Editing';

  @override
  String get materialDetailStartWriting => 'Start writing…';

  @override
  String get materialDetailNoContent =>
      '_No content yet. Tap ✏️ to add notes._';

  @override
  String get materialDetailNoImages => 'No images found';

  @override
  String get materialDetailOpening => 'Opening…';

  @override
  String get materialDetailOpenExternal => 'Open in external app';

  @override
  String get materialDetailFileMissing =>
      'File missing on disk. It may have been removed.';

  @override
  String materialDetailCouldNotOpenFile(String message) {
    return 'Could not open file: $message';
  }

  @override
  String get materialDetailAdded => 'Added';

  @override
  String get materialDetailLocation => 'Location';

  @override
  String materialDetailWords(int count) {
    return '$count words';
  }

  @override
  String get materialActionsRename => 'Rename';

  @override
  String pdfPickerCouldNotOpen(String error) {
    return 'Could not open PDF: $error';
  }

  @override
  String pdfPickerFailedToSave(String error) {
    return 'Failed to save pages: $error';
  }

  @override
  String get pdfPickerLoading => 'Loading pages...';

  @override
  String pdfPickerPagesCount(int count) {
    return '$count pages — tap to select';
  }

  @override
  String get pdfPickerSelectPages => 'Select pages to continue';

  @override
  String pdfPickerAddPages(int count) {
    return 'Add $count page(s)';
  }

  @override
  String pdfPickerPage(int number) {
    return 'Page $number';
  }

  @override
  String chatCouldNotLoadModel(String error) {
    return 'Could not load model: $error';
  }

  @override
  String get chatFailedToStartSession =>
      'Failed to start chat session. Please try again.';

  @override
  String get chatSessionInterrupted => 'Session interrupted. Please try again.';

  @override
  String chatError(String error) {
    return 'Error: $error';
  }

  @override
  String get chatSessionNotFound => 'Session not found';

  @override
  String get chatResetQuestion => 'Reset chat?';

  @override
  String get chatResetConfirm => 'All messages will be deleted.';

  @override
  String get chatReset => 'Reset';

  @override
  String get chatThinking => 'Thinking…';

  @override
  String get chatThoughtProcess => 'Thought process';

  @override
  String get chatAskQuex => 'Ask Quex anything';

  @override
  String get chatAskQuexSubtitle =>
      'Ask about your notes, get a summary, or request quiz hints.';

  @override
  String get chatQuickSummarize => 'Summarize';

  @override
  String get chatQuickQuizHints => 'Quiz hints';

  @override
  String get chatQuickExplainSimply => 'Explain simply';

  @override
  String chatAskAbout(String topic) {
    return 'Ask about \"$topic\"';
  }

  @override
  String get chatSession => 'Session';

  @override
  String get chatSuggestedTopics => 'Suggested topics';

  @override
  String get chatAskQuexHint => 'Ask Quex…';

  @override
  String get chatVoiceMessage => 'Voice message';

  @override
  String get chatMicHold => 'Hold to speak';

  @override
  String get chatMicPermissionDenied =>
      'Microphone permission denied. Enable it in Settings.';

  @override
  String get chatMicError => 'Recording failed. Please try again.';

  @override
  String get chatListening => 'Listening...';

  @override
  String get chatWaitingForResponse => 'Waiting for response...';

  @override
  String get chatThinkingMode => 'Thinking mode';

  @override
  String get chatThinkingModeDescription => 'Show AI\'s thought process';

  @override
  String get chatThinkingModeConfirm => 'Enable thinking mode?';

  @override
  String get chatThinkingModeConfirmMessage =>
      'This will clear the current conversation and restart the chat with thinking enabled. Continue?';

  @override
  String get chatThinkingModeDisableConfirm => 'Disable thinking mode?';

  @override
  String get chatThinkingModeDisableMessage =>
      'This will clear the current conversation and restart the chat with thinking disabled. Continue?';

  @override
  String get chatTokens => 'tokens';

  @override
  String get chatThinkingLabel => 'Thinking';

  @override
  String get quizDetailTitle => 'Quiz Questions';

  @override
  String quizDetailError(String error) {
    return 'Error: $error';
  }

  @override
  String get quizDetailNotFound => 'Quiz not found';

  @override
  String get quizDetailDeleted => 'This quiz may have been deleted.';

  @override
  String get quizDetailFinish => 'Finish Quiz';

  @override
  String get quizDetailToday => 'Today';

  @override
  String get quizDetailYesterday => 'Yesterday';

  @override
  String quizDetailQuestionsCount(int count) {
    return '$count Questions';
  }

  @override
  String quizDetailAnswered(int count) {
    return '$count answered';
  }

  @override
  String questionChatFailedToPreload(String error) {
    return 'Failed to preload chat session: $error';
  }

  @override
  String get questionChatNotFound => 'Question not found';

  @override
  String questionChatTitle(int number) {
    return 'Question $number';
  }

  @override
  String get questionChatScoreCorrect => 'Correct! 🎉 No explanation needed.';

  @override
  String get questionChatScorePartial => 'Partial credit — keep going!';

  @override
  String get questionChatScoreIncorrect => 'Not quite — let\'s keep discussing';

  @override
  String get questionChatQuestionLabel => 'Question';

  @override
  String get questionChatTalkToQuex => 'Talk to Quex…';

  @override
  String summaryFailedToLoad(String error) {
    return 'Failed to load summary: $error';
  }

  @override
  String get summaryQuizNotFound => 'Quiz not found';

  @override
  String summaryFailedToLoadSession(String error) {
    return 'Failed to load session: $error';
  }

  @override
  String get summaryTitle => 'Summary';

  @override
  String get summaryChat => 'Chat';

  @override
  String get summarySession => 'Session';

  @override
  String get summaryResults => 'Results';

  @override
  String get summaryResultsSubtitle =>
      'Review the quiz and keep the learning loop going.';

  @override
  String get summaryQuizCompleted => 'Quiz completed';

  @override
  String get summaryQuizInProgress => 'Quiz still in progress';

  @override
  String summaryOf(int total) {
    return 'of $total';
  }

  @override
  String get summaryCorrect => 'Correct';

  @override
  String get summaryTotal => 'Total';

  @override
  String get summaryNextSteps => 'Next steps';

  @override
  String get summaryNextStepsSubtitle => 'Keep the session moving forward.';

  @override
  String get summaryDiscuss => 'Discuss';

  @override
  String get summaryRetryQuiz => 'Retry quiz';

  @override
  String get summarySessionDetails => 'Session details';

  @override
  String get summaryReview => 'Review';

  @override
  String get summaryReviewSubtitle =>
      'Focus on the questions that need another pass.';

  @override
  String get summaryNoMissed => 'No missed questions. Nice work.';

  @override
  String summaryYourAnswer(String answer) {
    return 'Your answer: $answer';
  }

  @override
  String get summaryChatToLearn => 'Chat with Quex to learn more.';

  @override
  String get quizGenAddMaterialsFirst => 'Add study materials first.';

  @override
  String quizGenFailed(String message) {
    return 'Quiz generation failed: $message';
  }

  @override
  String get quizGenPickMaterials => 'Pick your materials';

  @override
  String get quizGenLoadingBrain => 'Loading brain...';

  @override
  String get quizGenReady => 'Quiz is ready! 🎉';

  @override
  String get quizGenExtracting => 'Extracting existing questions...';

  @override
  String get quizGenGenerating => 'Generating quiz...';

  @override
  String get quizGenThinking => 'Quex is thinking...';

  @override
  String get quizGenFoundQuestions => 'Found existing questions';

  @override
  String get quizGenNoQuestions => 'No existing questions found';

  @override
  String get quizGenGettingReady => 'Getting ready...';

  @override
  String get quizGenWhichMaterials => 'Which materials to quiz on?';

  @override
  String get quizGenScanMaterials =>
      'Quex will scan these for existing questions.';

  @override
  String get quizGenLoadingModel => 'Loading model…';

  @override
  String get quizGenSelectFirst => 'Select materials first';

  @override
  String quizGenGenerate(int count) {
    return 'Generate quiz ($count)';
  }

  @override
  String get quizGenFoundTitle => 'Found existing questions';

  @override
  String get quizGenNoQuestionsTitle => 'No existing questions';

  @override
  String get quizGenFoundDescription =>
      'These questions were found in your materials. Quex will use these to generate your quiz.';

  @override
  String get quizGenNoQuestionsDescription =>
      'No quiz questions were found in your materials. Quex will generate questions from scratch.';

  @override
  String get quizGenContinue => 'Continue to generate quiz';

  @override
  String get quizDebugTitle => 'Generated Quiz';

  @override
  String get quizDebugQuestionsGenerated => 'Questions Generated';

  @override
  String quizDebugReadyToReview(int count, String s) {
    return '$count question$s ready to review.';
  }

  @override
  String get quizDebugMultipleChoice => 'Multiple Choice';

  @override
  String get quizDebugTextAnswer => 'Text Answer';

  @override
  String get quizDebugViewQuiz => 'View Quiz';
}
