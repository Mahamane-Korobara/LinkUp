import '../models/linkup_agent.dart';

/// Surface publique d'un service de découverte d'agents Linkup.
///
/// Découpler l'écran picker de l'implémentation mDNS concrète permet d'injecter
/// une `FakeDiscovery` dans les widget tests sans toucher au socket UDP.
abstract class AgentDiscovery {
  Stream<List<LinkupAgent>> get stream;
  List<LinkupAgent> get agents;

  Future<void> start();
  Future<void> scanOnce();
  LinkupAgent addManualAgent({
    required String address,
    int bridgePort,
    int reverbPort,
    String? label,
  });
  Future<void> dispose();
}
