import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

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
    final theme = Theme.of(context);
    // Tudatosan más hangulat, mint a regisztráció sötét, fotós képernyője:
    // világos pergamen alap, hajlított olajzöld fejléc a címerrel.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _LoginHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: Colors.white,
                        elevation: 3,
                        shadowColor: const Color(0x33000000),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Lépj be a fiókodba',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'A pontjaid, jutalmaid és a ranglista-helyezésed '
                                'ezen a telefonon is visszakerülnek.',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _emailController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: _inputDecoration(
                                  label: 'E-mail-cím',
                                  hint: 'pl. kiss.janos@example.com',
                                  icon: Icons.alternate_email_rounded,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _nameController,
                                enabled: !_isLoading,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_isLoading) _handleLogin();
                                },
                                decoration: _inputDecoration(
                                  label: 'Név (ahogy regisztráltál)',
                                  hint: 'pl. Kiss János',
                                  icon: Icons.badge_outlined,
                                ),
                              ),
                              const SizedBox(height: 22),
                              FilledButton.icon(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.seed,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: _isLoading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: const Text(
                                  'Belépés',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _InfoTile(
                        icon: Icons.key_off_outlined,
                        title: 'Nincs külön jelszó',
                        text:
                            'A belépéshez a regisztrációkor megadott e-mail-cím '
                            'és név kell. A név kis- és nagybetűje nem számít.',
                      ),
                      const SizedBox(height: 10),
                      const _InfoTile(
                        icon: Icons.mail_outline_rounded,
                        title: 'Nem adtál meg e-mail-címet?',
                        text:
                            'Akkor a fiókod csak az eredeti telefonon érhető el. '
                            'Ott a Profil oldalon most is megadhatod.',
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.seed,
                        ),
                        child: const Text(
                          'Új vagyok – vissza a regisztrációhoz',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF8F5EE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.seed, width: 1.6),
      ),
    );
  }
}

/// Hajlított, olajzöld átmenetes fejléc a címerrel és a visszalépés gombbal.
class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipPath(
        clipper: _CurveClipper(),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, top + 4, 8, 54),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6E8560), AppColors.seed, Color(0xFF3F4E35)],
            ),
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white,
                  tooltip: 'Vissza',
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo_splash.png',
                  height: 68,
                  cacheHeight: 204,
                  semanticLabel: 'Nagyvázsony címere',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Üdv újra!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Folytasd a túrázást ott, ahol abbahagytad.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A fejléc alsó, ívelt pereme.
class _CurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(0, size.height - 36)
      ..quadraticBezierTo(
        size.width / 2,
        size.height + 18,
        size.width,
        size.height - 36,
      )
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3D5BC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.seed, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A3F2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(color: Color(0xFF6B5A44), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
