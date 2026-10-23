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
          if (!s.hasData)
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('Error: ${s.error}')));
          if (s.data!.docs.isEmpty) {
            return const Center(
              child: Text('No viva scheduled for your batch.'),
            );
          }
          return ListView(
            children: s.data!.docs
                .map((d) => _SessionCard(me: me, session: Session.fromDoc(d)))
                .toList(),
          );
        },
      ),
    );
  }
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

        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.subject,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    headline,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Now inside: ${inside != null ? 'Group ${inside.number}' : '-'}',
                ),
                Text(
                  'Called: ${called != null ? 'Group ${called.number}' : '-'}',
                ),
                Text(
                  'Your group: ${mine != null ? 'Group ${mine.number}' : '-'}',
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: all
                      .map(
                        (g) => Chip(
                          label: Text('G${g.number}'),
                          backgroundColor: switch (g.status) {
                            'inProgress' => Colors.blue.shade100,
                            'called' => Colors.green.shade100,
                            'done' => Colors.grey.shade300,
                            _ => null,
                          },
                          side: g.id == mine?.id
                              ? const BorderSide(width: 2)
                              : null,
                        ),
                      )
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
