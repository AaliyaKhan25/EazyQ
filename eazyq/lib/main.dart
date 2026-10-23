import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/roles.dart';
import 'firebase_options.dart';
import 'screens/live_queue_screen.dart';
import 'screens/login_screen.dart';
import 'screens/account_setup_screen.dart';
import 'screens/approval_pending_screen.dart';
import 'screens/staff_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const EazyQApp());
}

class EazyQApp extends StatelessWidget {
  const EazyQApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EazyQ',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF315CDB),
            brightness: Brightness.light,
            surface: const Color(0xFFF8F9FC),
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF5F7FB),
            foregroundColor: Color(0xFF182230),
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE8ECF3)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDCE2EC)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDCE2EC)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF315CDB), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        home: const AuthGate(),
      );
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

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
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
                return AccountSetupScreen(user: user);
              }
              final userData = snap.data!.data()!;
              final me = Profile.fromMap(user.uid, userData);
              final basicStaffPending = me.role == Role.teacher &&
                  me.accountStatus == 'pending' &&
                  userData['authorizationStatus'] == 'pending';
              if (me.accountStatus != 'active' && !basicStaffPending) {
                return const ApprovalPendingScreen();
              }
              switch (me.role) {
                case Role.student:
                  return LiveQueueScreen(me: me);
                case Role.teacher:
                  if (basicStaffPending) return LiveQueueScreen(me: me);
                  return StaffDashboard(me: me);
                case Role.deptAdmin:
                  return StaffDashboard(me: me);
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
