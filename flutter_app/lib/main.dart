// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/supabase_service.dart';
import 'screens/inspection_wizard_screen.dart';
import 'screens/admin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Força orientação vertical para celulares operacionais
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Estilização da barra de status do Android (Tático Dark)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1329),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Inicializa conexão Supabase
  await SupabaseService.instance.initialize();

  runApp(const SisCheckVtrApp());
}

class SisCheckVtrApp extends StatelessWidget {
  const SisCheckVtrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SisCheck-VTR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1329),
        primaryColor: const Color(0xFFF59E0B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF59E0B),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF0F172A),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Roboto',
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  bool _showingAdmin = false;

  @override
  Widget build(BuildContext context) {
    if (_showingAdmin) {
      return AdminScreen(
        onBackToDriver: () => setState(() => _showingAdmin = false),
      );
    }

    return InspectionWizardScreen(
      onOpenAdmin: () => setState(() => _showingAdmin = true),
    );
  }
}
