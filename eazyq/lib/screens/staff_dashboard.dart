import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';
import 'session_control_screen.dart';

/// Home screen for HOD, professors and assistant professors.
/// HOD / admins see every session in the department;
/// teachers see only sessions where they are an examiner.
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (_, s) {
          if (s.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('Error: ${s.error}')));
          }
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());

          var docs = s.data!.docs;
          if (me.role == Role.teacher && !me.isHod) {
            docs = docs.where((d) {
              final ex = d.data()['examinerIds'];
              return ex is List && ex.contains(me.uid);
            }).toList();
          }
          if (docs.isEmpty) {
            return const Center(
                child: Text('No sessions assigned to you yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: docs.map((d) {
              final m = d.data();
              return Card(
                child: ListTile(
                  title: Text(m['subject'] ?? 'Untitled session'),
                  subtitle: Text(
                      '${m['room'] ?? 'No room'} · ${m['type'] ?? ''} · ${m['status'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SessionControlScreen(me: me, sessionId: d.id),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
