import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Több-települési (white-label) tartalom-szűrés.
///
/// A tartalom-dokumentumok `projectId` mezővel jelölik, melyik településhez
/// tartoznak. A mező HIÁNYA az alapértelmezett települést jelenti, így a még
/// nem migrált (régi) adat is helyesen látszik – ugyanaz a szabály, mint az
/// admin felületen.

/// Egy dokumentum-adat települése.
String projectIdOf(Map<String, dynamic>? data) {
  final value = data?['projectId'];
  if (value is String && value.trim().isNotEmpty) return value;
  return AppConfig.defaultProjectId;
}

/// Ehhez a kiadáshoz tartozik-e a dokumentum.
bool inActiveProject(Map<String, dynamic>? data) =>
    projectIdOf(data) == AppConfig.projectId;

/// Firestore dokumentumok szűrése az aktív településre.
List<QueryDocumentSnapshot<Map<String, dynamic>>> whereActiveProject(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs.where((d) => inActiveProject(d.data())).toList();
}

/// Hibatűrő szűrés: ha a szűrés MINDENT kidobna (pl. hibás vagy hiányzó
/// `projectId` az adatbázisban), inkább a teljes listát adjuk vissza.
///
/// Miért: egy üres térkép/lista sokkal rosszabb a felhasználónak, mint ha
/// átmenetileg többet lát a kelleténél. Egy-települési kiadásnál ez amúgy sem
/// jelent különbséget, mert csak egy település tartalma van az adatbázisban.
List<T> filterToActiveProject<T>(
  List<T> items,
  Map<String, dynamic>? Function(T) dataOf,
) {
  if (items.isEmpty) return items;
  final filtered = items.where((item) => inActiveProject(dataOf(item))).toList();
  if (filtered.isEmpty) {
    debugPrint(
      'Projekt-szűrés: minden elem kiesett (${AppConfig.projectId}) – '
      'a teljes lista marad, hogy ne legyen üres a képernyő.',
    );
    return items;
  }
  return filtered;
}
