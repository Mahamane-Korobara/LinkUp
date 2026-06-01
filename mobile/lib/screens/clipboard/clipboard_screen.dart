import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/clipboard/clipboard_client.dart';
import '../../services/pairing/paired_device_store.dart';

/// Lit le presse-papier du téléphone (injectable pour les widget tests).
typedef PhoneClipboardReader = Future<String?> Function();

/// Écrit dans le presse-papier du téléphone (injectable pour les widget tests).
typedef PhoneClipboardWriter = Future<void> Function(String text);

/// Écran presse-papier + lien rapide (S5).
///
/// - « Envoyer » : lit le presse-papier du tél et le pousse sur le PC. Android
///   impose une action utilisateur (lecture du presse-papier interdite en
///   arrière-plan depuis Android 10) — d'où le bouton plutôt qu'un auto-sync.
/// - « Coller depuis le PC » : récupère le presse-papier du PC et le met dans
///   celui du tél.
/// - Historique : derniers contenus échangés ; tap = recopier sur le tél, et
///   un lien http(s) peut être ouvert directement sur le PC.
class ClipboardScreen extends StatefulWidget {
  final PairedDevice device;
  final ClipboardClient? client;
  final PhoneClipboardReader? readPhoneClipboard;
  final PhoneClipboardWriter? writePhoneClipboard;

  const ClipboardScreen({
    super.key,
    required this.device,
    this.client,
    this.readPhoneClipboard,
    this.writePhoneClipboard,
  });

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  late final ClipboardClient _client;
  late final bool _ownsClient;
  late final PhoneClipboardReader _read;
  late final PhoneClipboardWriter _write;

  List<ClipboardItem>? _items;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? ClipboardClient();
    _read = widget.readPhoneClipboard ?? _defaultRead;
    _write = widget.writePhoneClipboard ?? _defaultWrite;
    _load();
  }

  @override
  void dispose() {
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

  /// Lit le presse-papier du tél (action utilisateur) et le pousse sur le PC.
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

  /// Récupère le presse-papier du PC et le met dans celui du tél.
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
          Padding(
            padding: const EdgeInsets.all(12),
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
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
        ],
      ),
    );
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
    final items = _items ?? const [];
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.content_paste_off, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Center(child: Text('Aucun contenu partagé pour l\'instant.')),
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
