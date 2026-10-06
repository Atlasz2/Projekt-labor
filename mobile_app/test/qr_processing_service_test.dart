import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/qr_processing_service.dart';

/// A QrProcessingService a jóváírást a redeemQr Cloud Functionre bízza; a
/// tesztek a szerverhívást a `serverRedeemOverride` hookkal helyettesítik, és
/// a válasz értelmezését, a hibaosztályozást és a kliensoldali helyszín-
/// előszűrést ellenőrzik.
void main() {
  tearDown(() => QrProcessingService.serverRedeemOverride = null);

  void serverReturns(Map<String, dynamic> payload) {
    QrProcessingService.serverRedeemOverride = (_, _) async => payload;
  }

  group('szerver-válasz értelmezése', () {
    test('állomás-jóváírásból épül az eredmény', () async {
      serverReturns({
        'found': true,
        'kind': 'station',
        'targetId': 'st1',
        'target': {'name': 'Kinizsi vár', 'points': 25},
        'alreadyDone': false,
        'newAchievements': [
          {'id': 'first', 'name': 'Első felfedezés'},
        ],
        'updatedPoints': 25,
        'completedStationsCount': 1,
        'completedEventsCount': 0,
      });

      final result = await QrProcessingService.processByCode(code: 'VAR-001');

      expect(result.kind, QrTargetKind.station);
      expect(result.alreadyDone, isFalse);
      expect(result.updatedPoints, 25);
      expect(result.completedStationsCount, 1);
      expect(result.target['name'], 'Kinizsi vár');
      expect(result.newAchievements.single['name'], 'Első felfedezés');
    });

    test(
      'esemény és ismételt beolvasás (alreadyDone) helyesen jelenik meg',
      () async {
        serverReturns({
          'found': true,
          'kind': 'event',
          'target': {'name': 'Várjátékok'},
          'alreadyDone': true,
          'newAchievements': <Object>[],
          'updatedPoints': 40,
          'completedStationsCount': 2,
          'completedEventsCount': 1,
        });

        final result = await QrProcessingService.processByCode(code: 'EV-1');

        expect(result.kind, QrTargetKind.event);
        expect(result.alreadyDone, isTrue);
        expect(result.newAchievements, isEmpty);
        expect(result.completedEventsCount, 1);
      },
    );

    test(
      'a beágyazott Map<Object?, Object?> válasz String-kulcsúvá alakul',
      () async {
        QrProcessingService.serverRedeemOverride = (_, _) async =>
            QrProcessingService.stringKeyedMap(<Object?, Object?>{
              'found': true,
              'kind': 'station',
              'target': <Object?, Object?>{
                'name': 'Malom',
                'location': <Object?, Object?>{'latitude': 47.0},
              },
              'newAchievements': [
                <Object?, Object?>{'id': 'a1'},
              ],
            });

        final result = await QrProcessingService.processByCode(code: 'MALOM');

        expect(result.target['location'], isA<Map<String, dynamic>>());
        expect(result.newAchievements.single['id'], 'a1');
        expect(result.updatedPoints, 0);
      },
    );

    test('a kód és a pozíció változatlanul jut el a szerverhez', () async {
      String? sentCode;
      ScanLocation? sentLocation;
      QrProcessingService.serverRedeemOverride = (code, location) async {
        sentCode = code;
        sentLocation = location;
        return {
          'found': true,
          'kind': 'station',
          'target': <String, dynamic>{},
        };
      };

      await QrProcessingService.processByCode(
        code: 'VAR-001',
        location: (lat: 47.06, lng: 17.71),
      );

      expect(sentCode, 'VAR-001');
      expect(sentLocation, (lat: 47.06, lng: 17.71));
    });
  });

  group('hibaosztályozás', () {
    test('found:false → QrCodeNotFoundException (végleges)', () async {
      serverReturns({'found': false});
      await expectLater(
        QrProcessingService.processByCode(code: 'NEMLETEZIK'),
        throwsA(isA<QrCodeNotFoundException>()),
      );
    });

    test('wrong_project → QrWrongProjectException (végleges)', () async {
      serverReturns({'found': true, 'rejected': 'wrong_project'});
      await expectLater(
        QrProcessingService.processByCode(code: 'MASIK-FALU'),
        throwsA(isA<QrWrongProjectException>()),
      );
    });

    test('out_of_range → QrOutOfRangeException a mért értékekkel', () async {
      serverReturns({
        'found': true,
        'rejected': 'out_of_range',
        'distance': 812.4,
        'threshold': 150,
      });
      await expectLater(
        QrProcessingService.processByCode(code: 'VAR-001'),
        throwsA(
          isA<QrOutOfRangeException>()
              .having((e) => e.distance, 'distance', 812)
              .having((e) => e.threshold, 'threshold', 150),
        ),
      );
    });

    test(
      'out_of_range küszöb nélkül az alapértelmezett 150 m-t mutatja',
      () async {
        serverReturns({
          'found': true,
          'rejected': 'out_of_range',
          'distance': 300,
        });
        await expectLater(
          QrProcessingService.processByCode(code: 'VAR-001'),
          throwsA(
            isA<QrOutOfRangeException>().having(
              (e) => e.threshold,
              'threshold',
              150,
            ),
          ),
        );
      },
    );

    test('nem elérhető szolgáltatás → QrServerUnavailableException', () async {
      QrProcessingService.serverRedeemOverride = (_, _) async =>
          throw const QrServerUnavailableException();
      await expectLater(
        QrProcessingService.processByCode(code: 'VAR-001'),
        throwsA(isA<QrServerUnavailableException>()),
      );
    });

    test(
      'átmeneti szerverhiba továbbdobódik (az offline sor újrapróbálja)',
      () async {
        QrProcessingService.serverRedeemOverride = (_, _) async =>
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'offline',
            );
        await expectLater(
          QrProcessingService.processByCode(code: 'VAR-001'),
          throwsA(isA<FirebaseFunctionsException>()),
        );
      },
    );

    test('a kivételek érthető üzenetet adnak a felületnek', () {
      expect(const QrCodeNotFoundException('X-1').toString(), contains('X-1'));
      expect(
        const QrOutOfRangeException(distance: 300, threshold: 150).toString(),
        contains('300 m'),
      );
      expect(const QrServerUnavailableException().toString(), isNotEmpty);
    });
  });

  group('kliensoldali helyszín-előszűrés (locationRejection)', () {
    const station = {'latitude': 47.06, 'longitude': 17.715};

    test('távoli pozícióra kiutasítás a távolsággal és a küszöbbel', () {
      final r = QrProcessingService.locationRejection(station, (
        lat: 47.2,
        lng: 17.9,
      ));
      expect(r, isNotNull);
      expect(r!.threshold, 150);
      expect(r.distance, greaterThan(150));
    });

    test('a helyszínen lévő pozíció rendben van', () {
      expect(
        QrProcessingService.locationRejection(station, (
          lat: 47.0601,
          lng: 17.7151,
        )),
        isNull,
      );
    });

    test('pozíció nélkül nincs mit ellenőrizni (graceful)', () {
      expect(QrProcessingService.locationRejection(station, null), isNull);
    });

    test('koordináta nélküli vagy (0,0) célnál a pozíció irreleváns', () {
      const far = (lat: 10.0, lng: 10.0);
      expect(QrProcessingService.locationRejection({'name': 'x'}, far), isNull);
      expect(
        QrProcessingService.locationRejection({
          'latitude': 0,
          'longitude': 0,
        }, far),
        isNull,
      );
    });

    test('a beágyazott location mezőt is olvassa', () {
      final r = QrProcessingService.locationRejection(
        {
          'location': {'latitude': 47.06, 'longitude': 17.715},
        },
        (lat: 47.2, lng: 17.9),
      );
      expect(r, isNotNull);
    });

    test('az állomás radius mezője kitágítja a megengedett kört', () {
      const pos = (lat: 47.0645, lng: 17.715); // kb. 500 m-re északra
      expect(QrProcessingService.locationRejection(station, pos), isNotNull);
      expect(
        QrProcessingService.locationRejection({
          ...station,
          'radius': 1000,
        }, pos),
        isNull,
      );
    });
  });
}
