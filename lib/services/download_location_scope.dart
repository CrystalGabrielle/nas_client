import 'package:flutter/widgets.dart';

import 'download_location.dart';

/// Makes the app-wide [DownloadLocationStore] available to every screen.
class DownloadLocationScope extends InheritedNotifier<DownloadLocationStore> {
  const DownloadLocationScope({
    required DownloadLocationStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static DownloadLocationStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DownloadLocationScope>();
    assert(scope != null, 'No DownloadLocationScope found in the widget tree');
    return scope!.notifier!;
  }
}
