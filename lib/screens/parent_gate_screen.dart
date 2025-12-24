import 'dart:math';
import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';

class ParentGateScreen extends StatefulWidget {
  const ParentGateScreen({super.key});

  @override
  State<ParentGateScreen> createState() => _ParentGateScreenState();
}

class _ParentGateScreenState extends State<ParentGateScreen> {
  final _controller = TextEditingController();
  final _rand = Random();

  late int a;
  late int b;

  String? _error;

  @override
  void initState() {
    super.initState();
    _regen();
  }

  void _regen() {
    a = 2 + _rand.nextInt(8); // 2..9
    b = 2 + _rand.nextInt(8); // 2..9
    _controller.clear();
    _error = null;
    setState(() {});
  }

  void _submit() {
    final text = _controller.text.trim();
    final val = int.tryParse(text);

    if (val == null) {
      setState(() => _error = 'Please enter a number.');
      return;
    }

    if (val == a + b) {
      Navigator.pushReplacementNamed(context, '/parent-summary');
      return;
    }

    setState(() => _error = 'Not quite. Try again.');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Parents'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.large),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.large),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                    color: Colors.black.withOpacity(0.08),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 44, color: AppColors.textSecondary),
                  const SizedBox(height: AppSpacing.medium),
                  const Text(
                    'Parent Check',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    'Answer this to continue:',
                    style: TextStyle(color: AppColors.textSecondary.withOpacity(0.9)),
                  ),
                  const SizedBox(height: AppSpacing.large),

                  Text(
                    '$a + $b = ?',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.medium),

                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter answer',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.large),
                        borderSide: BorderSide.none,
                      ),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),

                  const SizedBox(height: AppSpacing.large),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _regen,
                          child: const Text('New Question'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.medium),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submit,
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
