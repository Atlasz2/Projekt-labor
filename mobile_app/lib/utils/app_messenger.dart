import 'package:flutter/material.dart';

/// Alkalmazásszintű üzenetkezelő: a rajta keresztül mutatott üzenet a
/// képernyőváltást is túléli (például a fiók törlése utáni kijelentkezéskor,
/// amikor a profil képernyő eltűnik).
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppMessage(
  String text, {
  Duration duration = const Duration(seconds: 4),
}) {
  appMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: duration));
}
