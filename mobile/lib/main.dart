import 'package:flutter/material.dart';

import 'screens/launch_gate.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const LinkupApp());
}

class LinkupApp extends StatelessWidget {
  const LinkupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linkup',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // S2.J5 : reconnexion auto si un PC est déjà appairé (cf. LaunchGate).
      home: const LaunchGate(),
    );
  }
}
