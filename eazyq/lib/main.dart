import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/roles.dart';
import 'firebase_options.dart';
import 'screens/live_queue_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(home: AuthGate()));
}

/// Routes by role after login.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (_, auth) {
          if (auth.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final user = auth.data;
          if (user == null) return const LoginScreen();

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(),
            builder: (_, snap) {
              if (snap.hasError) {
                return Scaffold(
                    body: Center(child: Text('Error: ${snap.error}')));
              }
              if (!snap.hasData) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              if (!snap.data!.exists) {
                return Scaffold(
                  body: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Account not registered. Contact your department admin.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        child: const Text('Log out'),
                      ),
                    ]),
                  ),
                );
              }
              final me = Profile.fromMap(user.uid, snap.data!.data()!);
              switch (me.role) {
                case Role.student:
                  return LiveQueueScreen(me: me);
                case Role.teacher:
                  return _Placeholder(title: 'TODO: teacher dashboard');
                case Role.deptAdmin:
                  return _Placeholder(title: 'TODO: admin dashboard');
              }
            },
          );
        },
      );
}

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('EazyQ'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
        ),
        body: Center(child: Text(title)),
      );
}
