// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RonikCloud';

  @override
  String get signOut => 'Sign out';

  @override
  String get upload => 'Upload';

  @override
  String get settings => 'Settings';

  @override
  String get paymentProcessing => 'Payment processing...';

  @override
  String get paymentConfirmed =>
      'Payment confirmed! Your workspace will unlock in a moment.';

  @override
  String get storageUsage => 'Storage Usage';

  @override
  String get files => 'Files';

  @override
  String get folders => 'Folders';

  @override
  String get offline => 'Offline';

  @override
  String get shared => 'Shared';

  @override
  String get recent => 'Recent';

  @override
  String get search => 'Search';

  @override
  String get testerPageTitle => 'RonikCloud founding beta';

  @override
  String get testerEyebrow => 'FOUNDING BETA';

  @override
  String get testerHeroTitle => 'Test one real file workflow';

  @override
  String get testerHeroBody =>
      'RonikCloud is looking for freelancers, creators, consultants, and small teams who regularly send, collect, or back up client files.';

  @override
  String get testerHeroAsk =>
      'Join if you can install an available beta, try one workflow with non-critical copies, and tell us exactly where it fails or feels unclear.';

  @override
  String get testerFormTitle => 'Request beta access';

  @override
  String get testerFormBody =>
      'Testing is selected by default. Product news is optional and kept separate.';

  @override
  String get testerEmailLabel => 'Email';

  @override
  String get testerEmailHint => 'you@example.com';

  @override
  String get testerSubmit => 'Request beta access';

  @override
  String get testerSubmitting => 'Requesting access';

  @override
  String get testerTestingTitle => 'Participate in product testing';

  @override
  String get testerTestingSubtitle =>
      'Receive available beta links and focused testing requests. For Android, use the Google Account email on your device. Access is sent after manual review.';

  @override
  String get testerProductNewsTitle => 'Receive weekly product news';

  @override
  String get testerProductNewsSubtitle =>
      'An optional short RonikCloud progress update, sent about once a week.';

  @override
  String get testerConsentNote =>
      'We use your email and these separate consent choices to run the tester program. You can unsubscribe from email updates.';

  @override
  String get testerInvalidEmail => 'Enter a valid email address.';

  @override
  String get testerChoosePreference => 'Choose testing, product news, or both.';

  @override
  String get testerSuccessTesting =>
      'You\'re on the tester list. Check your inbox for confirmation. Beta access is reviewed manually; when approved, you\'ll receive the available platform links.';

  @override
  String get testerSuccessNews =>
      'Your product news preference has been saved.';

  @override
  String get testerFailureInvalid =>
      'The request could not be accepted. Check the email and preferences, then try again.';

  @override
  String get testerFailureAlreadyRegistered =>
      'This email is already registered for the selected updates.';

  @override
  String get testerFailureRateLimited =>
      'Too many signup attempts were made. Wait briefly and try again.';

  @override
  String get testerFailureUnavailable =>
      'The tester signup service is temporarily unavailable. Check your connection and try again.';

  @override
  String get testerFailureGeneric =>
      'Unable to join the tester list. Please try again.';

  @override
  String get testerWorkflowTitle => 'What we ask from testers';

  @override
  String get testerStepOneTitle => 'Install an available beta';

  @override
  String get testerStepOneDetail =>
      'Join with the email for your target platform. We send access links after any required manual review.';

  @override
  String get testerStepTwoTitle => 'Test one workflow';

  @override
  String get testerStepTwoDetail =>
      'Using non-critical copies, try upload and download, a protected link or file request, or a recovery step.';

  @override
  String get testerStepThreeTitle => 'Send blunt feedback';

  @override
  String get testerStepThreeDetail =>
      'Reply to a tester email with the exact step that failed, surprised you, or felt unclear.';

  @override
  String get testerBoundariesTitle => 'Founding-beta boundaries';

  @override
  String get testerBoundariesBody =>
      'This is pre-release software and has not been independently audited. Use non-critical copies, keep another backup, and do not depend on RonikCloud as your only copy or for production work.';

  @override
  String get testerPlatformsTitle => 'Available beta builds';

  @override
  String get testerPlatformsBody =>
      'Availability is checked live. Access links are sent after manual review where required.';

  @override
  String get testerPlatformAndroid => 'Android';

  @override
  String get testerPlatformIos => 'iPhone and iPad';

  @override
  String get testerPlatformMacos => 'Mac';

  @override
  String get testerPlatformWindows => 'Windows';

  @override
  String get testerPlatformLinux => 'Linux';

  @override
  String get testerChannelGooglePlay => 'Google Play beta';

  @override
  String get testerChannelTestFlight => 'Apple TestFlight beta';

  @override
  String get testerChannelDirectDownload => 'Direct download';

  @override
  String get testerAvailabilityChecking => 'Checking...';

  @override
  String get testerAvailabilityUnknown => 'Check downloads';

  @override
  String get testerAvailabilityAvailable => 'Available now';

  @override
  String get testerAvailabilityUnavailable => 'Not published';

  @override
  String get testerCheckDownloads => 'Check all downloads';

  @override
  String get testerReferralTitle => 'Invite one workflow peer';

  @override
  String get testerReferralBody =>
      'Know someone who regularly handles client files? Invite them to evaluate the founding beta with you. Sharing is optional and opens your device\'s share sheet.';

  @override
  String get testerReferralButton => 'Invite one person';

  @override
  String get testerReferralShareText =>
      'RonikCloud is looking for founding-beta testers who handle client files. It encrypts protected file content and names on the device, but it is early and has not been independently audited. Use non-critical copies and keep another backup. Want to test one workflow with me?';

  @override
  String get testerReferralShareFailure =>
      'The share sheet could not be opened. Your beta request is still saved.';
}
