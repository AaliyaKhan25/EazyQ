import 'package:flutter/material.dart';

import '../core/roles.dart';
import '../models/models.dart';
import '../services/queue_service.dart';

/// Marks form built dynamically from the scheme (file, viva, practical,
/// attendance, midsem... whatever the professor/HOD configured).
class MarksEntryScreen extends StatefulWidget {
  final Profile teacher;
  final String sessionId, studentId, studentName;
  final Scheme scheme;
  const MarksEntryScreen({
    super.key,
    required this.teacher,
    required this.sessionId,
    required this.studentId,
    required this.studentName,
    required this.scheme,
  });

  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.scheme.fields) f.key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final values = <String, double>{};
    for (final f in widget.scheme.fields) {
      final t = _c[f.key]!.text.trim();
      if (t.isNotEmpty) values[f.key] = double.parse(t);
    }
    try {
      await QueueService().saveMarks(
        widget.sessionId,
        widget.studentId,
        widget.scheme,
        values,
        widget.teacher.uid,
      );
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.studentName)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final f in widget.scheme.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _c[f.key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '${f.label} (max ${f.max.toStringAsFixed(0)})',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            FilledButton(onPressed: _save, child: const Text('Save marks')),
          ],
        ),
      );
}
