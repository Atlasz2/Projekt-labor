import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/privacy_screen.dart';
import '../utils/app_messenger.dart';
import '../services/account_service.dart';

/// A profil "Adataim és adatvédelem" (GDPR) szekciója: adatexport és
/// fiók-törlés. Saját állapotot kezel (folyamatjelzők), így a profil
/// képernyőnek nem kell erről tudnia.
class DataRightsSection extends StatefulWidget {
  const DataRightsSection({super.key});

  @override
  State<DataRightsSection> createState() => _DataRightsSectionState();
}

class _DataRightsSectionState extends State<DataRightsSection> {
  bool _exportInProgress = false;
  bool _deleteInProgress = false;

  Future<void> _handleExport() async {
    setState(() => _exportInProgress = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Adataid összegyűjtése… ez pár másodpercig tart.'),
        duration: Duration(seconds: 20),
      ),
    );
    try {
      final result = await AccountService.exportToDownloads();
      messenger.hideCurrentSnackBar();
      if (result.savedToDownloads) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Letöltve a Letöltések mappába: ${result.fileName}'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Megnyitás',
              onPressed: () => AccountService.openDownloaded(result.uri!),
            ),
          ),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Az adatexport nem sikerült: ${_friendlyError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportInProgress = false);
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fiók végleges törlése'),
        content: const Text(
          'Ez törli a profilodat, a pontjaidat, a haladásodat és a ranglista-'
          'bejegyzésedet. A művelet NEM vonható vissza.\n\n'
          'Biztosan törlöd a fiókodat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleteInProgress = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    // Blokkoló folyamatjelző: a törlés alatt ne lehessen mást csinálni.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(width: 18),
                Expanded(child: Text('Fiókod törlése folyamatban…')),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await AccountService.deleteAccount();
      // A kijelentkezés után az AuthGate (a navigátor első oldala) a
      // regisztrációs képernyőt mutatja: minden felette lévő oldalt (profil,
      // folyamatjelző) bezárunk, hogy oda kerüljön a felhasználó.
      navigator.popUntil((route) => route.isFirst);
      showAppMessage(
        'A fiókodat és minden hozzá tartozó adatodat töröltük.',
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      navigator.pop(); // folyamatjelző
      if (!mounted) return;
      setState(() => _deleteInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A fiók törlése nem sikerült: ${_friendlyError(e)}'),
        ),
      );
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('unauthenticated')) return 'jelentkezz be újra';
    if (text.contains('unavailable') || text.contains('network')) {
      return 'nincs internetkapcsolat';
    }
    return 'próbáld újra később';
  }

  @override
  Widget build(BuildContext context) {
    // Összecsukható, alapból zárt szekció — ritkán használt, ezért ne
    // uralja a profil képernyőt.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // A ThemeData az ExpansionTile alap szürke elválasztóit rejti el.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.shield_outlined, color: Colors.blueGrey.shade400),
          title: const Text(
            'Adataim és adatvédelem',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A GDPR szerint jogod van letölteni vagy véglegesen törölni a rólad tárolt adatokat.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Adatkezelési tájékoztató'),
              subtitle: const Text('Milyen adatot, miért és meddig kezelünk'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PrivacyScreen())),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_outlined),
              title: const Text('Adataim letöltése'),
              subtitle: const Text('PDF a telefon Letöltések mappájába'),
              trailing: _exportInProgress
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _exportInProgress ? null : _handleExport,
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Colors.red.shade400,
              ),
              title: Text(
                'Fiók törlése',
                style: TextStyle(color: Colors.red.shade400),
              ),
              subtitle: const Text('Végleges, nem visszavonható'),
              trailing: _deleteInProgress
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right, color: Colors.red.shade400),
              onTap: _deleteInProgress ? null : _handleDeleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}
