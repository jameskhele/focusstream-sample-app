import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'state/session.dart';

void main() => runApp(const FocusStreamApp());

class FocusStreamApp extends StatefulWidget {
  const FocusStreamApp({super.key});

  @override
  State<FocusStreamApp> createState() => _FocusStreamAppState();
}

class _FocusStreamAppState extends State<FocusStreamApp> {
  final Session _session = Session();

  @override
  void initState() {
    super.initState();
    _session.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FocusStream SaaS Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F111A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Premium indigo accent
          secondary: Color(0xFF10B981), // Emerald green
          surface: Color(0xFF1E2130),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E2130),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF151824),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: _session.status == SessionStatus.signedIn
          ? DashboardScreen(session: _session)
          : LoginScreen(session: _session),
    );
  }
}
