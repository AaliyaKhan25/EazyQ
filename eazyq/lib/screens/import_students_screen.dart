import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';

/// Upload an Excel/CSV class list. Columns are matched automatically by
/// their header names; the teacher can correct any mapping before importing.
class ImportStudentsScreen extends StatefulWidget {
  final Profile me;
  const ImportStudentsScreen({super.key, required this.me});

  @override
  State<ImportStudentsScreen> createState() => _ImportStudentsScreenState();
}

class _ImportStudentsScreenState extends State<ImportStudentsScreen> {
  final _db = FirebaseFirestore.instance;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _batches = [];
  String? _batchId; // existing batch id, or '__new__'
  final _branch = TextEditingController();
  final _year = TextEditingController();
  final _section = TextEditingController();

  List<String> _headers = [];
  List<List<String>> _rows = [];
  String? _fileName;
  final Map<String, int?> _map = {
    'name': null,
    'rollNo': null,
    'email': null,
    'phone': null
  };
  bool _busy = false;

  static const _labels = {
    'name': 'Student name *',
    'rollNo': 'Roll number *',
    'email': 'Email (optional)',
    'phone': 'Phone (optional)',
  };
  static const _hints = {
    'name': ['student name', 'name of student', 'full name', 'name'],
    'rollNo': ['roll', 'enrol', 'enroll', 'reg', 'usn', 'seat', 'id'],
    'email': ['email', 'e-mail', 'mail'],
    'phone': ['mobile', 'phone', 'contact', 'mob'],
  };

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final s = await _db
          .collection('batches')
          .where('departmentId', isEqualTo: widget.me.departmentId)
          .get();
      setState(() => _batches = s.docs);
    } catch (e) {
      _snack('Could not load batches: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- file parsing ----------
  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;

    try {
      final table = f.name.toLowerCase().endsWith('.csv')
          ? _parseCsv(utf8.decode(f.bytes!, allowMalformed: true))
          : _parseExcel(f.bytes!);
      final cleaned =
          table.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
      if (cleaned.length < 2) {
        _snack('The file needs a header row and at least one student.');
        return;
      }
      final headers = cleaned.first.map((h) => h.trim()).toList();
      setState(() {
        _fileName = f.name;
        _headers = headers;
        _rows = cleaned.skip(1).toList();
        for (final k in _map.keys) {
          _map[k] = _guess(headers, _hints[k]!);
        }
      });
    } catch (e) {
      _snack('Could not read that file: $e');
    }
  }

  int? _guess(List<String> headers, List<String> patterns) {
    final low = headers.map((h) => h.toLowerCase()).toList();
    for (final p in patterns) {
      final i = low.indexWhere((h) => h.contains(p));
      if (i != -1 && !_map.values.contains(i)) return i;
    }
    return null;
  }

  List<List<String>> _parseExcel(List<int> bytes) {
    final book = Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first]!;
    return sheet.rows
        .map((r) => r.map((c) {
              final v = c?.value;
              if (v == null) return '';
              final s = v.toString();
              return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
            }).toList())
        .toList();
  }

  List<List<String>> _parseCsv(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell = StringBuffer();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  // ---------- import ----------
  String _val(List<String> r, String field) {
    final i = _map[field];
    if (i == null || i >= r.length) return '';
    return r[i].trim();
  }

  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  bool get _ready {
    if (_rows.isEmpty || _map['name'] == null || _map['rollNo'] == null)
      return false;
    if (_batchId == null) return false;
    if (_batchId == '__new__') {
      return _branch.text.trim().isNotEmpty &&
          int.tryParse(_year.text.trim()) != null &&
          _section.text.trim().isNotEmpty;
    }
    return true;
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      var batchId = _batchId!;
      if (batchId == '__new__') {
        batchId = _slug('${_branch.text}-${_year.text}-${_section.text}');
        await _db.collection('batches').doc(batchId).set({
          'departmentId': widget.me.departmentId,
          'branch': _branch.text.trim(),
          'year': int.parse(_year.text.trim()),
          'section': _section.text.trim(),
        }, SetOptions(merge: true));
      }

      final seen = <String>{};
      final entries = <String, Map<String, dynamic>>{};
      var skipped = 0;
      for (final r in _rows) {
        final name = _val(r, 'name');
        final roll = _val(r, 'rollNo').replaceAll('/', '-');
        final email = _val(r, 'email').toLowerCase();
        final phone = _val(r, 'phone');
        if (name.isEmpty || roll.isEmpty || !seen.add(roll)) {
          skipped++;
          continue;
        }
        entries[roll] = {
          'name': name,
          'rollNo': roll,
          'email': email,
          'phone': phone,
          'importedAt': FieldValue.serverTimestamp(),
        };
      }

      final ids = entries.keys.toList();
      for (var i = 0; i < ids.length; i += 400) {
        final b = _db.batch();
        for (final id in ids.skip(i).take(400)) {
          b.set(_db.collection('batches/$batchId/roster').doc(id), entries[id]!,
              SetOptions(merge: true));
        }
        await b.commit();
      }

      await _linkExistingAccounts(batchId, entries);
      await _allocateQueueSlots(batchId, entries.keys.toList());

      _snack('Imported ${entries.length} students into "$batchId"'
          '${skipped > 0 ? ' ($skipped rows skipped: required fields were blank or enrollment numbers were duplicated.)' : ''}.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkExistingAccounts(
      String batchId, Map<String, Map<String, dynamic>> entries) async {
    if (entries.isEmpty) return;
    final users = await _db
        .collection('users')
        .where('departmentId', isEqualTo: widget.me.departmentId)
        .get();
    final students = users.docs.where((d) {
      final p = d.data();
      return p['role'] == 'student' && p['requestedRole'] != 'teacher' && p['batchId'] == batchId;
    }).toList();
    final roster = await _db.collection('batches/$batchId/roster').get();
    final rosterById = {for (final d in roster.docs) d.id: d.data()};
    final links = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final entry in entries.entries) {
      final id = entry.key;
      final row = entry.value;
      final byRoll = students.where((d) {
        final p = d.data();
        return (p['rollNo'] == id || p['requestedRollNo'] == id) &&
            (p['name'] ?? '').toString().trim().toLowerCase() ==
                (row['name'] ?? '').toString().trim().toLowerCase();
      }).toList();
      final matches = byRoll.isNotEmpty
          ? byRoll
          : students.where((d) {
              final p = d.data();
              return p['rollNo'] == null && p['requestedRollNo'] == null &&
                  (p['name'] ?? '').toString().trim().toLowerCase() ==
                      (row['name'] ?? '').toString().trim().toLowerCase();
            }).toList();
      final alreadyLinked = rosterById[id]?['authUid'];
      if (matches.length == 1 &&
          (alreadyLinked == null || alreadyLinked == matches.single.id)) {
        links[id] = matches.single;
      }
    }

    final ids = links.keys.toList();
    // Rules validate each profile against its roster row via getAfter(); keep
    // each atomic link small enough for Firestore's rules access-call limit.
    for (var i = 0; i < ids.length; i += 10) {
      final b = _db.batch();
      for (final id in ids.skip(i).take(10)) {
        final link = MapEntry(id, links[id]!);
        final uid = link.value.id;
        final profile = link.value.data();
        b.set(
          _db.doc('batches/$batchId/roster/${link.key}'),
          {
            'authUid': uid,
            'linkedEmail': profile['email'] ?? '',
            'linkedPhone': profile['phone'] ?? '',
            'linkedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (profile['rollNo'] == null) {
          b.update(_db.collection('users').doc(uid), {'rollNo': link.key});
        }
      }
      await b.commit();
    }
  }

  Future<void> _allocateQueueSlots(String batchId, List<String> addedIds) async {
    if (addedIds.isEmpty) return;
    final sessions = await _db
        .collection('sessions')
        .where('batchId', isEqualTo: batchId)
        .where('departmentId', isEqualTo: widget.me.departmentId)
        .get();
    final roster = await _db.collection('batches/$batchId/roster').get();
    final allStudentIds = roster.docs.map((d) => d.id).toList()..sort();

    for (final sessionDoc in sessions.docs) {
      final session = sessionDoc.data();
      if (!['scheduled', 'live'].contains(session['status'])) continue;
      try {
        final groupsRef = _db.collection('sessions/${sessionDoc.id}/groups');
        final groups = await groupsRef.orderBy('number').get();
        final size = ((session['groupSize'] as num?)?.toInt() ?? 4).clamp(1, 100).toInt();
        final actions = <({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data, bool update})>[];

        if (groups.docs.isEmpty) {
          for (var i = 0; i < allStudentIds.length; i += size) {
            final number = i ~/ size + 1;
            actions.add((ref: groupsRef.doc('g$number'), update: false, data: {
              'number': number,
              'status': 'waiting',
              'studentIds': allStudentIds.skip(i).take(size).toList(),
            }));
          }
        } else {
          final assigned = groups.docs
              .expand((d) => List<String>.from(d.data()['studentIds'] ?? []))
              .toSet();
          final pending = addedIds.where((id) => !assigned.contains(id)).toList();
          final additions = <String, List<String>>{};
          var lastNumber = groups.docs
              .map((d) => (d.data()['number'] as num?)?.toInt() ?? 0)
              .fold<int>(0, (max, n) => n > max ? n : max);

          for (final studentId in pending) {
            final waiting = groups.docs.where((d) {
              final data = d.data();
              final current = List<String>.from(data['studentIds'] ?? []);
              return data['status'] == 'waiting' &&
                  current.length + (additions[d.id]?.length ?? 0) < size;
            }).firstOrNull;
            if (waiting != null) {
              additions.putIfAbsent(waiting.id, () => []).add(studentId);
            } else {
              lastNumber++;
              actions.add((ref: groupsRef.doc('g$lastNumber'), update: false, data: {
                'number': lastNumber,
                'status': 'waiting',
                'studentIds': [studentId],
              }));
            }
          }
          for (final addition in additions.entries) {
            actions.add((ref: groupsRef.doc(addition.key), update: true, data: {
              'studentIds': FieldValue.arrayUnion(addition.value),
            }));
          }
        }
        for (var i = 0; i < actions.length; i += 400) {
          final b = _db.batch();
          for (final action in actions.skip(i).take(400)) {
            if (action.update) {
              b.update(action.ref, action.data);
            } else {
              b.set(action.ref, action.data);
            }
          }
          await b.commit();
        }
      } catch (_) {
        // An unassigned teacher may import a roster but cannot alter this session's queue.
      }
    }
  }

  Future<void> _addManually() async {
    if (_batchId == null || _batchId == '__new__') {
      _snack('Choose an existing branch and year first.');
      return;
    }
    final name = TextEditingController();
    final roll = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a student'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Student name')),
          const SizedBox(height: 12),
          TextField(controller: roll, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Enrollment number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final cleanName = name.text.trim();
            final cleanRoll = roll.text.trim().replaceAll('/', '-');
            if (cleanName.isNotEmpty && cleanRoll.isNotEmpty) {
              Navigator.pop(dialogContext, {'name': cleanName, 'rollNo': cleanRoll});
            }
          }, child: const Text('Add to class list')),
        ],
      ),
    );
    name.dispose();
    roll.dispose();
    if (result == null) return;

    setState(() => _busy = true);
    try {
      final batchId = _batchId!;
      final entry = {
        'name': result['name']!,
        'rollNo': result['rollNo']!,
        'email': '',
        'phone': '',
        'importedAt': FieldValue.serverTimestamp(),
      };
      await _db.doc('batches/$batchId/roster/${result['rollNo']}')
          .set(entry, SetOptions(merge: true));
      await _linkExistingAccounts(batchId, {result['rollNo']!: entry});
      await _allocateQueueSlots(batchId, [result['rollNo']!]);
      _snack('Added ${result['name']} to the class list. Their queue slot is ready for eligible sessions.');
    } catch (e) {
      _snack('Could not add student: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _batchLabel(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return '${m['branch'] ?? ''} · Year ${m['year'] ?? ''} · ${m['section'] ?? ''}  (${d.id})';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import student list')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('1. Choose the batch',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _batchId,
          isExpanded: true,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: 'Batch'),
          items: [
            for (final d in _batches)
              DropdownMenuItem(
                  value: d.id,
                  child: Text(_batchLabel(d), overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(
                value: '__new__', child: Text('+ Create new batch')),
          ],
          onChanged: (v) => setState(() => _batchId = v),
        ),
        if (_batchId == '__new__') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _branch,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Branch', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Year', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _section,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Section', border: OutlineInputBorder()))),
          ]),
        ],
        const SizedBox(height: 24),
        Text('2. Upload the class list (.xlsx or .csv)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Import a class list once, or add a student manually. Matching portal accounts are linked automatically; students can sign in before they are added.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add one student manually'),
          onPressed: _busy ? null : _addManually,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: Text(_fileName ?? 'Choose file'),
          onPressed: _pick,
        ),
        if (_headers.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('3. Check the column match',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              '${_rows.length} rows found. Fix any column that was matched wrongly.'),
          const SizedBox(height: 8),
          for (final k in _map.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<int?>(
                value: _map[k],
                isExpanded: true,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(), labelText: _labels[k]),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— not in file —')),
                  for (var i = 0; i < _headers.length; i++)
                    DropdownMenuItem<int?>(
                        value: i,
                        child: Text(_headers[i].isEmpty
                            ? 'Column ${i + 1}'
                            : _headers[i])),
                ],
                onChanged: (v) => setState(() => _map[k] = v),
              ),
            ),
          const SizedBox(height: 8),
          Text('Preview', style: Theme.of(context).textTheme.titleSmall),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Roll no.')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Phone')),
              ],
              rows: _rows
                  .take(5)
                  .map((r) => DataRow(cells: [
                        DataCell(Text(_val(r, 'rollNo'))),
                        DataCell(Text(_val(r, 'name'))),
                        DataCell(Text(_val(r, 'email'))),
                        DataCell(Text(_val(r, 'phone'))),
                      ]))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text('Import ${_rows.length} students'),
            onPressed: _ready && !_busy ? _import : null,
          ),
        ],
      ]),
    );
  }
}
