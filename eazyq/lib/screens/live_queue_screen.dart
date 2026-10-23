import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/roles.dart';
import '../models/models.dart';

/// What a student sees: which group is inside, which group they are,
/// how many groups are ahead, and a clear "go to the room now" banner.
class LiveQueueScreen extends StatelessWidget {
  final Profile me;
  const LiveQueueScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    final sessions = FirebaseFirestore.instance
        .collection('sessions')
        .where('batchId', isEqualTo: me.batchId)
        .where('status', whereIn: ['scheduled', 'live']).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('My viva queue'), actions: [
        IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut()),
      ]),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: sessions,
        builder: (_, s) {
          if (s.hasError)
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('Error: ${s.error}')));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              _StudentWelcome(me: me, sessionCount: s.data!.docs.length),
              const SizedBox(height: 14),
              if (s.data!.docs.isEmpty)
                const _EmptyVivaState()
              else ...[
                Text('Your sessions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Queue updates appear here automatically.', style: TextStyle(color: Colors.blueGrey.shade600)),
                const SizedBox(height: 8),
                ...s.data!.docs.map((d) => _SessionCard(me: me, session: Session.fromDoc(d))),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StudentWelcome extends StatelessWidget {
  final Profile me;
  final int sessionCount;
  const _StudentWelcome({required this.me, required this.sessionCount});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF315CDB), Color(0xFF7048C8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF315CDB).withOpacity(.2), blurRadius: 22, offset: const Offset(0, 10))],
        ),
        child: Stack(children: [
          Positioned(right: -24, top: -28, child: Icon(Icons.school_rounded, size: 130, color: Colors.white.withOpacity(.09))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(.18),
                foregroundColor: Colors.white,
                child: Text(me.name.isEmpty ? 'S' : me.name[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('STUDENT PORTAL', style: TextStyle(color: Color(0xFFDDE6FF), fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                Text('Hi, ${me.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(30)),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF7EF0B3), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            Text('${me.branch ?? 'Your branch'}  ·  ${me.year == null ? 'Year' : 'Year ${me.year}'}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            Text('$sessionCount upcoming or live ${sessionCount == 1 ? 'session' : 'sessions'}', style: const TextStyle(color: Color(0xFFDDE6FF))),
          ]),
        ]),
      );
}

class _EmptyVivaState extends StatelessWidget {
  const _EmptyVivaState();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
          child: Column(children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.event_available_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('You’re all caught up', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('New viva sessions for your batch will show up here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey.shade600)),
          ]),
        ),
      );
}

class _SessionCard extends StatelessWidget {
  final Profile me;
  final Session session;
  const _SessionCard({required this.me, required this.session});

  @override
  Widget build(BuildContext context) {
    final groups = FirebaseFirestore.instance
        .collection('sessions/${session.id}/groups')
        .orderBy('number')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: groups,
      builder: (_, s) {
        if (!s.hasData)
          return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText('Groups error: ${s.error}'));
        final all = s.data!.docs.map(Group.fromDoc).toList();
        final mine =
            all.where((g) => me.rollNo != null && g.studentIds.contains(me.rollNo)).firstOrNull;
        final inside = all.where((g) => g.status == 'inProgress').firstOrNull;
        final called = all.where((g) => g.status == 'called').firstOrNull;
        final ahead = mine == null
            ? 0
            : all
                .where((g) => g.number < mine.number && g.status != 'done')
                .length;

        String headline;
        Color color;
        if (mine == null) {
          headline = 'You are not assigned to a group yet.';
          color = Colors.grey;
        } else if (mine.status == 'called') {
          headline = 'Go to ${session.room ?? 'the viva room'} NOW';
          color = Colors.green;
        } else if (mine.status == 'inProgress') {
          headline = 'Your group is inside';
          color = Colors.blue;
        } else if (mine.status == 'done') {
          headline = 'Your viva is complete';
          color = Colors.grey;
        } else if (ahead <= 1) {
          headline = "You're next. Stay near the room.";
          color = Colors.orange;
        } else {
          headline =
              '$ahead groups ahead (~${ahead * session.avgMinutesPerGroup} min)';
          color = Colors.indigo;
        }

        final colorScheme = Theme.of(context).colorScheme;
        final statusIcon = switch (mine?.status) {
          'called' => Icons.campaign_rounded,
          'inProgress' => Icons.play_circle_fill_rounded,
          'done' => Icons.check_circle_rounded,
          _ when mine == null => Icons.person_add_alt_1_rounded,
          _ when ahead <= 1 => Icons.notifications_active_rounded,
          _ => Icons.hourglass_top_rounded,
        };
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(15)),
                    child: Icon(Icons.record_voice_over_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(session.subject, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${session.room ?? 'Room to be announced'} · ${session.status.toUpperCase()}', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
                  ])),
                  Icon(Icons.chevron_right_rounded, color: Colors.blueGrey.shade300),
                ]),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutBack,
                  child: Container(
                    key: ValueKey('$headline-${mine?.status}'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withOpacity(.16), color.withOpacity(.07)]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withOpacity(.18)),
                    ),
                    child: Row(children: [
                      Icon(statusIcon, color: color, size: 25),
                      const SizedBox(width: 12),
                      Expanded(child: Text(headline, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color))),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _QueueInfoPill(icon: Icons.meeting_room_outlined, text: 'Inside ${inside != null ? 'G${inside.number}' : '—'}'),
                  _QueueInfoPill(icon: Icons.campaign_outlined, text: 'Called ${called != null ? 'G${called.number}' : '—'}'),
                  _QueueInfoPill(icon: Icons.groups_2_outlined, text: 'Your group ${mine != null ? 'G${mine.number}' : '—'}'),
                ]),
                const Divider(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: all
                      .map((g) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          child: Chip(
                          avatar: Icon(switch (g.status) {
                            'inProgress' => Icons.play_arrow_rounded,
                            'called' => Icons.notifications_active_outlined,
                            'done' => Icons.check_rounded,
                            _ => Icons.more_horiz_rounded,
                          }, size: 17),
                          label: Text('Group ${g.number}'),
                          backgroundColor: switch (g.status) {
                            'inProgress' => Colors.blue.shade50,
                            'called' => Colors.green.shade50,
                            'done' => Colors.grey.shade200,
                            _ => Colors.orange.shade50,
                          },
                          side: g.id == mine?.id
                              ? BorderSide(width: 1.5, color: colorScheme.primary)
                              : BorderSide.none,
                        ),
                      ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueueInfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _QueueInfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF3F5F9), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.blueGrey.shade600),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
