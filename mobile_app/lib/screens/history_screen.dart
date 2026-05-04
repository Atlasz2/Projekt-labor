import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/offline_image.dart';

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
  String _selectedPeriod = 'Összes';

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
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _periodLabel(Map<String, dynamic> event) {
    return _safeString(event['period']);
  }

  Future<void> _loadHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

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
    final periods = _events
        .map(_periodLabel)
        .where((period) => period.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final activePeriod = periods.contains(_selectedPeriod)
        ? _selectedPeriod
        : 'Összes';
    final filteredEvents = activePeriod == 'Összes'
        ? _events
        : _events.where((event) => _periodLabel(event) == activePeriod).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE4),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/var.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    const Color(0xFFF5EFE4).withValues(alpha: 0.92),
                    const Color(0xFFF5EFE4),
                  ],
                ),
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF1F2937),
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsetsDirectional.only(
                    start: 56,
                    bottom: 14,
                    end: 14,
                  ),
                  expandedTitleScale: 1.18,
                  title: const Text(
                    'Nagyvázsony története',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset('assets/var.jpg', fit: BoxFit.cover),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.72),
                            ],
                          ),
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
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadHistory,
                            child: const Text('Újrapróbálás'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_events.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('Nincs történeti adat.')),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Idővonal és korszakok',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Válassz korszakot, majd nyisd le az eseménykártyát a részletekért. Így hosszabb leírásoknál is átlátható marad az oldal.',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                          if (periods.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: const Text('Összes'),
                                      selected: activePeriod == 'Összes',
                                      onSelected: (_) {
                                        setState(() => _selectedPeriod = 'Összes');
                                      },
                                    ),
                                  ),
                                  ...periods.map(
                                    (period) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(period),
                                        selected: activePeriod == period,
                                        onSelected: (_) {
                                          setState(() => _selectedPeriod = period);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (filteredEvents.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Ebben a korszakban nincs még megjeleníthető esemény.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList.builder(
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        return _TimelineEntry(
                          event: filteredEvents[index],
                          initiallyExpanded: index == 0,
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool initiallyExpanded;

  const _TimelineEntry({required this.event, required this.initiallyExpanded});

  @override
  Widget build(BuildContext context) {
    final facts = (event['facts'] as List<String>?) ?? const [];
    final imageUrl = event['imageUrl']?.toString() ?? '';
    final description = event['description']?.toString() ?? '';
    final period = event['period']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B4F2A),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      event['year']?.toString() ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (period.isNotEmpty)
                    Chip(
                      label: Text(period),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                event['title']?.toString() ?? '',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.5),
                ),
              ],
            ],
          ),
          children: [
            if (imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: OfflineImage.network(
                    imageUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _placeholder(),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _placeholder(),
                ),
              ),
            if (description.isNotEmpty)
              Text(
                description,
                style: TextStyle(color: Colors.grey.shade800, height: 1.6),
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
              const SizedBox(height: 16),
              const Text(
                'Érdekességek',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...facts.map(
                (fact) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: Color(0xFF6B4F2A),
                        ),
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
    );
  }

  Widget _placeholder() {
    return Container(
      height: 140,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B7355), Color(0xFFC9A66B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.account_balance_outlined,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}