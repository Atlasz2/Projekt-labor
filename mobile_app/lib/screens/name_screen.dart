import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';
import 'privacy_screen.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
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
    _emailFocus.dispose();
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

    // E-mail nélkül is lehet regisztrálni, de érdemes tudni, mivel jár.
    if (email.isEmpty) {
      final proceed = await _confirmWithoutEmail();
      if (!mounted) return;
      if (proceed != true) {
        _emailFocus.requestFocus();
        return;
      }
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

  /// Tájékoztatás az e-mail nélküli regisztrációról. Igaz: folytatás e-mail
  /// nélkül; hamis vagy null: a felhasználó mégis megadja.
  Future<bool?> _confirmWithoutEmail() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: const Text('Folytatod e-mail nélkül?'),
        content: const Text(
          'Semmi gond, e-mail nélkül is mindenhez hozzáférsz.\n\n'
          'Egyet érdemes tudni: e-mail-cím nélkül a pontjaidat és a '
          'jutalmaidat csak ezen a telefonon őrizzük. Ha telefont cserélsz, '
          'vagy újratelepíted az alkalmazást, nem tudjuk őket visszaállítani.\n\n'
          'E-mail-címet később is megadhatsz a Profil oldalon.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('E-mail megadása'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Folytatás e-mail nélkül'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A háttér a Scaffoldon KÍVÜL van: a billentyűzet megjelenésekor csak az
    // űrlap tér ki (a Scaffold átméreteződik), a háttérkép nem rajzolódik és
    // méreteződik újra minden animációs képkockán – ettől akadt a gépelés.
    return Stack(
      fit: StackFit.expand,
      children: [
        const _NameBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // A fejléc felül, az űrlap alul: a vár a kettő között látszik.
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, viewport) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 460,
                          minHeight: viewport.maxHeight - 44,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Image.asset(
                                  'assets/logo_splash.png',
                                  height: 92,
                                  cacheHeight: 276,
                                  semanticLabel: 'Nagyvázsony címere',
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Fedezd fel Nagyvázsonyt!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Járd be a túrákat, olvasd be az állomások QR-kódjait, '
                                  'és gyűjts pontokat, jutalmakat.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: Color(0xF2FFFFFF),
                                    shadows: [
                                      Shadow(
                                        color: Colors.black45,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 120),
                            Card(
                              color: Colors.white.withValues(alpha: 0.95),
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  22,
                                  20,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Hogyan szólíthatunk?',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Ez a név jelenik meg a ranglistán. Később a profilban módosíthatod.',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: _displayNameController,
                                      enabled: !_isLoading,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      textInputAction: TextInputAction.next,
                                      maxLength: 40,
                                      decoration: InputDecoration(
                                        labelText: 'Név *',
                                        hintText: 'pl. Kiss János',
                                        prefixIcon: const Icon(
                                          Icons.person_outline,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _emailController,
                                      focusNode: _emailFocus,
                                      enabled: !_isLoading,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) {
                                        if (!_isLoading) _handleContinue();
                                      },
                                      decoration: InputDecoration(
                                        labelText: 'E-mail (opcionális)',
                                        hintText: 'pl. kiss.janos@example.com',
                                        helperText:
                                            'Ezzel egy másik telefonon is folytathatod.',
                                        prefixIcon: const Icon(
                                          Icons.email_outlined,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _handleContinue,
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              'Folytatás',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const PrivacyScreen(),
                                            ),
                                          ),
                                      child: const Text(
                                        'A folytatással elfogadod az adatkezelési '
                                        'tájékoztatót (megnyitás)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const LoginScreen(),
                                              ),
                                            ),
                                      icon: const Icon(Icons.devices, size: 18),
                                      label: const Text(
                                        'Van már fiókom (másik eszközön)',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A regisztrációs képernyő háttere: a Kinizsi-vár légifotója a képernyő
/// felső részén (így a kép a kijelzőn legfeljebb kb. 1,1-szeresére nagyítódik,
/// nem pixelesedik), alatta sötétzöld átmenet, amelyen az űrlap ül.
class _NameBackground extends StatelessWidget {
  const _NameBackground();

  static const _base = Color(0xFF141F10);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: _base,
        child: LayoutBuilder(
          builder: (context, box) {
            final imageHeight = box.maxHeight * 0.5;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: imageHeight,
                  child: Image.asset(
                    'assets/name_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x8C000000),
                        Color(0x00000000),
                        Color(0x00141F10),
                        _base,
                        _base,
                      ],
                      stops: [0, 0.22, 0.3, 0.5, 1],
                    ),
                  ),
                ),
              ],
            );
          },
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
