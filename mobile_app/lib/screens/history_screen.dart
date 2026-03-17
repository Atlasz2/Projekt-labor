import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  List<String> _safeFacts(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    return const [];
  }

  Future<void> _loadHistory() async {
    try {
      setState(() => _isLoading = true);
      final snapshot = await _firestore
          .collection('about')
          .orderBy('year', descending: false)
          .get();

      setState(() {
        _events = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'year': _safeString(data['year']),
            'title': _safeString(data['title'], fallback: 'Nagyvázsony'),
            'description': _safeString(data['description']),
            'period': _safeString(data['period']),
            'quote': _safeString(data['quote']),
            'imageUrl': _safeString(data['imageUrl']),
            'facts': _safeFacts(data['facts']),
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Hiba: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/var.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF2EBDD).withValues(alpha: 0.90),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text('Nagyvázsony története'),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset('assets/var.jpg', fit: BoxFit.cover),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                              const Color(0xFF2B2B2B).withValues(alpha: 0.75),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 20,
                        right: 20,
                        bottom: 56,
                        child: Text(
                          'Vár, végvári múlt, Kinizsi-emlékek és a település évszázados öröksége.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _loadHistory, child: const Text('Újrapróbálás')),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_events.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('Nincs történeti adat.')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  sliver: SliverList.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final isLast = index == _events.length - 1;
                      return _TimelineEntry(event: event, isLast: isLast);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isLast;

  const _TimelineEntry({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final facts = (event['facts'] as List<String>?) ?? const [];
    final imageUrl = event['imageUrl']?.toString() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4F2A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    (event['year']?.toString().isNotEmpty ?? false)
                        ? event['year'].toString().substring(0, event['year'].toString().length.clamp(0, 4))
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 3,
                  height: 180,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF8B7355).withValues(alpha: 0.55),
                        const Color(0xFF8B7355).withValues(alpha: 0.18),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _placeholder(),
                  )
                else
                  _placeholder(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['year']?.toString() ?? '',
                        style: const TextStyle(
                          color: Color(0xFF6B4F2A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event['title']?.toString() ?? '',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if ((event['period']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Chip(
                          label: Text(event['period'].toString()),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        event['description']?.toString() ?? '',
                        style: TextStyle(color: Colors.grey.shade700, height: 1.45),
                      ),
                      if ((event['quote']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B4F2A).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '"${event['quote']}"',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text('Érdekességek', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...facts.map(
                          (fact) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Icon(Icons.circle, size: 8, color: Color(0xFF6B4F2A)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(fact)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B7355), Color(0xFFC9A66B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.account_balance, size: 48, color: Colors.white54),
      ),
    );
  }
}

