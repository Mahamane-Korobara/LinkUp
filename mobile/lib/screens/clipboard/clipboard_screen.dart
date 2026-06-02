import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/clipboard/clipboard_client.dart';
import '../../services/clipboard/clipboard_watcher.dart';
import '../../services/pairing/paired_device_store.dart';

/// Lit le presse-papier du téléphone (injectable pour les widget tests).
typedef PhoneClipboardReader = Future<String?> Function();

/// Écrit dans le presse-papier du téléphone (injectable pour les widget tests).
typedef PhoneClipboardWriter = Future<void> Function(String text);

/// Filtre d'origine de l'historique presse-papier.
enum _ClipFilter { all, sent, received }

/// Écran presse-papier + lien rapide (S5).
///
/// - Manuel : « Envoyer » (lit le presse-papier du tél au tap), « Coller depuis
///   le PC », et tap sur un item = recopier.
/// - **Auto** (interrupteur) : tant que l'app est au 1er plan, chaque copie sur
///   le tél est poussée sur le PC, et le presse-papier du PC est tiré
///   périodiquement vers le tél. Android interdit l'arrière-plan → auto = 1er
///   plan uniquement, comme KDE Connect. Un anti-rebond partagé évite la boucle.
class ClipboardScreen extends StatefulWidget {
  final PairedDevice device;
  final ClipboardClient? client;
  final ClipboardWatcher? watcher;
  final PhoneClipboardReader? readPhoneClipboard;
  final PhoneClipboardWriter? writePhoneClipboard;

  /// Intervalle de tirage du presse-papier PC en mode auto.
  final Duration autoPollInterval;

  const ClipboardScreen({
    super.key,
    required this.device,
    this.client,
    this.watcher,
    this.readPhoneClipboard,
    this.writePhoneClipboard,
    this.autoPollInterval = const Duration(seconds: 3),
  });

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  late final ClipboardClient _client;
  late final bool _ownsClient;
  late final ClipboardWatcher _watcher;
  late final bool _ownsWatcher;
  late final PhoneClipboardReader _read;
  late final PhoneClipboardWriter _write;

  List<ClipboardItem>? _items;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  _ClipFilter _filter = _ClipFilter.all;

  // Mode auto (1er plan).
  bool _auto = false;
  StreamSubscription<void>? _watchSub;
  Timer? _autoTimer;

  /// Dernier contenu synchronisé (dans un sens OU l'autre) — anti-rebond : on
  /// ne re-pousse pas / ne ré-applique pas un texte qu'on vient d'échanger.
  String? _lastSynced;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? ClipboardClient();
    _ownsWatcher = widget.watcher == null;
    _watcher = widget.watcher ?? NativeClipboardWatcher();
    _read = widget.readPhoneClipboard ?? _defaultRead;
    _write = widget.writePhoneClipboard ?? _defaultWrite;
    _load();
  }

  @override
  void dispose() {
    _disableAuto();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  static Future<String?> _defaultRead() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  static Future<void> _defaultWrite(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _client.history(widget.device);
      if (!mounted) return;
      setState(() => _items = items);
    } on ClipboardException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------- auto

  void _toggleAuto(bool on) {
    setState(() => _auto = on);
    if (on) {
      _enableAuto();
    } else {
      _disableAuto();
    }
  }

  Future<void> _enableAuto() async {
    await _watcher.start();
    _watchSub = _watcher.onChanged.listen((_) => _autoPush());
    _autoTimer = Timer.periodic(widget.autoPollInterval, (_) => _autoPull());
  }

  void _disableAuto() {
    _watchSub?.cancel();
    _watchSub = null;
    _autoTimer?.cancel();
    _autoTimer = null;
    if (_ownsWatcher) _watcher.stop();
  }

  /// Le tél vient de copier quelque chose → on le pousse sur le PC.
  Future<void> _autoPush() async {
    final text = (await _read())?.trim();
    if (text == null || text.isEmpty || text == _lastSynced) return;
    _lastSynced = text;
    try {
      await _client.push(widget.device, text);
      if (mounted) await _load();
    } on ClipboardException {
      // best-effort : un échec ponctuel ne casse pas le mode auto.
    }
  }

  /// Tire le presse-papier du PC et l'applique au tél (s'il a changé).
  Future<void> _autoPull() async {
    try {
      final text = (await _client.pullFromPc(widget.device)).trim();
      if (text.isEmpty || text == _lastSynced) return;
      _lastSynced = text;
      await _write(text);
      if (mounted) await _load();
    } on ClipboardException {
      // best-effort
    }
  }

  // ------------------------------------------------------------------- manuel

  Future<void> _sendPhoneClipboard() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = (await _read())?.trim();
    if (text == null || text.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Le presse-papier du téléphone est vide.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      _lastSynced = text;
      await _client.push(widget.device, text);
      messenger.showSnackBar(const SnackBar(content: Text('Envoyé sur le PC ✓')));
      await _load();
      if (mounted && ClipboardItem(id: '', content: text, origin: 'phone').looksLikeUrl) {
        messenger.showSnackBar(SnackBar(
          content: const Text('Ce texte est un lien.'),
          action: SnackBarAction(label: 'Ouvrir sur le PC', onPressed: () => _openLink(text)),
        ));
      }
    } on ClipboardException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteFromPc() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final text = await _client.pullFromPc(widget.device);
      if (text.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Le presse-papier du PC est vide.')),
        );
        return;
      }
      _lastSynced = text.trim();
      await _write(text);
      messenger.showSnackBar(const SnackBar(content: Text('Copié depuis le PC ✓')));
      await _load();
    } on ClipboardException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToPhone(ClipboardItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    _lastSynced = item.content.trim();
    await _write(item.content);
    messenger.showSnackBar(
      const SnackBar(content: Text('Copié dans le presse-papier du téléphone ✓')),
    );
  }

  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _client.openLink(widget.device, url);
      messenger.showSnackBar(const SnackBar(content: Text('Lien ouvert sur le PC ✓')));
    } on ClipboardException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // --------------------------------------------------------------------- vue

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Presse-papier — ${widget.device.pcName}'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            value: _auto,
            onChanged: _toggleAuto,
            title: const Text('Sync auto'),
            subtitle: const Text(
              'Tant que cet écran est ouvert : copie sur le tél → PC, et inversement.',
            ),
            secondary: Icon(_auto ? Icons.sync : Icons.sync_disabled),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _sendPhoneClipboard,
                    icon: const Icon(Icons.upload),
                    label: const Text('Envoyer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pasteFromPc,
                    icon: const Icon(Icons.download),
                    label: const Text('Coller depuis le PC'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _filterBar(),
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
        ],
      ),
    );
  }

  /// Filtre Tout / Envoyés depuis le tél / Reçus du PC (chips défilables).
  Widget _filterBar() {
    Widget chip(String label, _ClipFilter value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          chip('Tout', _ClipFilter.all),
          chip('Envoyés', _ClipFilter.sent),
          chip('Reçus du PC', _ClipFilter.received),
        ],
      ),
    );
  }

  /// Applique le filtre d'origine à la liste chargée.
  List<ClipboardItem> _filtered(List<ClipboardItem> items) {
    switch (_filter) {
      case _ClipFilter.all:
        return items;
      case _ClipFilter.sent:
        return items.where((i) => !i.isFromPc).toList();
      case _ClipFilter.received:
        return items.where((i) => i.isFromPc).toList();
    }
  }

  Widget _buildBody() {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Center(child: Text(_error!, textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      );
    }
    final all = _items ?? const <ClipboardItem>[];
    final items = _filtered(all);
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.content_paste_off, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Center(
            child: Text(all.isEmpty
                ? 'Aucun contenu partagé pour l\'instant.'
                : 'Rien dans ce filtre.'),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Le presse-papier est effacé automatiquement après 2 jours.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        return ListTile(
          leading: Icon(
            item.isFromPc ? Icons.desktop_windows : Icons.phone_android,
            color: item.isFromPc ? Colors.indigo : Colors.green,
          ),
          title: Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.isFromPc ? 'depuis le PC' : 'depuis le téléphone',
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => _copyToPhone(item),
          trailing: item.looksLikeUrl
              ? TextButton(
                  onPressed: () => _openLink(item.content),
                  child: const Text('Ouvrir sur PC'),
                )
              : const Icon(Icons.copy, size: 18),
        );
      },
    );
  }
}
