import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';
import '../models/models.dart';
import '../services/queue_service.dart';

/// Marks form built from the session's scheme. Pre-fills saved marks.
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
    for (final f in widget.scheme.fields) f.key: TextEditingController()
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  Future<void> _loadExisting() async {
    try {
      final d = await FirebaseFirestore.instance
          .doc('sessions/${widget.sessionId}/marks/${widget.studentId}')
          .get();
      final v = d.data()?['values'];
      if (v is Map) {
        v.forEach((k, val) {
          if (val is num) _c[k]?.text = _fmt(val);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final values = <String, double>{};
    for (final f in widget.scheme.fields) {
      final t = _c[f.key]!.text.trim();
      if (t.isEmpty) continue;
      final v = double.tryParse(t);
      if (v == null) {
        _snack('${f.label}: "$t" is not a number');
        return;
      }
      values[f.key] = v;
    }
    try {
      await QueueService().saveMarks(widget.sessionId, widget.studentId,
          widget.scheme, values, widget.teacher.uid);
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (e) {
      _snack(e.message.toString());
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxTotal = widget.scheme.fields.fold<double>(0, (a, f) => a + f.max);
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(widget.scheme.name,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              for (final f in widget.scheme.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _c[f.key],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: '${f.label} (out of ${_fmt(f.max)})',
                        border: const OutlineInputBorder()),
                  ),
                ),
              ListenableBuilder(
                listenable: Listenable.merge(_c.values.toList()),
                builder: (_, __) {
                  final total = _c.values
                      .map((c) => double.tryParse(c.text.trim()) ?? 0)
                      .fold<double>(0, (a, b) => a + b);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text('Total: ${_fmt(total)} / ${_fmt(maxTotal)}',
                        style: Theme.of(context).textTheme.titleMedium),
                  );
                },
              ),
              FilledButton(onPressed: _save, child: const Text('Save marks')),
            ]),
    );
  }
}
