import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String ronikCloudHomeTitle =
    'RonikCloud | Private Cloud Storage and Encrypted Sharing';

extension AppPageTitle on Widget {
  Widget withAppPageTitle(String title) {
    return _CurrentRouteTitle(title: title, child: this);
  }
}

class _CurrentRouteTitle extends StatelessWidget {
  const _CurrentRouteTitle({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Navigator retains covered routes. Their asynchronous rebuilds must not
    // replace the visible page's title. Keep the child at the same tree position
    // so covering a page also preserves its forms and scroll state.
    if (ModalRoute.isCurrentOf(context) != false) {
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(
          label: title,
          primaryColor: const Color(0xFF1B48A5).toARGB32(),
        ),
      );
    }
    return child;
  }
}
