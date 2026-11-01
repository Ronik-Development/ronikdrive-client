import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_en.dart';

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
    Locale('cs'),
    Locale('en'),
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'RonikCloud'**
  String get appTitle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @paymentProcessing.
  ///
  /// In en, this message translates to:
  /// **'Payment processing...'**
  String get paymentProcessing;

  /// No description provided for @paymentConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed! Your workspace will unlock in a moment.'**
  String get paymentConfirmed;

  /// No description provided for @storageUsage.
  ///
  /// In en, this message translates to:
  /// **'Storage Usage'**
  String get storageUsage;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @shared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get shared;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @testerPageTitle.
  ///
  /// In en, this message translates to:
  /// **'RonikCloud founding beta'**
  String get testerPageTitle;

  /// No description provided for @testerEyebrow.
  ///
  /// In en, this message translates to:
  /// **'FOUNDING BETA'**
  String get testerEyebrow;

  /// No description provided for @testerHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Test one real file workflow'**
  String get testerHeroTitle;

  /// No description provided for @testerHeroBody.
  ///
  /// In en, this message translates to:
  /// **'RonikCloud is looking for freelancers, creators, consultants, and small teams who regularly send, collect, or back up client files.'**
  String get testerHeroBody;

  /// No description provided for @testerHeroAsk.
  ///
  /// In en, this message translates to:
  /// **'Join if you can install an available beta, try one workflow with non-critical copies, and tell us exactly where it fails or feels unclear.'**
  String get testerHeroAsk;

  /// No description provided for @testerFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Request beta access'**
  String get testerFormTitle;

  /// No description provided for @testerFormBody.
  ///
  /// In en, this message translates to:
  /// **'Testing is selected by default. Product news is optional and kept separate.'**
  String get testerFormBody;

  /// No description provided for @testerEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get testerEmailLabel;

  /// No description provided for @testerEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get testerEmailHint;

  /// No description provided for @testerSubmit.
  ///
  /// In en, this message translates to:
  /// **'Request beta access'**
  String get testerSubmit;

  /// No description provided for @testerSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Requesting access'**
  String get testerSubmitting;

  /// No description provided for @testerTestingTitle.
  ///
  /// In en, this message translates to:
  /// **'Participate in product testing'**
  String get testerTestingTitle;

  /// No description provided for @testerTestingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive available beta links and focused testing requests. For Android, use the Google Account email on your device. Access is sent after manual review.'**
  String get testerTestingSubtitle;

  /// No description provided for @testerProductNewsTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive weekly product news'**
  String get testerProductNewsTitle;

  /// No description provided for @testerProductNewsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An optional short RonikCloud progress update, sent about once a week.'**
  String get testerProductNewsSubtitle;

  /// No description provided for @testerConsentNote.
  ///
  /// In en, this message translates to:
  /// **'We use your email and these separate consent choices to run the tester program. You can unsubscribe from email updates.'**
  String get testerConsentNote;

  /// No description provided for @testerInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get testerInvalidEmail;

  /// No description provided for @testerChoosePreference.
  ///
  /// In en, this message translates to:
  /// **'Choose testing, product news, or both.'**
  String get testerChoosePreference;

  /// No description provided for @testerSuccessTesting.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the tester list. Check your inbox for confirmation. Beta access is reviewed manually; when approved, you\'ll receive the available platform links.'**
  String get testerSuccessTesting;

  /// No description provided for @testerSuccessNews.
  ///
  /// In en, this message translates to:
  /// **'Your product news preference has been saved.'**
  String get testerSuccessNews;

  /// No description provided for @testerFailureInvalid.
  ///
  /// In en, this message translates to:
  /// **'The request could not be accepted. Check the email and preferences, then try again.'**
  String get testerFailureInvalid;

  /// No description provided for @testerFailureAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered for the selected updates.'**
  String get testerFailureAlreadyRegistered;

  /// No description provided for @testerFailureRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many signup attempts were made. Wait briefly and try again.'**
  String get testerFailureRateLimited;

  /// No description provided for @testerFailureUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The tester signup service is temporarily unavailable. Check your connection and try again.'**
  String get testerFailureUnavailable;

  /// No description provided for @testerFailureGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unable to join the tester list. Please try again.'**
  String get testerFailureGeneric;

  /// No description provided for @testerWorkflowTitle.
  ///
  /// In en, this message translates to:
  /// **'What we ask from testers'**
  String get testerWorkflowTitle;

  /// No description provided for @testerStepOneTitle.
  ///
  /// In en, this message translates to:
  /// **'Install an available beta'**
  String get testerStepOneTitle;

  /// No description provided for @testerStepOneDetail.
  ///
  /// In en, this message translates to:
  /// **'Join with the email for your target platform. We send access links after any required manual review.'**
  String get testerStepOneDetail;

  /// No description provided for @testerStepTwoTitle.
  ///
  /// In en, this message translates to:
  /// **'Test one workflow'**
  String get testerStepTwoTitle;

  /// No description provided for @testerStepTwoDetail.
  ///
  /// In en, this message translates to:
  /// **'Using non-critical copies, try upload and download, a protected link or file request, or a recovery step.'**
  String get testerStepTwoDetail;

  /// No description provided for @testerStepThreeTitle.
  ///
  /// In en, this message translates to:
  /// **'Send blunt feedback'**
  String get testerStepThreeTitle;

  /// No description provided for @testerStepThreeDetail.
  ///
  /// In en, this message translates to:
  /// **'Reply to a tester email with the exact step that failed, surprised you, or felt unclear.'**
  String get testerStepThreeDetail;

  /// No description provided for @testerBoundariesTitle.
  ///
  /// In en, this message translates to:
  /// **'Founding-beta boundaries'**
  String get testerBoundariesTitle;

  /// No description provided for @testerBoundariesBody.
  ///
  /// In en, this message translates to:
  /// **'This is pre-release software and has not been independently audited. Use non-critical copies, keep another backup, and do not depend on RonikCloud as your only copy or for production work.'**
  String get testerBoundariesBody;

  /// No description provided for @testerPlatformsTitle.
  ///
  /// In en, this message translates to:
  /// **'Available beta builds'**
  String get testerPlatformsTitle;

  /// No description provided for @testerPlatformsBody.
  ///
  /// In en, this message translates to:
  /// **'Availability is checked live. Access links are sent after manual review where required.'**
  String get testerPlatformsBody;

  /// No description provided for @testerPlatformAndroid.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get testerPlatformAndroid;

  /// No description provided for @testerPlatformIos.
  ///
  /// In en, this message translates to:
  /// **'iPhone and iPad'**
  String get testerPlatformIos;

  /// No description provided for @testerPlatformMacos.
  ///
  /// In en, this message translates to:
  /// **'Mac'**
  String get testerPlatformMacos;

  /// No description provided for @testerPlatformWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get testerPlatformWindows;

  /// No description provided for @testerPlatformLinux.
  ///
  /// In en, this message translates to:
  /// **'Linux'**
  String get testerPlatformLinux;

  /// No description provided for @testerChannelGooglePlay.
  ///
  /// In en, this message translates to:
  /// **'Google Play beta'**
  String get testerChannelGooglePlay;

  /// No description provided for @testerChannelTestFlight.
  ///
  /// In en, this message translates to:
  /// **'Apple TestFlight beta'**
  String get testerChannelTestFlight;

  /// No description provided for @testerChannelDirectDownload.
  ///
  /// In en, this message translates to:
  /// **'Direct download'**
  String get testerChannelDirectDownload;

  /// No description provided for @testerAvailabilityChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get testerAvailabilityChecking;

  /// No description provided for @testerAvailabilityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Check downloads'**
  String get testerAvailabilityUnknown;

  /// No description provided for @testerAvailabilityAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available now'**
  String get testerAvailabilityAvailable;

  /// No description provided for @testerAvailabilityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not published'**
  String get testerAvailabilityUnavailable;

  /// No description provided for @testerCheckDownloads.
  ///
  /// In en, this message translates to:
  /// **'Check all downloads'**
  String get testerCheckDownloads;

  /// No description provided for @testerReferralTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite one workflow peer'**
  String get testerReferralTitle;

  /// No description provided for @testerReferralBody.
  ///
  /// In en, this message translates to:
  /// **'Know someone who regularly handles client files? Invite them to evaluate the founding beta with you. Sharing is optional and opens your device\'s share sheet.'**
  String get testerReferralBody;

  /// No description provided for @testerReferralButton.
  ///
  /// In en, this message translates to:
  /// **'Invite one person'**
  String get testerReferralButton;

  /// No description provided for @testerReferralShareText.
  ///
  /// In en, this message translates to:
  /// **'RonikCloud is looking for founding-beta testers who handle client files. It encrypts protected file content and names on the device, but it is early and has not been independently audited. Use non-critical copies and keep another backup. Want to test one workflow with me?'**
  String get testerReferralShareText;

  /// No description provided for @testerReferralShareFailure.
  ///
  /// In en, this message translates to:
  /// **'The share sheet could not be opened. Your beta request is still saved.'**
  String get testerReferralShareFailure;
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
      <String>['cs', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
