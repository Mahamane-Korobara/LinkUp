import 'package:flutter/material.dart';

import '../../config/linkup_ports.dart';
import '../../utils/address_validators.dart';

/// Résultat du dialog de saisie manuelle : IP + port du bridge.
class ManualAgentInput {
  final String address;
  final int bridgePort;

  ManualAgentInput({required this.address, required this.bridgePort});
}

/// Dialog de saisie manuelle d'un agent (T1.17 du plan).
/// Affiche un formulaire IPv4 / hostname `.local` + port avec validation stricte.
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
              validator: validateAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: 'Port du bridge',
                hintText: '${LinkupPorts.bridge}',
              ),
              keyboardType: TextInputType.number,
              validator: validatePort,
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
