import 'package:flutter/material.dart';

import 'screens/launch_gate.dart';

void main() {
  runApp(const LinkupApp());
}

class LinkupApp extends StatelessWidget {
  const LinkupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linkup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // S2.J5 : reconnexion auto si un PC est déjà appairé (cf. LaunchGate).
      home: const LaunchGate(),
    );
  }
}
