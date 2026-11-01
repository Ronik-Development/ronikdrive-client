import 'dart:convert';

import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'username-only account can start checkout without a synthetic email',
    () async {
      Map<String, dynamic>? requestBody;
      final api = HttpStripeCheckoutApi(
        apiBaseUrl: Uri.parse('https://api.example.test/'),
        projectId: 'cloudapp-7dcc2',
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'url': 'https://checkout.stripe.test/session'}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      final coordinator = SubscriptionCoordinator(
        firestore: FakeFirebaseFirestore(),
        checkoutApi: api,
      );

      final launch = await coordinator.startCheckoutSession(
        uid: 'username-only-user',
        email: '',
        planTier: 'ultra',
        interval: 'monthly',
        idToken: 'verified-token',
      );

      expect(
        launch.checkoutUri,
        Uri.parse('https://checkout.stripe.test/session'),
      );
      expect(requestBody?['email'], '');
      expect(requestBody?['uid'], 'username-only-user');
      expect(requestBody?['tier'], 'ultra');
    },
  );
}
