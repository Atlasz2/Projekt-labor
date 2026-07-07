import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'name_screen.dart';
import '../services/bootstrap_service.dart';
import '../services/pending_qr_sync_service.dart';
import '../theme/app_colors.dart';
import 'main_menu_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _initialAuthResolved = FirebaseAuth.instance.currentUser != null;
  String? _lastBootstrappedUid;
  bool _servicesStoppedForSignedOut = false;
  Stream<DocumentSnapshot>? _userDocStream;
  String? _userDocStreamUid;

  // A live snapshot stream (not a one-shot get) so the gate reacts the moment
  // the user document is created during registration — no app restart needed.
  Stream<DocumentSnapshot> _userDocByUid(String uid) {
    if (_userDocStream != null && _userDocStreamUid == uid) {
      return _userDocStream!;
    }
    _userDocStreamUid = uid;
    _userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();
    return _userDocStream!;
  }

  void _startBackgroundServices(String uid) {
    if (_lastBootstrappedUid == uid) return;
    _lastBootstrappedUid = uid;
    _servicesStoppedForSignedOut = false;
    unawaited(BootstrapService.run());
    unawaited(PendingQrSyncService.start());
  }

  Future<void> _stopBackgroundServices() async {
    if (_servicesStoppedForSignedOut) return;
    _servicesStoppedForSignedOut = true;
    _lastBootstrappedUid = null;
    _userDocStream = null;
    _userDocStreamUid = null;
    await PendingQrSyncService.stop();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!_initialAuthResolved &&
            snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const _LoadingSplashScreen();
        }

        if (!_initialAuthResolved &&
            snapshot.connectionState != ConnectionState.waiting) {
          _initialAuthResolved = true;
        }

        if (!snapshot.hasData || snapshot.data == null) {
          unawaited(_stopBackgroundServices());
          return const NameScreen();
        }

        _initialAuthResolved = true;
        final user = snapshot.data!;
        _startBackgroundServices(user.uid);

        return StreamBuilder<DocumentSnapshot>(
          stream: _userDocByUid(user.uid),
          builder: (context, docSnapshot) {
            if (!docSnapshot.hasData) {
              return const _LoadingSplashScreen();
            }

            if (!docSnapshot.data!.exists) {
              return const NameScreen();
            }

            return const MainMenuScreen();
          },
        );
      },
    );
  }
}

class _LoadingSplashScreen extends StatelessWidget {
  const _LoadingSplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 120, height: 120),
            const SizedBox(height: 28),
            const Text(
              'Nagyvázsony',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryText,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Túra alkalmazás',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryText.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.seed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
