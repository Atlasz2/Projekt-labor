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
  String _severity = 'medium';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'severity': _severity,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            service.isOnline
                ? 'A hibabejelentes el lett kuldve.'
                : 'Offline modban rogzitve. Online kapcsolatnal szinkronizalodik.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nem sikerult elkuldeni: $error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hibabejelentes')),
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
                    'Ha hibat talalsz, itt rogzitheto a bejelentes. Az admin latni fogja a nevedet es email cimedet is.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nev'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Kotelezo mező.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Kotelezo mező.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Rovid cim'),
                    validator: (value) =>
                        (value == null || value.trim().length < 4)
                        ? 'Irj legalabb 4 karaktert.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _severity,
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Alacsony')),
                      DropdownMenuItem(value: 'medium', child: Text('Kozepes')),
                      DropdownMenuItem(value: 'high', child: Text('Magas')),
                      DropdownMenuItem(
                        value: 'critical',
                        child: Text('Kritikus'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _severity = value ?? 'medium'),
                    decoration: const InputDecoration(labelText: 'Sulyossag'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 5,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Leiras'),
                    validator: (value) =>
                        (value == null || value.trim().length < 10)
                        ? 'Adj reszletesebb leirast.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _submitting ? 'Kuldes...' : 'Hibabejelentes elkuldese',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
