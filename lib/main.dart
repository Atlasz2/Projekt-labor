import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config/firebase_config.dart';
import 'themes/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/station_detail_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'models/trip.dart';
import 'models/station.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nagyvazsony Tours',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/map': (context) {
          final trip = ModalRoute.of(context)!.settings.arguments as Trip;
          return MapScreen(trip: trip);
        },
        '/station_detail': (context) {
          final station =
              ModalRoute.of(context)!.settings.arguments as Station;
          return StationDetailScreen(station: station);
        },
        '/qr_scanner': (context) => const QRScannerScreen(),
      },
    );
  }
}
