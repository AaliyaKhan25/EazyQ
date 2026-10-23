import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/roles.dart';
import '../models/models.dart';
import '../services/queue_service.dart';
import 'marks_entry_screen.dart';

String _fmt(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// Live control panel for one session: arrange groups, run the queue,
/// enter marks for each student.
class SessionControlScreen extends StatefulWidget {
  final Profile me;
  final String sessionId;
  const SessionControlScreen(
      {super.key, required this.me, required this.sessionId});

  @override
  State<SessionControlScreen> createState() => _SessionControlScreenState();
}

class _SessionControlScreenState extends State<SessionControlScreen> {
  final _db = FirebaseFirestore.instance;
  final _queue = QueueService();

  Map<String, Map<String, dynamic>> _roster = {};
  Scheme? _scheme;
  bool _ready = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final sd = await _db.collection('sessions').doc(widget.sessionId).get();
      final m = sd.data();
      if (m != null) {
        await _loadRoster(m['batchId']);
        try {
          final sc = await _db.collection('schemes').doc(m['schemeId']).get();
          if (sc.exists) _scheme = Scheme.fromDoc(sc);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadRoster(String batchId) async {
    final snap = await _db.collection('batches/$batchId/roster').get();
    _roster = {for (final d in snap.docs) d.id: d.data()};
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _label(String id) {
    final r = _roster[id];
    if (r == null) return id;
    return '${r['rollNo'] ?? id} · ${r['name'] ?? ''}';
  }

  int _cmp(String a, String b) {
    final ra = '${_roster[a]?['rollNo'] ?? a}',
        rb = '${_roster[b]?['rollNo'] ?? b}';
    final ia = int.tryParse(ra), ib = int.tryParse(rb);
    if (ia != null && ib != null) return ia.compareTo(ib);
    return ra.compareTo(rb);
  }

  Future<void> _build(Session s, int size, {bool replace = false}) async {
    try {
      await _loadRoster(s.batchId);
      if (_roster.isEmpty) {
        _snack('No students in this batch yet. Import a student list first.');
        return;
      }
      final ids = _roster.keys.toList()..sort(_cmp);
      await _queue.buildGroups(s.id, ids, size: size, replace: replace);
      if (mounted) setState(() {});
      _snack('Created groups for ${ids.length} students.');
    } catch (e) {
      _snack('Could not build groups: $e');
    }
  }

  Future<void> _rebuild(Session s, int size) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rebuild groups?'),
        content: const Text(
            'All groups are re-created from the student list and any manual changes are lost. Saved marks are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rebuild')),
        ],
      ),
    );
    if (ok == true) await _build(s, size, replace: true);
  }

  Future<void> _moveTo(
      String sid, String studentId, Group from, List<Group> all) async {
    final target = await showModalBottomSheet<Group>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Move ${_label(studentId)} to…',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final g
                in all.where((g) => g.id != from.id && g.status != 'done'))
              ListTile(
                title: Text('Group ${g.number}'),
                subtitle: Text('${g.studentIds.length} students · ${g.status}'),
                onTap: () => Navigator.pop(context, g),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await _queue.moveStudent(sid, studentId, from.id, target.id);
    } catch (e) {
      _snack('Could not move: $e');
    }
  }

  Future<void> _openMarks(Session s, String studentId) async {
    final ref = _db.collection('schemes').doc(s.schemeId);
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      final d = await ref.get();
      if (d.exists) doc = d;
    } catch (_) {
      // a missing doc is denied by the rules; treat as "not found"
    }

    if (doc == null) {
      if (!mounted) return;
      if (!widget.me.can(Perm.defineSchemes)) {
        _snack(
            'This session has no marking scheme. Ask your HOD or a professor.');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Marking scheme missing'),
          content: const Text(
              'This session points to a scheme that does not exist. Create a default one?\n\nFile 10, Viva 10, Practical 10, Attendance 5, Midsem 15.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create')),
          ],
        ),
      );
      if (ok != true) return;
      await ref.set({
        'departmentId': widget.me.departmentId,
        'name': 'Default scheme',
        'fields': [
          {'key': 'file', 'label': 'File marks', 'max': 10},
          {'key': 'viva', 'label': 'Viva marks', 'max': 10},
          {'key': 'practical', 'label': 'Practical marks', 'max': 10},
          {'key': 'attendance', 'label': 'Attendance marks', 'max': 5},
          {'key': 'midsem', 'label': 'Midsem marks', 'max': 15},
        ],
      });
      doc = await ref.get();
    }

    final scheme = Scheme.fromDoc(doc);
    _scheme = scheme;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarksEntryScreen(
          teacher: widget.me,
          sessionId: s.id,
          studentId: studentId,
          studentName: _label(studentId),
          scheme: scheme,
        ),
      ),
    );
  }

  Future<void> _exportMarksReport(Session session) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await _loadRoster(session.batchId);
      if (_roster.isEmpty) throw StateError('This batch has no student roster yet.');
      final marksSnapshot = await _db
          .collection('sessions/${session.id}/marks')
          .get();
      final marks = {for (final d in marksSnapshot.docs) d.id: d.data()};
      var scheme = _scheme;
      if (scheme == null) {
        final schemeDoc = await _db.collection('schemes').doc(session.schemeId).get();
        if (schemeDoc.exists) scheme = Scheme.fromDoc(schemeDoc);
      }
      final fields = scheme?.fields ?? const <MarkField>[];
      final workbook = Excel.createExcel();
      final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
      final headers = [
        'Enrollment number',
        'Student name',
        ...fields.map((field) => '${field.label} / ${_fmt(field.max)}'),
        'Total',
        'Maximum',
        'Status',
        'Published',
      ];
      sheet.appendRow(headers.map((value) => TextCellValue(value)).toList());
      final ids = _roster.keys.toList()..sort(_cmp);
      for (final id in ids) {
        final roster = _roster[id]!;
        final mark = marks[id];
        final values = mark?['values'] is Map
            ? Map<String, dynamic>.from(mark!['values'] as Map)
            : <String, dynamic>{};
        sheet.appendRow([
          TextCellValue(id),
          TextCellValue('${roster['name'] ?? ''}'),
          ...fields.map((field) {
            final value = values[field.key];
            return value is num
                ? DoubleCellValue(value.toDouble())
                : TextCellValue('');
          }),
          if (mark?['total'] is num)
            DoubleCellValue((mark!['total'] as num).toDouble())
          else
            TextCellValue(''),
          DoubleCellValue(fields.fold<double>(0, (sum, field) => sum + field.max)),
          TextCellValue(mark == null ? 'Not marked' : 'Marked'),
          TextCellValue(mark?['published'] == true ? 'Yes' : 'No'),
        ]);
      }
      final safeSubject = session.subject.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final fileName = 'EazyQ_${safeSubject}_marks.xlsx';
      if (kIsWeb) {
        workbook.save(fileName: fileName);
      } else {
        final bytes = workbook.encode();
        if (bytes == null) throw StateError('Could not build the Excel workbook.');
        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Download marks report',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          bytes: Uint8List.fromList(bytes),
        );
        if (savedPath == null) {
          _snack('Report download canceled.');
          return;
        }
      }
      _snack('Marks report is ready.');
    } catch (e) {
      _snack('Could not export marks report: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sid = widget.sessionId;
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final maxTotal = _scheme?.fields.fold<double>(0, (a, f) => a + f.max);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('sessions').doc(sid).snapshots(),
      builder: (_, ss) {
        if (ss.hasError)
          return Scaffold(
              body: Center(child: SelectableText('Error: ${ss.error}')));
        if (!ss.hasData || !ss.data!.exists) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final session = Session.fromDoc(ss.data!);
        final size = (ss.data!.data()!['groupSize'] as num?)?.toInt() ?? 4;

        return Scaffold(
          appBar: AppBar(title: Text(session.subject), actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rebuild') _rebuild(session, size);
                if (v == 'reload')
                  _loadRoster(session.batchId).then((_) => setState(() {}));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rebuild', child: Text('Rebuild groups')),
                PopupMenuItem(
                    value: 'reload', child: Text('Refresh student names')),
              ],
            ),
          ]),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('sessions/$sid/groups')
                .orderBy('number')
                .snapshots(),
            builder: (_, gs) {
              if (gs.hasError)
                return Center(
                    child: SelectableText('Groups error: ${gs.error}'));
              if (!gs.hasData)
                return const Center(child: CircularProgressIndicator());
              final groups = gs.data!.docs.map(Group.fromDoc).toList();
              final done = groups.where((g) => g.status == 'done').length;
              final waiting = groups.where((g) => g.status == 'waiting').length;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db.collection('sessions/$sid/marks').snapshots(),
                builder: (_, ms) {
                  final totals = <String, num>{
                    if (ms.hasData)
                      for (final d in ms.data!.docs)
                        d.id: (d.data()['total'] as num?) ?? 0
                  };
                  return ListView(padding: const EdgeInsets.all(12), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${session.room ?? 'No room'} · batch ${session.batchId} · ${_roster.length} students'),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                _SessionStat(label: 'Groups', value: '${groups.length}', icon: Icons.groups_rounded, color: const Color(0xFF315CDB)),
                                _SessionStat(label: 'Waiting', value: '$waiting', icon: Icons.hourglass_top_rounded, color: const Color(0xFFE09A26)),
                                _SessionStat(label: 'Completed', value: '$done', icon: Icons.check_circle_rounded, color: const Color(0xFF218A5A)),
                                _SessionStat(label: 'Marked', value: '${totals.length}', icon: Icons.edit_note_rounded, color: const Color(0xFF8057C7)),
                              ]),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _exporting
                                    ? null
                                    : () => _exportMarksReport(session),
                                icon: _exporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download_outlined),
                                label: Text(_exporting
                                    ? 'Preparing report…'
                                    : 'Download marks report'),
                              ),
                              const SizedBox(height: 4),
                              if (groups.isEmpty)
                                FilledButton.icon(
                                  icon: const Icon(Icons.groups),
                                  label: Text('Build groups of $size'),
                                  onPressed: () => _build(session, size),
                                )
                              else
                                FilledButton.icon(
                                  icon: const Icon(Icons.campaign),
                                  label: const Text('Call next group'),
                                  onPressed: waiting == 0
                                      ? null
                                      : () => _queue.callNext(session.id),
                                ),
                            ]),
                      ),
                    ),
                    for (final g in groups)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text('Group ${g.number}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: Text(g.status),
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide.none,
                                    backgroundColor: switch (g.status) {
                                      'called' => Colors.green.shade100,
                                      'inProgress' => Colors.blue.shade100,
                                      'done' => Colors.grey.shade300,
                                      _ => Colors.orange.shade100,
                                    },
                                  ),
                                  const Spacer(),
                                  if (g.status == 'called')
                                    FilledButton(
                                        onPressed: () =>
                                            _queue.startGroup(session.id, g.id),
                                        child: const Text('Start')),
                                  if (g.status == 'inProgress')
                                    FilledButton(
                                        onPressed: () => _queue.finishGroup(
                                            session.id, g.id),
                                        child: const Text('Finish')),
                                ]),
                                for (final id in g.studentIds)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(_label(id)),
                                    subtitle: totals.containsKey(id)
                                        ? Text(
                                            'Marked: ${_fmt(totals[id]!)}${maxTotal != null ? ' / ${_fmt(maxTotal)}' : ''}')
                                        : const Text('Not marked yet'),
                                    onTap: () => _openMarks(session, id),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Enter marks',
                                            icon: Icon(
                                                totals.containsKey(id)
                                                    ? Icons.check_circle
                                                    : Icons.edit_note,
                                                color: totals.containsKey(id)
                                                    ? Colors.green
                                                    : null),
                                            onPressed: () =>
                                                _openMarks(session, id),
                                          ),
                                          PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'move')
                                                _moveTo(
                                                    session.id, id, g, groups);
                                              if (v == 'later')
                                                _queue.callLater(
                                                    session.id, id, g.id);
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'move',
                                                  child:
                                                      Text('Move to group…')),
                                              PopupMenuItem(
                                                  value: 'later',
                                                  child: Text(
                                                      'Send to last group (absent/late)')),
                                            ],
                                          ),
                                        ]),
                                  ),
                              ]),
                        ),
                      ),
                  ]);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _SessionStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SessionStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 95),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 7),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label, style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 10)),
          ]),
        ]),
      );
}
