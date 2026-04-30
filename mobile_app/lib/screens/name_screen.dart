import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  String _normalizeDisplayName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final displayName = _displayNameController.text.trim();

    if (displayName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('A név megadása kötelező!')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final normalizedName = _normalizeDisplayName(displayName);
      final usernameRef = firestore.collection('usernames').doc(normalizedName);
      final currentUser = FirebaseAuth.instance.currentUser;
      final user = currentUser ?? (await FirebaseAuth.instance.signInAnonymously()).user;
      if (user == null) {
        throw Exception('Nem sikerült bejelentkezni.');
      }
      final email = _emailController.text.trim();

      await firestore.runTransaction((transaction) async {
        final reservedName = await transaction.get(usernameRef);
        if (reservedName.exists) {
          final reservedUid = reservedName.data()?['uid']?.toString();
          if (reservedUid != user.uid) {
            throw Exception('Ez a név már foglalt. Válassz másikat.');
          }
        }

        transaction.set(usernameRef, {
          'uid': user.uid,
          'displayName': displayName,
          'normalized': normalizedName,
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(firestore.collection('users').doc(user.uid), {
          'displayName': displayName,
          'name': displayName,
          'email': email.isEmpty ? null : email,
          'createdAt': FieldValue.serverTimestamp(),
          'points': 0,
          'completedTrips': 0,
          'visitedStations': <String>[],
          'achievements': <String>[],
        }, SetOptions(merge: true));

        transaction.set(
          firestore.collection('user_progress').doc(user.uid),
          {
            'name': displayName,
            'email': email,
            'completedStations': <String>[],
            'completedEvents': <String>[],
            'completedTripIds': <String>[],
            'totalPoints': 0,
            'currentTrip': 'Nincs túra',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          firestore.collection('public_leaderboard').doc(user.uid),
          {
            'displayName': displayName,
            'points': 0,
            'completedStationsCount': 0,
            'completedEventsCount': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil sikeresen létrehozva!')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hiba: ${e.message}')));
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      var message = 'Váratlan hiba történt.';
      if (code.contains('permission-denied') || code.contains('insufficient')) {
        message = 'Nincs jogosultság a profil létrehozásához. Ellenőrizd a hálózatot és próbáld újra.';
      } else if (code.contains('unavailable') || code.contains('network')) {
        message = 'Nincs kapcsolat a Firebase szolgáltatással. Ellenőrizd az internetet.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Váratlan hiba: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nagyvázsony'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            Icon(Icons.location_on, size: 64, color: const Color(0xFF667EEA)),
            const SizedBox(height: 24),
            const Text(
              'Üdvözölünk a Nagyvázsony Túra Alkalmazásban!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kérjük, add meg a nevedet a folytatáshoz.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 48),
            TextField(
              controller: _displayNameController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Teljes név *',
                hintText: 'pl. Kiss János',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email (opcionális)',
                hintText: 'pl. kiss.janos@example.com',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleContinue,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Folytatás',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}






