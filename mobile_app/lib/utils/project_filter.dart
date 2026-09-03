import 'package:cloud_firestore/cloud_firestore.dart';

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
