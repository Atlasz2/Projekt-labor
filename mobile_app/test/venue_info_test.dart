import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/utils/venue_info.dart';

void main() {
  test('típuscímke: ismert kód magyarul, ismeretlen változatlanul', () {
    expect(venueTypeLabel('guesthouse', isRestaurant: false), 'Vendégház');
    expect(venueTypeLabel('icecream', isRestaurant: true), 'Fagylaltozó');
    expect(venueTypeLabel('jurta', isRestaurant: false), 'jurta');
  });

  test(
    'ár: szöveges ár változatlan, csak számhoz kerül Ft, üres/0 elrejtve',
    () {
      expect(priceLabel('18 000 Ft'), '18 000 Ft');
      expect(priceLabel('18000'), '18000 Ft');
      expect(priceLabel(0), '');
      expect(priceLabel(null), '');
    },
  );

  test('kapacitás: számhoz „fő”, mértékegységes szöveg változatlan', () {
    expect(capacityLabel('12'), '12 fő');
    expect(capacityLabel('12 fő'), '12 fő');
    expect(capacityLabel(''), '');
  });

  test('weboldal: séma nélkül https, nem http(s) és hibás cím elutasítva', () {
    expect(websiteUri('www.pelda.hu').toString(), 'https://www.pelda.hu');
    expect(websiteUri('http://pelda.hu/menu')!.scheme, 'http');
    expect(websiteUri('javascript:alert(1)'), isNull);
    expect(websiteUri('tel:123'), isNull);
    expect(websiteUri('nem link'), isNull);
    expect(websiteUri(''), isNull);
  });
}
