// A profil képernyő tiszta (UI-mentes) számításai, hogy külön tesztelhetők
// legyenek. Az achievement-feltételek szövegét, a rang-medált és a következő
// pontcélt számolják.

int safeCount(dynamic value) {
  if (value is List) return value.length;
  if (value is num) return value.toInt();
  return 0;
}

int safeInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String rankMedal(int rank) {
  if (rank == 1) return '🥇';
  if (rank == 2) return '🥈';
  if (rank == 3) return '🥉';
  return '#$rank';
}

/// Egy achievement-feltétel ember által olvasható leírása (típus + érték).
String conditionText(String type, int value) {
  switch (type) {
    case 'station_count':
      return '$value állomás';
    case 'event_count':
      return '$value esemény';
    case 'qr_count':
      return '$value QR-kód';
    case 'points_threshold':
      return '$value pont';
    case 'trip_complete':
      return '$value teljesített túra';
    case 'top_n':
      return 'Top $value helyezés';
    case 'manual':
      return 'Manuális';
    default:
      return '';
  }
}

/// A jutalom-előrehaladás sávhoz: a legközelebbi, még el nem ért pontküszöb.
/// Ha már minden küszöböt elértünk, a legmagasabbat adja; ha nincs küszöb,
/// egy ésszerű alapértéket (140).
int nextPointTarget(
  int currentPoints,
  List<Map<String, dynamic>> achievementDefinitions,
) {
  final thresholds = achievementDefinitions
      .where((a) => (a['conditionType']?.toString() ?? '') == 'points_threshold')
      .map((a) => safeInt(a['conditionValue']))
      .where((t) => t > 0)
      .toList();

  final above = thresholds.where((t) => t > currentPoints).toList();
  if (above.isNotEmpty) {
    above.sort();
    return above.first;
  }
  if (thresholds.isNotEmpty) {
    thresholds.sort();
    return thresholds.last;
  }
  return 140;
}
