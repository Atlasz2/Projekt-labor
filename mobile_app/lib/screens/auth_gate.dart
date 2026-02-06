import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'name_screen.dart';
import 'main_menu_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
            if (docSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
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
