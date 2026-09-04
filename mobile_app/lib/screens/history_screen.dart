import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/app_background.dart';
import '../widgets/offline_image.dart';
import '../utils/project_filter.dart';

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
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<void> _loadHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final query = _firestore
          .collection('about')
          .orderBy('year', descending: false);

      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        // A szerveres lekérés timeoutol, ha a hálózat csatlakozott, de halott,
        // különben a képernyő örökké pörögne.
        snapshot = await query.get().timeout(const Duration(seconds: 10));
      } catch (_) {
        // Visszalépés a Firestore helyi gyorsítótárára (offline / gyenge net).
        snapshot = await query.get(const GetOptions(source: Source.cache));
      }

      if (!mounted) return;
      setState(() {
        // Csak ennek a településnek a történeti bejegyzései.
        _events = whereActiveProject(snapshot.docs).map((doc) {
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
      if (!mounted) return;
      setState(() {
        _error = 'Hiba: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE4),
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackground()),
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
                      const AppBackground(),
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
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  sliver: SliverList.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      return _TimelineEntry(
                        event: _events[index],
                        initiallyExpanded: index == 0,
                      );
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

class _TimelineEntry extends StatefulWidget {
  final Map<String, dynamic> event;
  final bool initiallyExpanded;

  const _TimelineEntry({required this.event, required this.initiallyExpanded});

  @override
  State<_TimelineEntry> createState() => _TimelineEntryState();
}

class _TimelineEntryState extends State<_TimelineEntry> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
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
          initiallyExpanded: widget.initiallyExpanded,
          // A leírás csak EGYSZER jelenjen meg: összecsukva rövidítve,
          // kinyitva teljes egészében (a kép alatti duplikátum megszűnt).
          onExpansionChanged: (value) => setState(() => _expanded = value),
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
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
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