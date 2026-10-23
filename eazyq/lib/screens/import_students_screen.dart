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
        if (name.isEmpty || roll.isEmpty || !seen.add(roll)) {
          skipped++;
          continue;
        }
        entries[roll] = {
          'name': name,
          'rollNo': roll,
          'email': _val(r, 'email'),
          'phone': _val(r, 'phone'),
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

      _snack('Imported ${entries.length} students into "$batchId"'
          '${skipped > 0 ? ' ($skipped rows skipped: blank or duplicate roll no.)' : ''}.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Import failed: $e');
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
              ],
              rows: _rows
                  .take(5)
                  .map((r) => DataRow(cells: [
                        DataCell(Text(_val(r, 'rollNo'))),
                        DataCell(Text(_val(r, 'name'))),
                        DataCell(Text(_val(r, 'email'))),
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
