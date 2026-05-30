import 'package:flutter/material.dart';

import '../../config/linkup_ports.dart';

/// Résultat du dialog de saisie manuelle : IP + port du bridge.
class ManualAgentInput {
  final String address;
  final int bridgePort;

  ManualAgentInput({required this.address, required this.bridgePort});
}

/// Dialog de saisie manuelle d'un agent (T1.17 du plan).
/// Affiche un formulaire IPv4 / hostname + port avec validation stricte.
class ManualAgentDialog extends StatefulWidget {
  const ManualAgentDialog({super.key});

  @override
  State<ManualAgentDialog> createState() => _ManualAgentDialogState();
}

class _ManualAgentDialogState extends State<ManualAgentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '${LinkupPorts.bridge}');

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Saisie manuelle'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'IP locale du PC',
                hintText: '192.168.1.42',
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
              validator: _validateAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: 'Port du bridge',
                hintText: '${LinkupPorts.bridge}',
              ),
              keyboardType: TextInputType.number,
              validator: _validatePort,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(
                ManualAgentInput(
                  address: _addressController.text.trim(),
                  bridgePort: int.parse(_portController.text.trim()),
                ),
              );
            }
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

// Validation IPv4 stricte (0.0.0.0 – 255.255.255.255) ou hostname mDNS de
// type `pc.local`. Refuse les chaînes arbitraires comme « foobar » qui
// passaient l'ancienne regex permissive.
final _ipv4Regex = RegExp(
  r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
  r'(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
);
final _hostnameRegex = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}(\.local)?$');

String? _validateAddress(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Adresse requise';
  if (!_ipv4Regex.hasMatch(v) && !_hostnameRegex.hasMatch(v)) {
    return 'Format invalide (ex: 192.168.1.10 ou pc.local)';
  }
  return null;
}

String? _validatePort(String? value) {
  final n = int.tryParse(value?.trim() ?? '');
  if (n == null || n <= 0 || n > 65535) {
    return 'Port entre 1 et 65535';
  }
  return null;
}
