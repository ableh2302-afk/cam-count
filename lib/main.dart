import 'package:flutter/material.dart';
import 'screens/activation_screen.dart';
import 'screens/home_screen.dart';
import 'services/license.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.load();
  runApp(const CamCountApp());
}

class CamCountApp extends StatefulWidget {
  const CamCountApp({super.key});
  @override
  State<CamCountApp> createState() => _CamCountAppState();
}

class _CamCountAppState extends State<CamCountApp> {
  late Future<LicenseStatus> _f = LicenseService.check();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cam Count',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: FutureBuilder<LicenseStatus>(
        future: _f,
        builder: (c, s) {
          if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (s.data!.valid) return const HomeScreen();
          return ActivationScreen(
            message: s.data!.message,
            onActivated: () => setState(() => _f = LicenseService.check()),
          );
        },
      ),
    );
  }
}
