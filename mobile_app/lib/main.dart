import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';

import 'services/local_cache.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter('nagyvazsony_cache');
  await LocalCache.init();

  var firebaseReady = false;
  String? firebaseInitError;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    firebaseReady = true;
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    firebaseInitError = e.toString();
    debugPrint('Firebase init error: $e');
  }

  if (firebaseReady) {
    try {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      // Nem await-eljük: a performance-gyűjtés bekapcsolása ne késleltesse
      // az első képkockát (korábban ez nyújtotta a splash-időt).
      unawaited(
        FirebasePerformance.instance.setPerformanceCollectionEnabled(true),
      );
    } catch (e) {
      debugPrint('Optional Firebase service init error: $e');
    }
  }

  runApp(MyApp(firebaseReady: firebaseReady, firebaseInitError: firebaseInitError));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.firebaseReady, this.firebaseInitError});

  final bool firebaseReady;
  final String? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Nagyvazsony',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF1E293B),
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.92),
          elevation: 1,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      home: firebaseReady
          ? const AuthGate()
          : _FirebaseInitErrorScreen(errorText: firebaseInitError),
    );
  }
}

class _FirebaseInitErrorScreen extends StatelessWidget {
  const _FirebaseInitErrorScreen({this.errorText});

  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text(
                'Nem sikerült csatlakozni',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ellenőrizd az internetkapcsolatot, majd indítsd újra az alkalmazást.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 20),
                Text(
                  errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}




