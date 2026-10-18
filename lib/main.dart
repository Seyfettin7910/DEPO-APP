import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/platform/db_fabrika.dart';

import 'services/supabase_service.dart';
import 'screens/giris/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mobilde sqflite doğrudan çalışır; Windows/Linux'ta FFI, web'de
  // tarayıcı içi sqlite (IndexedDB) devreye girer.
  veritabaniFabrikasiniAyarla();

  await SupabaseService.init();
  runApp(const ProviderScope(child: DepoApp()));
}

class DepoApp extends StatelessWidget {
  const DepoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Depo Takip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E6F40),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
