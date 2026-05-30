import 'package:flutter/material.dart';

import 'models/linkup_agent.dart';
import 'screens/agent_detail_screen.dart';
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
      home: Builder(
        builder: (context) => AgentPickerScreen(
          onAgentSelected: (agent) => _openDetail(context, agent),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, LinkupAgent agent) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentDetailScreen(agent: agent),
      ),
    );
  }
}
