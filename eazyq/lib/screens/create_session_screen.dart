import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';

/// Create a viva / internal / external session: pick the batch, the marking
/// scheme, the examiners, room and group size.
class CreateSessionScreen extends StatefulWidget {
  final Profile me;
  const CreateSessionScreen({super.key, required this.me});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _db = FirebaseFirestore.instance;
  final _subject = TextEditingController();
  final _room = TextEditingController();
  final _minutes = TextEditingController(text: '10');
  final _groupSize = TextEditingController(text: '4');

  String _type = 'viva';
  String? _batchId, _schemeId;
  final Set<String> _examiners = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _batches = [],
      _schemes = [],
      _teachers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dept = widget.me.departmentId;
      final b = await _db
          .collection('batches')
          .where('departmentId', isEqualTo: dept)
          .get();
      final s = await _db
          .collection('schemes')
          .where('departmentId', isEqualTo: dept)
          .get();
      final u = await _db
          .collection('users')
          .where('departmentId', isEqualTo: dept)
          .get();
      setState(() {
        _batches = b.docs;
        _schemes = s.docs;
        _teachers = u.docs.where((d) => d.data()['role'] == 'teacher').toList();
        if (widget.me.role == Role.teacher) _examiners.add(widget.me.uid);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty) return _snack('Enter a subject.');
    if (_batchId == null) return _snack('Choose a batch.');
    if (_schemeId == null) return _snack('Choose a marking scheme.');
    final size = int.tryParse(_groupSize.text.trim());
    final mins = int.tryParse(_minutes.text.trim());
    if (size == null || size < 1) return _snack('Group size must be a number.');
    if (mins == null || mins < 1)
      return _snack('Minutes per group must be a number.');
    try {
      await _db.collection('sessions').add({
        'departmentId': widget.me.departmentId,
        'subject': _subject.text.trim(),
        'type': _type,
        'room': _room.text.trim().isEmpty ? null : _room.text.trim(),
        'batchId': _batchId,
        'schemeId': _schemeId,
        'status': 'scheduled',
        'avgMinutesPerGroup': mins,
        'groupSize': size,
        'examinerIds': _examiners.toList(),
        'createdBy': widget.me.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Could not create session: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
          appBar: AppBar(title: const Text('New session')),
          body: Center(child: SelectableText('Error: $_error')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('New session')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _subject,
            decoration: const InputDecoration(
                labelText: 'Subject (e.g. DBMS Viva)',
                border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _type,
          decoration: const InputDecoration(
              labelText: 'Type', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'viva', child: Text('Viva')),
            DropdownMenuItem(value: 'internal', child: Text('Internal exam')),
            DropdownMenuItem(value: 'external', child: Text('External exam')),
          ],
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _batchId,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: _batches.isEmpty
                  ? 'Batch (none yet: import a student list first)'
                  : 'Batch',
              border: const OutlineInputBorder()),
          items: _batches.map((d) {
            final m = d.data();
            return DropdownMenuItem(
                value: d.id,
                child: Text(
                    '${m['branch']} · Year ${m['year']} · ${m['section']}',
                    overflow: TextOverflow.ellipsis));
          }).toList(),
          onChanged: (v) => setState(() => _batchId = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _schemeId,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: _schemes.isEmpty
                  ? 'Marking scheme (none yet: create one first)'
                  : 'Marking scheme',
              border: const OutlineInputBorder()),
          items: _schemes
              .map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(d['name'], overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _schemeId = v),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _room,
            decoration: const InputDecoration(
                labelText: 'Room (e.g. Lab 3)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _groupSize,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Students per group',
                      border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Minutes per group',
                      border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 16),
        Text('Examiners', style: Theme.of(context).textTheme.titleSmall),
        const Text(
            'Examiners can run the queue and enter marks. The HOD always can.'),
        const SizedBox(height: 6),
        if (_teachers.isEmpty)
          const Text('No teacher accounts found in this department yet.'),
        Wrap(
          spacing: 8,
          children: _teachers.map((d) {
            final sel = _examiners.contains(d.id);
            return FilterChip(
              label: Text(d['name'] ?? d.id),
              selected: sel,
              onSelected: (v) => setState(
                  () => v ? _examiners.add(d.id) : _examiners.remove(d.id)),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('Create session')),
      ]),
    );
  }
}
