import 'package:cloud_functions/cloud_functions.dart';

abstract interface class TransferVerificationPause {}

bool requiresTransferVerification(Object error) =>
    error is TransferVerificationPause ||
    (error is FirebaseFunctionsException &&
        error.details is Map &&
        (error.details as Map)['reason'] ==
            'business_recipient_verification_required');

const transferVerificationMessage =
    'Upgrade RonikCloud and open Company key verification before resuming this transfer.';
