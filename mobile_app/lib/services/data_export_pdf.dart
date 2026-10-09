import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Az exportált adatok (exportUserData válasza) emberi olvasásra szánt PDF-je.
///
/// Szándékosan nem a nyers adatszerkezet: technikai azonosítók (fiók-uid,
/// adatbázis-útvonalak) nem kerülnek bele, az állomások, rendezvények és
/// jutalmak a nevükkel szerepelnek. A [fonts] a magyar ékezetekhez kell
/// (a PDF alapbetűtípusa nem ismeri az ő/ű betűket).
class DataExportPdf {
  const DataExportPdf._();

  static const _olive = PdfColor.fromInt(0xFF5B6F4C);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _rowAlt = PdfColor.fromInt(0xFFF4F1EA);

  static Future<Uint8List> build(
    Map<String, dynamic> data, {
    required pw.Font regular,
    required pw.Font bold,
    Map<String, String> stationNames = const {},
    Map<String, String> eventNames = const {},
    Map<String, String> achievementNames = const {},
    DateTime? now,
  }) {
    final profile = _map(data['profile']);
    final progress = _map(data['progress']);
    final details = _map(data['progressDetails']);
    final leaderboard = _map(data['leaderboardEntry']);

    final stationsAt = _map(progress['completedStationsAt']);
    final stationDetails = {
      for (final d in _list(details['completed_stations']))
        _map(d)['id']?.toString() ?? '': _map(d),
    };
    final stationIds = <String>{
      ..._list(progress['completedStations']).map((e) => e.toString()),
      ...stationDetails.keys.where((k) => k.isNotEmpty),
    };
    final eventIds = <String>{
      ..._list(progress['completedEvents']).map((e) => e.toString()),
      ..._list(
        details['completed_events'],
      ).map((d) => _map(d)['id']?.toString() ?? '').where((k) => k.isNotEmpty),
    };
    final achievements = _list(details['unlocked_achievements']).map(_map);
    final bugReports = _list(data['bugReports']).map(_map).toList();

    final name =
        _text(profile['displayName']) ??
        _text(profile['name']) ??
        _text(progress['name']) ??
        '–';
    final email = _text(profile['email']) ?? _text(progress['email']);

    final doc = pw.Document(
      title: 'Nagyvázsony – Adataim',
      author: 'Nagyvázsonyi Turista App',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
        ),
        build: (context) => [
          pw.Text(
            'Nagyvázsony – Adataim',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: _olive,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Készült: ${formatDate(now ?? DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: _muted),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Ez a dokumentum tartalmazza mindazt, amit a Nagyvázsonyi Turista '
            'App rólad tárol. A dokumentum csak a te telefonodra került; '
            'senkinek nem küldtük el.',
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
          ),
          _heading('Profil'),
          _pairs([
            ('Név', name),
            ('E-mail-cím', email ?? 'nincs megadva'),
            ('Regisztráció', _dateText(profile['createdAt'])),
          ]),
          _heading('Összesítés'),
          _pairs([
            ('Pontszám', '${_int(progress['totalPoints'])} pont'),
            ('Teljesített állomások', '${stationIds.length} db'),
            ('Rendezvények', '${eventIds.length} db'),
            (
              'Teljesített túrák',
              '${_list(progress['completedTripIds']).length} db',
            ),
            (
              'Ranglista',
              leaderboard.isEmpty
                  ? 'nem szerepelsz rajta'
                  : '„${_text(leaderboard['displayName']) ?? name}” néven, '
                        '${_int(leaderboard['points'])} ponttal',
            ),
          ]),
          _heading('Teljesített állomások'),
          if (stationIds.isEmpty)
            _empty('Még nem teljesítettél állomást.')
          else
            _table(
              ['Állomás', 'Teljesítve'],
              [
                for (final id in stationIds)
                  [
                    stationNames[id] ?? 'Állomás (már nem elérhető)',
                    _dateText(
                      stationsAt[id] ?? stationDetails[id]?['completedAt'],
                    ),
                  ],
              ],
            ),
          _heading('Rendezvények'),
          if (eventIds.isEmpty)
            _empty('Még nem vettél részt rendezvényen.')
          else
            _table(
              ['Rendezvény'],
              [
                for (final id in eventIds)
                  [eventNames[id] ?? 'Rendezvény (már nem elérhető)'],
              ],
            ),
          _heading('Jutalmak'),
          if (achievements.isEmpty)
            _empty('Még nem oldottál fel jutalmat.')
          else
            _table(
              ['Jutalom', 'Feloldva', 'Beváltva'],
              [
                for (final a in achievements)
                  [
                    achievementNames[a['id']?.toString()] ??
                        _text(a['name']) ??
                        'Jutalom',
                    _dateText(a['unlockedAt']),
                    a['redeemedAt'] == null
                        ? 'még nem'
                        : _dateText(a['redeemedAt']),
                  ],
              ],
            ),
          _heading('Hibabejelentéseid'),
          if (bugReports.isEmpty)
            _empty('Nem küldtél hibabejelentést.')
          else
            _table(
              ['Beküldve', 'Leírás'],
              [
                for (final r in bugReports)
                  [
                    _dateText(
                      r['created_at'] ??
                          r['created_at_ms'] ??
                          r['created_at_text'],
                    ),
                    _text(r['description']) ?? '–',
                  ],
              ],
              widths: const {0: pw.FixedColumnWidth(110)},
            ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Az adataidat bármikor véglegesen törölheted az alkalmazásban: '
            'Profil › Adataim és adatvédelem › Fiók törlése.',
            style: const pw.TextStyle(fontSize: 9.5, color: _muted),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: _olive,
      ),
    ),
  );

  static pw.Widget _empty(String text) =>
      pw.Text(text, style: const pw.TextStyle(fontSize: 10.5, color: _muted));

  static pw.Widget _pairs(List<(String, String)> rows) => pw.Table(
    columnWidths: const {0: pw.FixedColumnWidth(150)},
    children: [
      for (final (label, value) in rows)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 10.5, color: _muted),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10.5)),
            ),
          ],
        ),
    ],
  );

  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    columnWidths: widths,
    headerStyle: pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: _olive),
    cellStyle: const pw.TextStyle(fontSize: 10),
    cellAlignment: pw.Alignment.centerLeft,
    headerAlignment: pw.Alignment.centerLeft,
    oddRowDecoration: const pw.BoxDecoration(color: _rowAlt),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    border: null,
  );

  /// Magyar dátumformátum: 2026. 10. 09. 15:40.
  static String formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = d.toLocal();
    return '${l.year}. ${two(l.month)}. ${two(l.day)}. '
        '${two(l.hour)}:${two(l.minute)}';
  }

  static String _dateText(Object? raw) {
    final d = parseDate(raw);
    return d == null ? '–' : formatDate(d);
  }

  /// A callable a Firestore-időbélyeget `{_seconds, _nanoseconds}` mapként
  /// adja; a régebbi mezők ezredmásodpercként vagy ISO-szövegként jönnek.
  static DateTime? parseDate(Object? raw) {
    if (raw is Map) {
      final s = raw['_seconds'] ?? raw['seconds'];
      if (s is num) {
        return DateTime.fromMillisecondsSinceEpoch((s * 1000).round());
      }
      return null;
    }
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static Map<String, dynamic> _map(Object? v) => v is Map
      ? v.map((k, val) => MapEntry(k.toString(), val))
      : <String, dynamic>{};

  static List<Object?> _list(Object? v) =>
      v is List ? v.cast<Object?>() : const [];

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
