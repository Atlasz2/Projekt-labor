import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/offline_sync_service.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;

  Map<String, dynamic>? _contactData;
  bool _isLoading = true;

  final Map<String, dynamic> _demoData = {
    'name': 'Nagyvázsony Turisztikai Információ',
    'address': 'Nagyvázsony, Kastély utca 1.',
    'phone': '+36 88 564 000',
    'email': 'info@nagyvazsony.hu',
  };

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      final snapshot = await _firestore.collection('contact').limit(1).get();
      if (snapshot.docs.isNotEmpty) {
        final rawData = snapshot.docs.first.data();
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
        setState(() {
          _contactData = _demoData;
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _contactData = _demoData;
        _isLoading = false;
      });
    }
  }

  Future<void> _submitBugReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'title': 'Bejelentés a Kapcsolat oldalról',
      'description': _descriptionController.text.trim(),
      'severity': 'medium',
      'status': 'active',
      'resolved': false,
      'reported_by': {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'user_id': user?.uid ?? '',
        'app_version': '1.0.0',
        'os': Theme.of(context).platform.name,
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
        await FirebaseFirestore.instance.collection('bug_reports').doc(bugId).set({
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kapcsolat & Hibabejelentés'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.call_outlined), text: 'Kapcsolat'),
            Tab(icon: Icon(Icons.bug_report_outlined), text: 'Hibabejelentés'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildContactTab(),
          _buildBugReportTab(),
        ],
      ),
    );
  }

  Widget _buildContactTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_contactData == null) return const Center(child: Text('Nincs kapcsolati adat.'));

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                _buildItem(Icons.location_on, 'Cím', _safeString(_contactData!['address'])),
                const SizedBox(height: 16),
                _buildItem(Icons.phone, 'Telefon', _safeString(_contactData!['phone'])),
                const SizedBox(height: 16),
                _buildItem(Icons.email, 'Email', _safeString(_contactData!['email'])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBugReportTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Neved',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Kötelező mező.' : null,
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
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Kötelező mező.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Mi a probléma?',
                      hintText: 'Írd le részletesen, hogy mit tapasztaltál...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 10)
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
                      label: Text(_submitting ? 'Küldés...' : 'Bejelentés elküldése'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (uid != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('bug_reports')
                  .where('reported_by.user_id', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aTs = (a.data()['created_at_ms'] ?? 0) as num;
                    final bTs = (b.data()['created_at_ms'] ?? 0) as num;
                    return bTs.compareTo(aTs);
                  });

                if (docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin visszajelzések',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      ...docs.map((doc) {
                        final item = doc.data();
                        final response = (item['admin_response'] ?? '').toString().trim();
                        final closed = _isClosed(item);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['description'] ?? 'Nincs leírás').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                closed ? 'Állapot: Lezárt (true)' : 'Állapot: Aktív (false)',
                                style: TextStyle(
                                  color: closed ? const Color(0xFF065F46) : const Color(0xFF92400E),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                response.isEmpty
                                    ? 'Admin válasz még nem érkezett.'
                                    : 'Admin válasz: $response',
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
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
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
