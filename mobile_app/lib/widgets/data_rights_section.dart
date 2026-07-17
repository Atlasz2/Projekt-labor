import 'package:flutter/material.dart';

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
    try {
      await AccountService.exportAndShare();
    } catch (e) {
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
    try {
      await AccountService.deleteAccount();
      // Sikeres törlés után az AuthGate a kijelentkezésre reagálva a
      // bejelentkező képernyőre vált — nincs több teendő itt.
    } catch (e) {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.blueGrey.shade400),
                const SizedBox(width: 8),
                const Text(
                  'Adataim és adatvédelem',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A GDPR szerint jogod van letölteni vagy véglegesen törölni a rólad tárolt adatokat.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_outlined),
              title: const Text('Adataim letöltése'),
              subtitle: const Text('Exportál JSON-fájlba és megoszt'),
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
              leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade400),
              title: Text('Fiók törlése', style: TextStyle(color: Colors.red.shade400)),
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
