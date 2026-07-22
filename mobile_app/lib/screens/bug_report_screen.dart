import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/offline_sync_service.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? '';
    _emailController.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool _isClosed(Map<String, dynamic> item) {
    // A státusz az elsődleges: az admin lezáráskor status:"closed"-ot ír.
    // (A régi `resolved: false` mező korábban felülírta ezt, ezért a lezárás
    // nem látszott a telefonon.)
    final status = (item['status'] ?? '').toString().toLowerCase();
    if (status == 'closed' || status == 'fixed' || status == 'resolved') {
      return true;
    }
    return item['resolved'] == true;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'status': 'open',
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
      _titleController.clear();
      _descriptionController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            service.isOnline
                ? 'A hibajelentés el lett küldve.'
                : 'Offline módban rögzítve. Szinkronizálódik, amint visszatér a kapcsolat.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nem sikerült elküldeni: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Hibabejelentés')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ha hibát találsz, itt rögzítheted a bejelentést. Az admin látni fogja a nevedet és email címedet is.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Lentebb a korábbi bejelentéseidet és az admin válaszait is látod.',
                      style: TextStyle(color: Color(0xFF1E3A8A), height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Név'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Kötelező mező.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Kötelező mező.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Rövid cím'),
                    validator: (value) =>
                        (value == null || value.trim().length < 4)
                        ? 'Írj legalább 4 karaktert.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 5,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Leírás'),
                    validator: (value) =>
                        (value == null || value.trim().length < 10)
                        ? 'Adj részletesebb leírást.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _submitting ? 'Küldés...' : 'Hibabejelentés elküldése',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('bug_reports')
                  .where('reported_by.user_id', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final Widget content;
                if (snapshot.hasError) {
                  content = const Text(
                    'A korábbi bejelentéseid betöltése most nem sikerült. '
                    'Ellenőrizd a kapcsolatot, és próbáld újra később.',
                    style: TextStyle(color: Color(0xFF92400E), height: 1.45),
                  );
                } else if (snapshot.connectionState == ConnectionState.waiting) {
                  content = const Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Korábbi bejelentéseid betöltése...'),
                    ],
                  );
                } else {
                  final docs = [...?snapshot.data?.docs]
                    ..sort((a, b) {
                      final aTs = (a.data()['created_at_ms'] ?? 0) as num;
                      final bTs = (b.data()['created_at_ms'] ?? 0) as num;
                      return bTs.compareTo(aTs);
                    });

                  if (docs.isEmpty) {
                    content = const Text(
                      'Még nincs korábbi hibabejelentésed. Az elküldött '
                      'bejelentéseid és az admin válaszai itt jelennek meg.',
                      style: TextStyle(color: Color(0xFF475569), height: 1.45),
                    );
                  } else {
                    content = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: docs.map((doc) {
                        final item = doc.data();
                        final response = (item['admin_response'] ?? '')
                            .toString()
                            .trim();
                        final closed = _isClosed(item);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatCreatedAt(item),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    closed ? 'Lezárt' : 'Folyamatban',
                                    style: TextStyle(
                                      color: closed
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFF92400E),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (item['title'] ?? 'Hibabejelentés').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text((item['description'] ?? '').toString()),
                              const SizedBox(height: 8),
                              Text(
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
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  }
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Korábbi hibabejelentéseid',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      content,
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}