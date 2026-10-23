import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';
import 'create_session_screen.dart';
import 'import_students_screen.dart';
import 'schemes_screen.dart';
import 'session_control_screen.dart';

/// Home for HOD, professors and assistant professors.
class StaffDashboard extends StatelessWidget {
  final Profile me;
  const StaffDashboard({super.key, required this.me});

  String get _title {
    switch (me.designation) {
      case Designation.hod:
        return 'HOD';
      case Designation.professor:
        return 'Professor';
      case Designation.assistantProfessor:
        return 'Asst. Professor';
      default:
        return 'Admin';
    }
  }

  void _go(BuildContext c, Widget w) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('sessions')
        .where('departmentId', isEqualTo: me.departmentId)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text('${me.name} · $_title'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.rule),
                label: const Text('Marking schemes'),
                onPressed: () => _go(context, SchemesScreen(me: me)),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Import students'),
                onPressed: () => _go(context, ImportStudentsScreen(me: me)),
              ),
              if (me.can(Perm.createSession))
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New session'),
                  onPressed: () => _go(context, CreateSessionScreen(me: me)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('Sessions', style: Theme.of(context).textTheme.titleMedium),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (_, s) {
            if (s.hasError) return SelectableText('Error: ${s.error}');
            if (!s.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()));
            }
            var docs = s.data!.docs;
            if (me.role == Role.teacher && !me.isHod) {
              docs = docs.where((d) {
                final ex = d.data()['examinerIds'];
                return ex is List && ex.contains(me.uid);
              }).toList();
            }
            if (docs.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(24), child: Text('No sessions yet.'));
            }
            return Column(
              children: docs.map((d) {
                final m = d.data();
                return Card(
                  child: ListTile(
                    title: Text(m['subject'] ?? 'Untitled session'),
                    subtitle: Text(
                        '${m['room'] ?? 'No room'} · ${m['type'] ?? ''} · ${m['status'] ?? ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _go(
                        context, SessionControlScreen(me: me, sessionId: d.id)),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ]),
    );
  }
}
