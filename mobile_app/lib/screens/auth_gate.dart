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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Only allow the splash on cold start before auth is resolved once.
        if (!_initialAuthResolved &&
            snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const _LoadingSplashScreen();
        }

        if (!_initialAuthResolved &&
            snapshot.connectionState != ConnectionState.waiting) {
          _initialAuthResolved = true;
        }

        // No user logged in
        if (!snapshot.hasData || snapshot.data == null) {
          PendingQrSyncService.stop().ignore();
          return const NameScreen();
        }

        _initialAuthResolved = true;
        final user = snapshot.data!;
        BootstrapService.run().ignore(); // adatok frissitese hatterben
        PendingQrSyncService.start().ignore();

        // User is logged in - show MainMenuScreen immediately without waiting for Firestore
        // Firestore updates will happen in background without blocking UI
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, docSnapshot) {
            // Show MainMenuScreen immediately even if Firestore data is loading
            // This prevents the loading spinner from blocking the UI
            if (!docSnapshot.hasData) {
              // Still loading, but show menu anyway
              return const MainMenuScreen();
            }

            // Check if user document exists
            if (!docSnapshot.data!.exists) {
              return const NameScreen();
            }

            // User has profile, show main menu
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
