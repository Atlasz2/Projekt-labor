import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Belépés másik eszközön: a felhasználó email + név párral visszaállítja a
/// korábbi fiókját (és a hozzá tartozó haladást). Sikeres belépés után az
/// AuthGate automatikusan a főképernyőre visz, ezért csak visszalépünk.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || name.isEmpty) {
      _showMessage('Add meg az emailt és a nevet is.');
      return;
    }
    if (!_isValidEmail(email)) {
      _showMessage('Érvénytelen email cím.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithEmailName(email: email, name: name);
      if (!mounted) return;
      // Az AuthGate az új auth-állapotra a főképernyőre vált – csak visszalépünk.
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      String message;
      if (code.contains('wrong-password') ||
          code.contains('user-not-found') ||
          code.contains('invalid-credential') ||
          code.contains('invalid-login')) {
        message =
            'Nem található fiók ezzel az email + név párral. Ellenőrizd, hogy pontosan úgy írod-e a nevet, ahogy regisztráltál.';
      } else if (code.contains('too-many-requests')) {
        message = 'Túl sok próbálkozás. Várj egy kicsit, majd próbáld újra.';
      } else if (code.contains('network')) {
        message = 'Nincs internetkapcsolat. Ellenőrizd a hálózatot.';
      } else {
        message = 'Belépési hiba: ${e.message ?? e.code}';
      }
      _showMessage(message);
    } catch (e) {
      _showMessage('Váratlan hiba: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Belépés'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.devices, size: 64, color: Color(0xFF667EEA)),
            const SizedBox(height: 20),
            const Text(
              'Van már fiókod?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ha korábban megadtál egy email címet, itt visszaléphetsz a '
              'haladásodba egy másik eszközön is.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 36),
            TextField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'pl. kiss.janos@example.com',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Név (ahogy regisztráltál)',
                hintText: 'pl. Kiss János',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
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
                      'Belépés',
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
