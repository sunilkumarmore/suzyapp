import 'package:flutter/material.dart';
import '../services/parent_gate_service.dart';

Future<bool> showParentGate(BuildContext context, {bool force = false}) async {
  if (!force && ParentGateService.isUnlocked) return true;

  final challenge = ParentGateService.createChallenge();
  final controller = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Grown-ups only'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What is ${challenge.question}?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Your answer'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final input = int.tryParse(controller.text);
              if (input != null && ParentGateService.verify(input, challenge)) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );

  return ok ?? false;
}
