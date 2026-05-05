import 'package:flutter/material.dart';
import 'package:emacs_text_field/emacs_text_field.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'EmacsTextField Example',
      home: ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EmacsTextField Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key bindings:  C-a/e line  ·  C-f/b char  ·  C-n/p line  '
              '·  M-f/b word\n'
              'C-k kill  ·  C-y yank  ·  C-w kill-sel  ·  M-Enter bullet  '
              '·  C-c d date',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // Fixed-height example (expands: false, minLines: 5).
            EmacsTextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                hintText: 'Type here — Emacs key bindings active',
              ),
            ),
            const SizedBox(height: 24),
            // Expanding example.
            const Text('Expanding variant (expands: true inside Expanded):'),
            const SizedBox(height: 8),
            Expanded(
              child: EmacsTextField(
                controller: TextEditingController(),
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Fills available space',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
