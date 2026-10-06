import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

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

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final displayName = _displayNameController.text.trim();
    final email = _emailController.text.trim();

    if (displayName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('A név megadása kötelező!')));
      return;
    }

    if (email.isNotEmpty && !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Érvénytelen email cím. Hagyd üresen, vagy adj meg helyeset.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final normalizedName = _normalizeDisplayName(displayName);
      final usernameRef = firestore.collection('usernames').doc(normalizedName);
      final currentUser = FirebaseAuth.instance.currentUser;
      final user =
          currentUser ?? (await FirebaseAuth.instance.signInAnonymously()).user;
      if (user == null) {
        throw Exception('Nem sikerült bejelentkezni.');
      }

      final progressRef = firestore.collection('user_progress').doc(user.uid);
      await firestore.runTransaction((transaction) async {
        final reservedName = await transaction.get(usernameRef);
        final existingProgress = await transaction.get(progressRef);
        if (reservedName.exists) {
          final reservedUid = reservedName.data()?['uid']?.toString();
          if (reservedUid != user.uid) {
            throw const _NameTakenException();
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
        }, SetOptions(merge: true));

        // A haladás-dokumentumot csak nullázva, és csak ha még nincs, hozza
        // létre a kliens – a pontokat ezután kizárólag a szerver írja.
        if (!existingProgress.exists) {
          transaction.set(progressRef, {
            'name': displayName,
            'email': email,
            'completedStations': <String>[],
            'completedEvents': <String>[],
            'completedTripIds': <String>[],
            'totalPoints': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      // Ha megadott emailt (és még nincs email-fiókkal összekötve), a
      // fiókot email+jelszó hitelesítővel is összekötjük, hogy másik eszközön
      // email+névvel visszaállítható legyen. Best-effort: ha az email már
      // foglalt, a profil név alapján akkor is elkészült.
      var linkedForMultiDevice = false;
      if (email.isNotEmpty && user.email == null) {
        try {
          await AuthService.linkEmailPassword(email: email, name: displayName);
          linkedForMultiDevice = true;
        } on FirebaseAuthException catch (e) {
          final code = e.code.toLowerCase();
          if (mounted &&
              (code.contains('email-already-in-use') ||
                  code.contains('credential-already-in-use'))) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ehhez az emailhez már tartozik fiók. A profilod elkészült; '
                  'ha a korábbi haladásod kell, lépj be a „Van már fiókom” '
                  'gombbal.',
                ),
                duration: Duration(seconds: 5),
              ),
            );
          }
          // Egyéb hibánál a profil név alapján így is működik (nem blokkoló).
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              linkedForMultiDevice
                  ? 'Profil létrehozva! Másik eszközön email + névvel léphetsz be.'
                  : 'Profil sikeresen létrehozva!',
            ),
          ),
        );
      }
    } on _NameTakenException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ez a név már foglalt. Válassz másikat.'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Regisztráció – hitelesítési hiba: ${e.code}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A bejelentkezés nem sikerült. Ellenőrizd az internetkapcsolatot, és próbáld újra.',
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      var message = 'Váratlan hiba történt.';
      if (code.contains('permission-denied') || code.contains('insufficient')) {
        message =
            'Nincs jogosultság a profil létrehozásához. Ellenőrizd a hálózatot és próbáld újra.';
      } else if (code.contains('unavailable') || code.contains('network')) {
        message =
            'Nincs kapcsolat a Firebase szolgáltatással. Ellenőrizd az internetet.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint('Regisztráció sikertelen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Váratlan hiba történt. Próbáld újra egy kicsit később.',
            ),
          ),
        );
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
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
              icon: const Icon(Icons.devices, size: 18),
              label: const Text('Van már fiókom (másik eszközön)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A választott név már egy másik fiókhoz tartozik (a regisztrációs
/// tranzakció dobja, a felület barátságos üzenetet mutat).
class _NameTakenException implements Exception {
  const _NameTakenException();
}
