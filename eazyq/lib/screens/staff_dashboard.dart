import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';
import 'create_session_screen.dart';
import 'import_students_screen.dart';
import 'schemes_screen.dart';
import 'session_control_screen.dart';
import 'teacher_approvals_screen.dart';

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
        title: const Text('EazyQ'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
        _StaffWelcome(name: me.name, title: _title),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick actions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
              if (me.isHod)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Staff approvals'),
                  onPressed: () => _go(context, TeacherApprovalsScreen(me: me)),
                ),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Sessions', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 4),
        Text('Select a session to manage its live queue and marks.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF667085),
                )),
        const SizedBox(height: 8),
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  child: Column(children: [
                    Icon(Icons.event_busy_outlined,
                        size: 36, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    const Text('No sessions yet',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Create a session to get your queue started.'),
                  ]),
                ),
              );
            }
            return Column(
              children: docs.map((d) {
                final m = d.data();
                final status = (m['status'] ?? 'scheduled').toString();
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: status == 'live'
                              ? const [Color(0xFFD6F7E6), Color(0xFFB9EFD2)]
                              : [Theme.of(context).colorScheme.primaryContainer, Colors.white],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(status == 'live' ? Icons.graphic_eq_rounded : Icons.assignment_rounded,
                          color: status == 'live' ? const Color(0xFF18864B) : Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(m['subject'] ?? 'Untitled session',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text('${m['room'] ?? 'Room not set'} · ${m['type'] ?? ''}'),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: status == 'live' ? const Color(0xFFE7F6EE) : const Color(0xFFF0F2F6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (status == 'live') ...[
                              const Icon(Icons.circle, size: 7, color: Color(0xFF18864B)),
                              const SizedBox(width: 5),
                            ],
                            Text(status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: status == 'live' ? const Color(0xFF18864B) : const Color(0xFF596579),
                              )),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () => _go(context, SessionControlScreen(me: me, sessionId: d.id)),
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

class _StaffWelcome extends StatelessWidget {
  final String name, title;
  const _StaffWelcome({required this.name, required this.title});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2942), Color(0xFF315CDB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF315CDB).withOpacity(.18), blurRadius: 20, offset: const Offset(0, 9))],
        ),
        child: Stack(children: [
          Positioned(right: -22, top: -26, child: Icon(Icons.dashboard_customize_rounded, size: 130, color: Colors.white.withOpacity(.08))),
          Row(children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.white.withOpacity(.15),
              foregroundColor: Colors.white,
              child: Icon(title == 'HOD' ? Icons.admin_panel_settings_rounded : Icons.person_rounded, size: 27),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('GOOD TO SEE YOU', style: TextStyle(color: Color(0xFFCFDAF5), fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('$title · Department workspace', style: const TextStyle(color: Color(0xFFDDE6FF), fontSize: 13)),
            ])),
            const SizedBox(width: 8),
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD780), size: 23),
          ]),
        ]),
      );
}
