import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';
import '../models/models.dart';
import '../services/queue_service.dart';
import 'marks_entry_screen.dart';

/// Live control panel for one viva / exam session.
class SessionControlScreen extends StatelessWidget {
  final Profile me;
  final String sessionId;
  SessionControlScreen({super.key, required this.me, required this.sessionId});

  final _db = FirebaseFirestore.instance;
  final _queue = QueueService();

  void _snack(BuildContext c, String msg) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _buildGroups(BuildContext c, Session s) async {
    try {
      final snap = await _db
          .collection('users')
          .where('departmentId', isEqualTo: me.departmentId)
          .where('batchId', isEqualTo: s.batchId)
          .get();
      final students = snap.docs
          .where((d) => d.data()['role'] == 'student')
          .toList()
        ..sort((a, b) =>
            '${a.data()['rollNo']}'.compareTo('${b.data()['rollNo']}'));
      if (students.isEmpty) {
        if (c.mounted) _snack(c, 'No students found for batch "${s.batchId}".');
        return;
      }
      await _queue.buildGroups(s.id, students.map((d) => d.id).toList(),
          size: 4);
      if (c.mounted)
        _snack(c, 'Created groups for ${students.length} students.');
    } catch (e) {
      if (c.mounted) _snack(c, 'Could not build groups: $e');
    }
  }

  Future<void> _openMarks(
      BuildContext c, Session s, String studentId, String name) async {
    final ref = _db.collection('schemes').doc(s.schemeId);
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      final d = await ref.get();
      if (d.exists) doc = d;
    } catch (_) {
      // reading a missing doc is denied by the rules; treat as "not found"
    }

    if (doc == null) {
      if (!c.mounted) return;
      if (!me.can(Perm.defineSchemes)) {
        _snack(c,
            'No marking scheme yet. Ask your HOD or professor to create one.');
        return;
      }
      final ok = await showDialog<bool>(
        context: c,
        builder: (_) => AlertDialog(
          title: const Text('No marking scheme'),
          content: const Text(
              'Create a default scheme?\n\nFile 10, Viva 10, Practical 10, Attendance 5, Midsem 15.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Create')),
          ],
        ),
      );
      if (ok != true) return;
      await ref.set({
        'departmentId': me.departmentId,
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

    if (!c.mounted) return;
    Navigator.push(
      c,
      MaterialPageRoute(
        builder: (_) => MarksEntryScreen(
          teacher: me,
          sessionId: s.id,
          studentId: studentId,
          studentName: name,
          scheme: Scheme.fromDoc(doc!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionStream = _db.collection('sessions').doc(sessionId).snapshots();
    final groupsStream = _db
        .collection('sessions/$sessionId/groups')
        .orderBy('number')
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: sessionStream,
      builder: (_, ss) {
        if (ss.hasError) {
          return Scaffold(
              body: Center(child: SelectableText('Error: ${ss.error}')));
        }
        if (!ss.hasData || !ss.data!.exists) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final session = Session.fromDoc(ss.data!);

        return Scaffold(
          appBar: AppBar(title: Text(session.subject)),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: groupsStream,
            builder: (_, gs) {
              if (gs.hasError) {
                return Center(
                    child: SelectableText('Groups error: ${gs.error}'));
              }
              if (!gs.hasData)
                return const Center(child: CircularProgressIndicator());
              final groups = gs.data!.docs.map(Group.fromDoc).toList();
              final done = groups.where((g) => g.status == 'done').length;
              final waiting = groups.where((g) => g.status == 'waiting').length;

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${session.room ?? 'No room'} · batch ${session.batchId}'),
                            const SizedBox(height: 4),
                            Text(
                                'Done $done / ${groups.length} · $waiting waiting'),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              if (groups.isEmpty)
                                FilledButton.icon(
                                  icon: const Icon(Icons.groups),
                                  label: const Text('Build groups of 4'),
                                  onPressed: () =>
                                      _buildGroups(context, session),
                                ),
                              if (groups.isNotEmpty)
                                FilledButton.icon(
                                  icon: const Icon(Icons.campaign),
                                  label: const Text('Call next group'),
                                  onPressed: waiting == 0
                                      ? null
                                      : () => _queue.callNext(session.id),
                                ),
                            ]),
                          ]),
                    ),
                  ),
                  for (final g in groups)
                    _GroupCard(
                      group: g,
                      onStart: () => _queue.startGroup(session.id, g.id),
                      onFinish: () => _queue.finishGroup(session.id, g.id),
                      onMarks: (id, name) =>
                          _openMarks(context, session, id, name),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _GroupCard extends StatefulWidget {
  final Group group;
  final VoidCallback onStart, onFinish;
  final void Function(String id, String name) onMarks;
  const _GroupCard({
    required this.group,
    required this.onStart,
    required this.onFinish,
    required this.onMarks,
  });

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late Future<Map<String, String>> _names = _load();

  Future<Map<String, String>> _load() async {
    final out = <String, String>{};
    await Future.wait(widget.group.studentIds.map((id) async {
      try {
        final d =
            await FirebaseFirestore.instance.collection('users').doc(id).get();
        final m = d.data();
        out[id] =
            m == null ? id : '${m['rollNo'] ?? ''} ${m['name'] ?? id}'.trim();
      } catch (_) {
        out[id] = id; // placeholder ids or no permission
      }
    }));
    return out;
  }

  @override
  void didUpdateWidget(covariant _GroupCard old) {
    super.didUpdateWidget(old);
    if (old.group.studentIds.join(',') != widget.group.studentIds.join(',')) {
      _names = _load();
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'called':
        return Colors.green;
      case 'inProgress':
        return Colors.blue;
      case 'done':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Group ${g.number}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            Chip(
              label: Text(g.status),
              backgroundColor: _color(g.status).withOpacity(.15),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            if (g.status == 'called')
              FilledButton(
                  onPressed: widget.onStart, child: const Text('Start')),
            if (g.status == 'inProgress')
              FilledButton(
                  onPressed: widget.onFinish, child: const Text('Finish')),
          ]),
          FutureBuilder<Map<String, String>>(
            future: _names,
            builder: (_, snap) {
              final names = snap.data ?? {};
              return Column(
                children: g.studentIds
                    .map((id) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(names[id] ?? id),
                          trailing: IconButton(
                            tooltip: 'Enter marks',
                            icon: const Icon(Icons.edit_note),
                            onPressed: () =>
                                widget.onMarks(id, names[id] ?? id),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ]),
      ),
    );
  }
}
