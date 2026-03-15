import "package:flutter/material.dart";
import "package:cloud_firestore/cloud_firestore.dart";

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _contactData;
  bool _isLoading = true;
  String? _error;

  final Map<String, dynamic> _demoData = {
    "name": "Nagyvázsony Turisztikai Információ",
    "address": "Nagyvázsony, Kastély utca 1.",
    "phone": "+36 88 564 000",
    "email": "info@nagyvazsony.hu",
    "hours": "H-V: 10:00 - 18:00",
  };

  @override
  void initState() {
    super.initState();
    _loadContactData();
  }

  Future<void> _loadContactData() async {
    try {
      setState(() => _isLoading = true);
      debugPrint("📞 Kapcsolat adatok betöltése...");
      
      final snapshot = await _firestore.collection("contact").limit(1).get();
      
      if (snapshot.docs.isNotEmpty) {
        debugPrint("✅ Firestore adat betöltve");
        final rawData = snapshot.docs.first.data();
        final mainOffice = (rawData["mainOffice"] as Map<String, dynamic>?) ?? rawData;
        setState(() {
          _contactData = {
            "name": mainOffice["name"],
            "address": mainOffice["address"],
            "phone": mainOffice["phone"],
            "email": mainOffice["email"],
            "hours": rawData["hours"] ?? mainOffice["hours"],
          };
          _isLoading = false;
        });
      } else {
        debugPrint("⚠️ Nincs Firestore adat, demo adatok használata");
        setState(() {
          _contactData = _demoData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Hiba: $e - Demo adatok használata");
      setState(() {
        _contactData = _demoData;
        _error = null;
        _isLoading = false;
      });
    }
  }

  String _safeString(dynamic value) {
    if (value == null) return "";
    if (value is String) return value;
    if (value is Map && value.containsKey("seconds")) return "";
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Kapcsolat"), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadContactData,
                        child: const Text("Újrapróbálás"),
                      ),
                    ],
                  ),
                )
              : _contactData == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text("Nincs kontakt adat"),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _safeString(_contactData!["name"]),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF667EEA),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    _buildItem(Icons.location_on, "Cím", _safeString(_contactData!["address"])),
                                    const SizedBox(height: 16),
                                    _buildItem(Icons.phone, "Telefon", _safeString(_contactData!["phone"])),
                                    const SizedBox(height: 16),
                                    _buildItem(Icons.email, "Email", _safeString(_contactData!["email"])),
                                    const SizedBox(height: 16),
                                    _buildItem(Icons.access_time, "Nyitvatartás", _safeString(_contactData!["hours"])),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

