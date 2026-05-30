import 'dart:async';

import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/services/agent_discovery.dart';

/// Implémentation contrôlable de [AgentDiscovery] pour les widget tests.
///
/// `emit(...)` pousse une liste arbitraire sur le stream, sans toucher au socket
/// UDP ni au MethodChannel natif.
class FakeDiscovery implements AgentDiscovery {
  final _controller = StreamController<List<LinkupAgent>>.broadcast();
  List<LinkupAgent> _items = const [];

  int scanCount = 0;
  int startCount = 0;
  int disposeCount = 0;
  int clearCount = 0;

  void emit(List<LinkupAgent> next) {
    _items = List.unmodifiable(next);
    _controller.add(_items);
  }

  @override
  Stream<List<LinkupAgent>> get stream => _controller.stream;

  @override
  List<LinkupAgent> get agents => _items;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> scanOnce() async {
    scanCount++;
  }

  @override
  LinkupAgent addManualAgent({
    required String address,
    int bridgePort = 8765,
    int reverbPort = 8080,
    String? label,
  }) {
    final agent = LinkupAgent(
      instanceName: label ?? 'manual:$address:$bridgePort',
      host: address,
      address: address,
      reverbPort: reverbPort,
      bridgePort: bridgePort,
      source: LinkupAgentSource.manual,
    );
    emit([..._items, agent]);
    return agent;
  }

  @override
  void clear() {
    clearCount++;
    emit(const []);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _controller.close();
  }
}
