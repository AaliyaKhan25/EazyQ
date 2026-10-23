import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';

String _fmt(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// List of marking schemes (the "basis of marking") for the department.
class SchemesScreen extends StatelessWidget {
  final Profile me;
  const SchemesScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    final canEdit = me.can(Perm.defineSchemes);
    final stream = FirebaseFirestore.instance
        .collection('schemes')
        .where('departmentId', isEqualTo: me.departmentId)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Marking schemes')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New scheme'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SchemeEditorScreen(me: me))),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (_, s) {
          if (s.hasError)
            return Center(child: SelectableText('Error: ${s.error}'));
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          if (s.data!.docs.isEmpty) {
            return Center(
                child: Text(canEdit
                    ? 'No schemes yet. Tap "New scheme".'
                    : 'No schemes yet. Ask your HOD or a professor to create one.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: s.data!.docs.map((d) {
              final fields = (d['fields'] as List).cast<Map>();
              final total =
                  fields.fold<double>(0, (a, f) => a + (f['max'] as num));
              return Card(
                child: ListTile(
                  title: Text('${d['name']}  ·  ${_fmt(total)} marks'),
                  subtitle: Text(fields
                      .map((f) => '${f['label']} ${_fmt(f['max'])}')
                      .join(' · ')),
                  trailing: canEdit ? const Icon(Icons.edit) : null,
                  onTap: canEdit
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  SchemeEditorScreen(me: me, existing: d)))
                      : null,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _Row {
  final TextEditingController label;
  final TextEditingController max;
  final String? key; // kept stable for existing parameters
  _Row({String? label, num? max, this.key})
      : label = TextEditingController(text: label),
        max = TextEditingController(text: max == null ? '' : _fmt(max));
}

/// Create or edit a scheme: a name plus any number of parameters,
/// each with its own total marks.
class SchemeEditorScreen extends StatefulWidget {
  final Profile me;
  final DocumentSnapshot<Map<String, dynamic>>? existing;
  const SchemeEditorScreen({super.key, required this.me, this.existing});

  @override
  State<SchemeEditorScreen> createState() => _SchemeEditorScreenState();
}

class _SchemeEditorScreenState extends State<SchemeEditorScreen> {
  final _name = TextEditingController();
  final List<_Row> _rows = [];
  static const _presets = [
    'File',
    'Viva',
    'Practical',
    'Attendance',
    'Midsem',
    'Assignment',
    'Quiz'
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e['name'];
      for (final f in (e['fields'] as List).cast<Map>()) {
        _rows.add(_Row(label: f['label'], max: f['max'], key: f['key']));
      }
    } else {
      _rows.add(_Row());
    }
  }

  String _slug(String s) {
    final k = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return k.isEmpty ? 'field' : k;
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack('Give the scheme a name.');
    final fields = <Map<String, dynamic>>[];
    final used = <String>{};
    for (final r in _rows) {
      final label = r.label.text.trim();
      final max = double.tryParse(r.max.text.trim());
      if (label.isEmpty || max == null || max <= 0) {
        return _snack('Every parameter needs a name and total marks above 0.');
      }
      final base = r.key ?? _slug(label);
      var k = base;
      var i = 2;
      while (used.contains(k)) {
        k = '${base}_$i';
        i++;
      }
      used.add(k);
      fields.add({'key': k, 'label': label, 'max': max});
    }
    if (fields.isEmpty) return _snack('Add at least one parameter.');

    try {
      final col = FirebaseFirestore.instance.collection('schemes');
      if (widget.existing != null) {
        await widget.existing!.reference
            .update({'name': name, 'fields': fields});
      } else {
        await col.add({
          'departmentId': widget.me.departmentId,
          'name': name,
          'fields': fields,
          'createdBy': widget.me.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'New marking scheme' : 'Edit scheme')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
              labelText: 'Scheme name (e.g. DBMS Internal Viva)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        const Text('Quick add'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _presets
              .map((p) => ActionChip(
                    label: Text(p),
                    onPressed: () => setState(() => _rows.add(_Row(label: p))),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _rows[i].label,
                  decoration: const InputDecoration(
                      labelText: 'Parameter', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _rows[i].max,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Total marks', border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _rows.removeAt(i)),
              ),
            ]),
          ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add parameter'),
          onPressed: () => setState(() => _rows.add(_Row())),
        ),
        const Divider(height: 32),
        Text(
          'Total: ${_fmt(_rows.fold<double>(0, (a, r) => a + (double.tryParse(r.max.text.trim()) ?? 0)))} marks',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save scheme')),
      ]),
    );
  }
}
