import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

typedef AccountClosureRequestCallable = Future<Object?> Function();

class AccountClosureRequestException implements Exception {
  const AccountClosureRequestException(this.message);

  final String message;

  @override
  String toString() => 'AccountClosureRequestException: $message';
}

class AccountClosureRequestReceipt {
  const AccountClosureRequestReceipt({
    required this.status,
    required this.alreadyRequested,
    this.receiptUrl,
  });

  final String status;
  final bool alreadyRequested;
  final Uri? receiptUrl;
}

class AccountClosureRequestService {
  AccountClosureRequestService({
    required FirebaseAuth auth,
    FirebaseFunctions? functions,
    AccountClosureRequestCallable? callable,
  }) : _auth = auth,
       _functions = functions,
       _callable = callable;

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  final AccountClosureRequestCallable? _callable;

  Future<AccountClosureRequestReceipt> submit() async {
    if (_auth.currentUser == null) {
      throw const AccountClosureRequestException(
        'Sign in again before requesting account closure.',
      );
    }

    try {
      final injected = _callable;
      final Object? raw;
      if (injected != null) {
        raw = await injected();
      } else {
        final functions =
            _functions ??
            FirebaseFunctions.instanceFor(
              app: _auth.app,
              region: 'europe-west1',
            );
        final result = await functions
            .httpsCallable('requestAccountDeletion')
            .call(<String, Object?>{'authorizationVersion': 2});
        raw = result.data;
      }

      if (raw is! Map) {
        throw const AccountClosureRequestException(
          'The closure request returned an invalid status. Try again or contact support.',
        );
      }
      final response = Map<String, Object?>.from(raw);
      final success = response['success'] == true;
      final status = response['status']?.toString().trim() ?? '';
      if (!success || status.isEmpty) {
        throw const AccountClosureRequestException(
          'The closure request was not recorded. Try again or contact support.',
        );
      }
      return AccountClosureRequestReceipt(
        status: status,
        alreadyRequested: response['alreadyRequested'] == true,
        receiptUrl: parseClosureReceiptUrl(response['receiptUrl']),
      );
    } on AccountClosureRequestException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated' ||
          error.code == 'failed-precondition') {
        throw const AccountClosureRequestException(
          'Confirm your identity again before requesting account closure.',
        );
      }
      throw const AccountClosureRequestException(
        'The closure request could not be recorded. Try again or contact support.',
      );
    } catch (_) {
      throw const AccountClosureRequestException(
        'The closure request could not be recorded. Try again or contact support.',
      );
    }
  }
}

Uri? parseClosureReceiptUrl(Object? value) {
  if (value is! String) return null;
  if (!RegExp(
    r'^https://(?:ronikcloud\.com|ronikdrive-staging\.web\.app|ronikcloud-test-7dcc2\.web\.app)/deletion-status#request=[a-f0-9]{64}&token=[A-Za-z0-9_-]{43}$',
  ).hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !{
        'ronikcloud.com',
        'ronikdrive-staging.web.app',
        'ronikcloud-test-7dcc2.web.app',
      }.contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.path != '/deletion-status' ||
      !RegExp(
        r'^request=[a-f0-9]{64}&token=[A-Za-z0-9_-]{43}$',
      ).hasMatch(uri.fragment)) {
    return null;
  }
  return uri;
}
