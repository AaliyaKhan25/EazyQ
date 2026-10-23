import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ApprovalPendingScreen extends StatelessWidget {
  const ApprovalPendingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.hourglass_top_rounded, size: 52, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 18),
                Text('Waiting for HOD approval', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Your staff account cannot access queues or marks until your department HOD authorizes it.', textAlign: TextAlign.center),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ]),
            ),
          ),
        ),
      );
}
