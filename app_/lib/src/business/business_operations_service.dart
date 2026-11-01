import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

typedef BusinessOperationsCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> data,
    );

class BusinessOperationsException implements Exception {
  const BusinessOperationsException();
  String get message =>
      'This request could not be confirmed. Refresh status before retrying. Your encryption keys stay on your device.';
}

class BusinessOperationsService {
  BusinessOperationsService({required BusinessOperationsCallable callable})
    : _callable = callable;

  factory BusinessOperationsService.forApp(FirebaseApp app) {
    final functions = FirebaseFunctions.instanceFor(
      app: app,
      region: 'europe-west1',
    );
    return BusinessOperationsService(
      callable: (name, data) async {
        final response = await functions
            .httpsCallable(name)
            .call<Map<String, dynamic>>(data);
        return Map<String, dynamic>.from(response.data);
      },
    );
  }

  final BusinessOperationsCallable _callable;

  static String newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    try {
      return await _callable(name, data);
    } catch (_) {
      throw const BusinessOperationsException();
    }
  }
}
