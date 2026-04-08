import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'name_screen.dart';
import '../services/bootstrap_service.dart';
import '../services/pending_qr_sync_service.dart';
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
  Future<DocumentSnapshot>? _userDocFuture;
  String? _userDocFutureUid;

  Future<DocumentSnapshot> _userDocByUid(String uid) {
    if (_userDocFuture != null && _userDocFutureUid == uid) {
      return _userDocFuture!;
    }
    _userDocFutureUid = uid;
    _userDocFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return _userDocFuture!;
  }

  void _startBackgroundServices(String uid) {
    if (_lastBootstrappedUid == uid) return;
    _lastBootstrappedUid = uid;
    _servicesStoppedForSignedOut = false;
    BootstrapService.run().ignore();
    PendingQrSyncService.start().ignore();
  }

  Future<void> _stopBackgroundServices() async {
    if (_servicesStoppedForSignedOut) return;
    _servicesStoppedForSignedOut = true;
    _lastBootstrappedUid = null;
    _userDocFuture = null;
    _userDocFutureUid = null;
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
          _stopBackgroundServices().ignore();
          return const NameScreen();
        }

        _initialAuthResolved = true;
        final user = snapshot.data!;
        _startBackgroundServices(user.uid);

        return FutureBuilder<DocumentSnapshot>(
          future: _userDocByUid(user.uid),
          builder: (context, docSnapshot) {
            if (!docSnapshot.hasData) {
              return const MainMenuScreen();
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/loading_screen.jpg', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.20)),
          const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
