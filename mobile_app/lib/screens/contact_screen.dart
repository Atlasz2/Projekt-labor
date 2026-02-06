import 'package:flutter/material.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kapcsolat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nagyvázsony Turisztikai Információ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildContactItem(Icons.location_on, 'Nagyvázsony, Kastély utca 1.', () {}),
                  const SizedBox(height: 12),
                  _buildContactItem(Icons.phone, '+36 88 564 000', () {}),
                  const SizedBox(height: 12),
                  _buildContactItem(Icons.email, 'info@nagyvazsony.hu', () {}),
                  const SizedBox(height: 12),
                  _buildContactItem(Icons.access_time, 'H-V: 10:00 - 18:00', () {}),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Icon(Icons.map, size: 80, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  static Widget _buildContactItem(IconData icon, String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF667EEA)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
