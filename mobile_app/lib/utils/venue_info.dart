/// Szállások és vendéglátóhelyek megjelenítési segédfüggvényei. A típusokat
/// az admin felület kódként tárolja (pl. `guesthouse`), a felhasználó magyar
/// címkét lát.
library;

const Map<String, String> _accommodationTypes = {
  'hotel': 'Hotel',
  'guesthouse': 'Vendégház',
  'apartment': 'Apartman',
  'campsite': 'Kemping',
};

const Map<String, String> _restaurantTypes = {
  'hungarian': 'Magyar konyha',
  'fish': 'Halételek',
  'cafe': 'Kávézó',
  'pizzeria': 'Pizzéria',
  'icecream': 'Fagylaltozó',
  'bar': 'Bár',
};

/// A típuskód magyar címkéje; ismeretlen kódnál maga a kód.
String venueTypeLabel(String type, {required bool isRestaurant}) {
  final key = type.trim();
  final labels = isRestaurant ? _restaurantTypes : _accommodationTypes;
  return labels[key] ?? key;
}

/// Ár megjelenítése: az admin szövegként tárolja („18 000 Ft”); ha csak szám,
/// „Ft”-ot fűzünk hozzá. Üres vagy nulla értéknél üres sztring.
String priceLabel(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty || value == '0') return '';
  return RegExp(r'^\d[\d\s.]*$').hasMatch(value) ? '$value Ft' : value;
}

/// Kapacitás megjelenítése („12 fő”); ha már tartalmaz mértékegységet, változatlan.
String capacityLabel(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty || value == '0') return '';
  return RegExp(r'^\d+$').hasMatch(value) ? '$value fő' : value;
}

/// A weboldal címe megnyitható `Uri`-ként, vagy null, ha nem érvényes http(s)
/// link. A séma nélküli alakot (`www.pelda.hu`) https-sel egészíti ki.
Uri? websiteUri(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return null;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value);
  final uri = Uri.tryParse(hasScheme ? value : 'https://$value');
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.host.contains('.') ? uri : null;
}
