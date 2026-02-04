import 'package:geolocator/geolocator.dart';

class GeolocationService {
  static final GeolocationService _instance =
      GeolocationService._internal();

  factory GeolocationService() {
    return _instance;
  }

  GeolocationService._internal();

  /// Ellenőrzi, hogy a helymeghatározás engedélyezett-e
  Future<bool> checkLocationPermission() async {
    final status = await Geolocator.checkPermission();
    
    if (status == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      return result == LocationPermission.whileInUse ||
          result == LocationPermission.always;
    }
    
    if (status == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }

  /// Aktuális pozíció lekérése
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        print('Helymeghatározási engedély megtagadva');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return position;
    } catch (e) {
      print('Error getting current position: \');
      return null;
    }
  }

  /// Valós idejű pozíciókövetés
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10, // Méterben
  }) {
    return Geolocator.getPositionStream(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  /// Távolság számítása két koordináta között
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Ellenőrzi, hogy a felhasználó közel van-e egy ponthoz
  bool isWithinRadius(
    double userLat,
    double userLon,
    double pointLat,
    double pointLon,
    int radiusMeters,
  ) {
    final distance = calculateDistance(userLat, userLon, pointLat, pointLon);
    return distance <= radiusMeters;
  }

  /// Helymeghatározás bekapcsolása
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Közel lévő állomások szűrése
  List<Map<String, dynamic>> filterNearbyStations(
    double userLat,
    double userLon,
    List<Map<String, dynamic>> stations,
    int radiusMeters,
  ) {
    return stations.where((station) {
      final distance = calculateDistance(
        userLat,
        userLon,
        station['latitude'] as double,
        station['longitude'] as double,
      );
      return distance <= radiusMeters;
    }).toList();
  }
}
