import 'package:flutter/material.dart';

import 'models/linkup_agent.dart';
import 'screens/agent_picker_screen.dart';

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
      home: AgentPickerScreen(
        onAgentSelected: (agent) => _showAgentSelected(context, agent),
      ),
    );
  }

  void _showAgentSelected(BuildContext context, LinkupAgent agent) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Agent sélectionné : ${agent.displayName} '
          '(${agent.address}:${agent.bridgePort})',
        ),
      ),
    );
  }
}
