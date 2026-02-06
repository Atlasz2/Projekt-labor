import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'name_screen.dart';
import 'main_menu_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<bool> _hasUserDoc(User user) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc.exists;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;

        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (user == null) {
          return const NameScreen();
        }

        if (user.isAnonymous) {
          return FutureBuilder<bool>(
            future: _hasUserDoc(user),
            builder: (context, docSnap) {
              if (docSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (docSnap.data == true) {
                return const MainMenuScreen();
              }
              return const NameScreen();
            },
          );
        }

        return const MainMenuScreen();
      },
    );
  }
}
