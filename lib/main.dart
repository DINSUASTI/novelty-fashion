import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'data/inventory_repository.dart';
import 'data/database_factory.dart';
import 'biometric_gate.dart';
import 'inventory_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Esta aplicación solo está disponible para Android.'),
          ),
        ),
      ),
    );
    return;
  }

  try {
    await prepareInventoryDatabase();
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('No fue posible preparar la base local.')),
        ),
      ),
    );
    return;
  }
  runApp(const AndroidBiometricGate(child: NoveltyFashionApp()));
}

class NoveltyFashionApp extends StatelessWidget {
  const NoveltyFashionApp({super.key, this.repository, this.authenticateClear});

  final InventoryRepository? repository;
  final Future<bool> Function()? authenticateClear;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Novelty Fashion',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF007C83),
              primary: const Color(0xFF007C83),
              surface: const Color(0xFFFAFCFC),
            ).copyWith(
              primary: const Color(0xFF007C83),
              onPrimary: Colors.white,
              primaryContainer: const Color(0xFFB6F1F2),
              onPrimaryContainer: const Color(0xFF002F32),
              secondary: const Color(0xFF3157C8),
              secondaryContainer: const Color(0xFFDCE2FF),
              tertiary: const Color(0xFFE05D44),
              error: const Color(0xFFBA1A1A),
              onError: Colors.white,
              errorContainer: const Color(0xFFFFDAD6),
              onErrorContainer: const Color(0xFF410002),
              outlineVariant: const Color(0xFFC5D0D0),
            ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F7),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFD8E1E1)),
          ),
        ),
      ),
      home: InventoryPage(
        repository: repository,
        authenticateClear: authenticateClear,
      ),
    );
  }
}
