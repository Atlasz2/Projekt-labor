import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'name_screen.dart';
import 'main_menu_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _appInitialized = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Only show splash on first auth check (app startup)
        if (snapshot.connectionState == ConnectionState.waiting &&
            !_appInitialized) {
          return const _LoadingSplashScreen();
        }

        if (snapshot.connectionState == ConnectionState.done) {
          _appInitialized = true;
        }

        // No user logged in
        if (!snapshot.hasData || snapshot.data == null) {
          return const NameScreen();
        }

        final user = snapshot.data!;

        // User is logged in, check if they have a Firestore document
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, docSnapshot) {
            // Don't show splash for Firestore checks after initialization
            if (docSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            // Check if user document exists
            if (!docSnapshot.hasData || !docSnapshot.data!.exists) {
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
          Image.asset(
            'assets/loading_screen.jpg',
            fit: BoxFit.cover,
          ),
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
