import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/offline_sync_service.dart';
import '../utils/project_filter.dart';
import '../config/app_config.dart';
import '../utils/app_version.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen>
    with SingleTickerProviderStateMixin {
  // A korábbi bejelentések élő lekérdezése felhasználónként egyszer jön
  // létre; a build-ben létrehozott stream minden újrarajzoláskor új
  // Firestore-feliratkozást nyitna.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _reportsStream;
  String? _reportsStreamUid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _reportsFor(String uid) {
    if (_reportsStream == null || _reportsStreamUid != uid) {
      _reportsStreamUid = uid;
      _reportsStream = FirebaseFirestore.instance
          .collection('bug_reports')
          .where('reported_by.user_id', isEqualTo: uid)
          .snapshots();
    }
    return _reportsStream!;
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;

  Map<String, dynamic>? _contactData;
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadContactData();
    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? '';
    _emailController.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _descriptionController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadContactData() async {
    try {
      setState(() => _isLoading = true);
      // Településenként külön kapcsolati dokumentum van, ezért a teljes
      // kollekcióból az aktív településhez tartozót választjuk ki.
      final snapshot = await _firestore.collection('contact').get();
      final scoped = whereActiveProject(snapshot.docs);
      if (scoped.isNotEmpty) {
        final rawData = scoped.first.data();
        final mainOffice =
            (rawData['mainOffice'] as Map<String, dynamic>?) ?? rawData;
        setState(() {
          _contactData = {
            'name': mainOffice['name'],
            'address': mainOffice['address'],
            'phone': mainOffice['phone'],
            'email': mainOffice['email'],
          };
          _isLoading = false;
        });
      } else {
        // Nincs megadott elérhetőség: nem mutatunk ellenőrizetlen adatot.
        setState(() {
          _contactData = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Elérhetőségek betöltése sikertelen: $e');
      setState(() {
        _contactData = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _submitBugReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final user = FirebaseAuth.instance.currentUser;
    final platform = Theme.of(context).platform.name;
    final appVersion = await appVersionLabel();
    final now = DateTime.now();
    final payload = <String, dynamic>{
      // Melyik település adminja lássa a bejelentést. A payloadban van, hogy az
      // offline sorba tett bejelentés is megkapja.
      'projectId': AppConfig.projectId,
      'title': 'Bejelentés a Kapcsolat oldalról',
      'description': _descriptionController.text.trim(),
      'status': 'active',
      'resolved': false,
      'reported_by': {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'user_id': user?.uid ?? '',
        'app_version': appVersion,
        'os': platform,
      },
      'admin_response': '',
      'screenshot_urls': <String>[],
      'created_at_ms': now.millisecondsSinceEpoch,
      'created_at_text': now.toIso8601String(),
      'updated_at_text': now.toIso8601String(),
    };

    final service = OfflineSyncService();
    final bugId = 'bug_${now.microsecondsSinceEpoch}';

    try {
      if (service.isOnline) {
        await FirebaseFirestore.instance
            .collection('bug_reports')
            .doc(bugId)
            .set({
              ...payload,
              'created_at': FieldValue.serverTimestamp(),
              'updated_at': FieldValue.serverTimestamp(),
            });
      } else {
        await service.queueAction(
          actionType: 'create',
          collection: 'bug_reports',
          docId: bugId,
          data: payload,
        );
      }

      if (!mounted) return;
      _descriptionController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            service.isOnline
                ? 'Bejelentés sikeresen elküldve!'
                : 'Offline módban rögzítve. Online kapcsolatkor szinkronizálódik.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _tabController.animateTo(2);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sikertelen küldés: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map && value.containsKey('seconds')) return '';
    return value.toString();
  }

  bool _isClosed(Map<String, dynamic> item) {
    final resolved = item['resolved'];
    if (resolved is bool) return resolved;
    final status = (item['status'] ?? '').toString().toLowerCase();
    return status == 'closed' || status == 'fixed' || status == 'resolved';
  }

  String _formatCreatedAt(Map<String, dynamic> item) {
    final raw = item['created_at_text']?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 'Ismeretlen időpont';
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}. $mm. $dd. $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kapcsolat & Hibabejelentés'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.call_outlined), text: 'Kapcsolat'),
            Tab(
              icon: Icon(Icons.bug_report_outlined),
              text: 'Új hibabejelentés',
            ),
            Tab(icon: Icon(Icons.history), text: 'Előzmények'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildContactTab(),
          _buildBugReportTab(),
          _buildBugHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildContactTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_contactData == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Az elérhetőségek most nem érhetők el. Ellenőrizd az '
            'internetkapcsolatot, vagy nézz vissza később.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _safeString(_contactData!['name']),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF667EEA),
                  ),
                ),
                const SizedBox(height: 20),
                _buildItem(
                  Icons.location_on,
                  'Cím',
                  _safeString(_contactData!['address']),
                ),
                const SizedBox(height: 16),
                _buildItem(
                  Icons.phone,
                  'Telefon',
                  _safeString(_contactData!['phone']),
                ),
                const SizedBox(height: 16),
                _buildItem(
                  Icons.email,
                  'Email',
                  _safeString(_contactData!['email']),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBugReportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Form(
            key: _formKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ha hibát találsz az alkalmazásban, itt tudod jelezni. A bejelentés offline módban is rögzíthető.',
                    style: TextStyle(height: 1.5, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          color: Color(0xFF2563EB),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'A korábbi bejelentéseidet és az admin válaszait az Előzmények fülön találod.',
                            style: TextStyle(
                              color: Color(0xFF1E3A8A),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Neved',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Kötelező mező.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Kötelező mező.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Mi a probléma?',
                      hintText: 'Írd le részletesen, hogy mit tapasztaltál...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'Legalább 10 karakter szükséges.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submitBugReport,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        _submitting ? 'Küldés...' : 'Bejelentés elküldése',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBugHistoryTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Jelentkezz be a korábbi hibabejelentéseid megtekintéséhez.',
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reportsFor(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aTs = (a.data()['created_at_ms'] ?? 0) as num;
            final bTs = (b.data()['created_at_ms'] ?? 0) as num;
            return bTs.compareTo(aTs);
          });

        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Még nincs korábbi hibabejelentésed.'),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Korábbi hibabejelentéseid',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Itt látod az állapotot és az admin válaszát is.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...docs.map((doc) {
              final item = doc.data();
              final response = (item['admin_response'] ?? '').toString().trim();
              final closed = _isClosed(item);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: closed
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFCD34D),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatCreatedAt(item),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: closed
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            closed ? 'Lezárt' : 'Folyamatban',
                            style: TextStyle(
                              color: closed
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF92400E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (item['description'] ?? 'Nincs leírás').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: response.isEmpty
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        response.isEmpty
                            ? 'Admin válasz még nem érkezett.'
                            : 'Admin válasz: $response',
                        style: TextStyle(
                          color: response.isEmpty
                              ? const Color(0xFF475569)
                              : const Color(0xFF1D4ED8),
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Lezárt bejelentés már nem szerkeszthető (a szabályok
                        // sem engedik), csak visszavonható.
                        if (!closed)
                          TextButton.icon(
                            onPressed: () => _editReport(
                              doc.id,
                              (item['description'] ?? '').toString(),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Szerkesztés'),
                          ),
                        TextButton.icon(
                          onPressed: () => _deleteReport(doc.id),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFB91C1C),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Visszavonás'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// A saját, még nyitott bejelentés leírásának javítása.
  Future<void> _editReport(String id, String current) async {
    final controller = TextEditingController(text: current);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bejelentés szerkesztése'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Mi a probléma?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || updated == current.trim()) return;
    if (updated.isEmpty) {
      _showSnack('A leírás nem lehet üres.');
      return;
    }
    try {
      final now = DateTime.now();
      await FirebaseFirestore.instance
          .collection('bug_reports')
          .doc(id)
          .update({
            'description': updated,
            'updated_at_text': now.toIso8601String(),
            'updated_at_ms': now.millisecondsSinceEpoch,
          });
      _showSnack('A bejelentést frissítettük.');
    } catch (e) {
      debugPrint('Bejelentés szerkesztése sikertelen: $e');
      _showSnack(
        'A mentés nem sikerült. Ellenőrizd a kapcsolatot, és próbáld újra.',
      );
    }
  }

  /// A saját bejelentés visszavonása (törlése) megerősítés után.
  Future<void> _deleteReport(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bejelentés visszavonása'),
        content: const Text(
          'Biztosan visszavonod ezt a bejelentést? A művelet nem vonható vissza.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Visszavonás'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('bug_reports')
          .doc(id)
          .delete();
      _showSnack('A bejelentést visszavontuk.');
    } catch (e) {
      debugPrint('Bejelentés törlése sikertelen: $e');
      _showSnack(
        'A törlés nem sikerült. Ellenőrizd a kapcsolatot, és próbáld újra.',
      );
    }
  }

  Widget _buildItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF667EEA), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
