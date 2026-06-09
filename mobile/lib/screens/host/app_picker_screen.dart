import 'package:flutter/material.dart';

import '../../services/apps/installed_apps.dart';
import '../../theme/app_colors.dart';

/// Sélecteur d'applications à envoyer à un autre téléphone (Mode Hôte, façon
/// Xender) : grille des apps installées avec leur logo, sélection multiple, puis
/// « Envoyer ». Renvoie la liste choisie via `Navigator.pop`.
class AppPickerScreen extends StatefulWidget {
  /// Injectable pour les tests ; en prod on lit le canal natif `linkup/apps`.
  final InstalledAppsService service;

  const AppPickerScreen({super.key, this.service = const InstalledAppsService()});

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  List<InstalledApp>? _apps;
  String? _error;
  String _query = '';
  final Set<String> _selected = {}; // packages cochés

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _apps = null;
      _error = null;
    });
    try {
      final apps = await widget.service.list();
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Impossible de lister les applications : $e');
    }
  }

  List<InstalledApp> get _visible {
    final apps = _apps ?? const <InstalledApp>[];
    if (_query.isEmpty) return apps;
    final q = _query.toLowerCase();
    return apps.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  void _toggle(InstalledApp app) {
    setState(() {
      if (!_selected.remove(app.packageName)) _selected.add(app.packageName);
    });
  }

  void _confirm() {
    final apps = _apps ?? const <InstalledApp>[];
    final chosen =
        apps.where((a) => _selected.contains(a.packageName)).toList();
    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer des applications')),
      body: SafeArea(child: _buildBody()),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _confirm,
              icon: const Icon(Icons.send_rounded),
              label: Text('Envoyer (${_selected.length})'),
            ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.apps_rounded, size: 64, color: AppColors.faint),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_apps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final apps = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Rechercher une application…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: apps.isEmpty
              ? const Center(child: Text('Aucune application trouvée.'))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 108,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (_, i) {
                    final app = apps[i];
                    return _AppTile(
                      app: app,
                      selected: _selected.contains(app.packageName),
                      onTap: () => _toggle(app),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Tuile d'une app : logo, nom (2 lignes), taille, + coche de sélection.
class _AppTile extends StatelessWidget {
  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  const _AppTile({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AppColors.brand : AppColors.hairline,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: AppColors.cardShadow,
                ),
                padding: const EdgeInsets.all(10),
                child: app.icon != null
                    ? Image.memory(app.icon!, gaplessPlayback: true)
                    : const Icon(Icons.android_rounded,
                        color: AppColors.brand, size: 28),
              ),
              if (selected)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            app.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.15,
            ),
          ),
          Text(
            _formatBytes(app.sizeBytes),
            style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int b) {
    if (b <= 0) return '';
    const units = ['o', 'Ko', 'Mo', 'Go'];
    var v = b.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 10 || u == 0 ? 0 : 1)} ${units[u]}';
  }
}
