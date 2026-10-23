import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/roles.dart';

/// HOD-only review queue for staff self-registration requests.
class TeacherApprovalsScreen extends StatelessWidget {
  final Profile me;
  const TeacherApprovalsScreen({super.key, required this.me});

  Future<void> _approve(BuildContext context, String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': 'teacher',
        'authorizationStatus': 'approved',
        'accountStatus': 'active',
        'approvedBy': me.uid,
        'approvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not approve account: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Staff approvals')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('departmentId', isEqualTo: me.departmentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Could not load requests: ${snapshot.error}'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final requests = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              return data['requestedRole'] == 'teacher' && data['authorizationStatus'] != 'approved';
            }).toList();
            if (requests.isEmpty) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_user_outlined, size: 44),
                  SizedBox(height: 12),
                  Text('No staff requests to review', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('New staff accounts will appear here.'),
                ]),
              ));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Review each staff identity. Approval upgrades their basic portal account with teacher tools.',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                for (final doc in requests)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(doc.data()['name'] ?? 'Staff applicant', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('${doc.data()['designation'] ?? 'Staff'} · ${doc.data()['branch'] ?? ''}'),
                        Text(doc.data()['email'] ?? ''),
                        Text(doc.data()['phone'] ?? ''),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => _approve(context, doc.id),
                            icon: const Icon(Icons.check),
                            label: const Text('Authorize as teacher'),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
