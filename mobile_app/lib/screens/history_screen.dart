import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final events = [
      {'year': '1265', 'title': 'Nagyvázsony alapítása', 'description': 'A várat a Módosult családnak alapította.'},
      {'year': '1479', 'title': 'A kastély újjáépítése', 'description': 'A török támadások után helyreállításra kerül a kastély.'},
      {'year': '1848', 'title': 'Történelmi események', 'description': 'A szabadsági harc időszakában fontos szerepe volt a város.'},
      {'year': '1945', 'title': 'Felszabadulás', 'description': 'Az épület új korszakba lép.'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Nagyvázsony története')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: const Color(0xFF667EEA), borderRadius: BorderRadius.circular(50)),
                        child: const Center(child: Icon(Icons.history_edu, color: Colors.white, size: 24)),
                      ),
                      if (index < events.length - 1)
                        Container(width: 2, height: 60, color: Colors.grey[300]),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(event['year'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF667EEA))),
                        const SizedBox(height: 4),
                        Text(event['title'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(event['description'] as String, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
