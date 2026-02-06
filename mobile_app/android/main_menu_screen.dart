import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'trips_screen.dart';
import 'programs_screen.dart';
import 'profile_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const TripsScreen(),
    const ProgramsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏰 Nagyvázsony Túraútvonal'),
        elevation: 2,
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Túrák',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Programok',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profilom',
          ),
        ],
      ),
    );
  }
}
