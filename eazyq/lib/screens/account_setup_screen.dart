import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Completes a basic portal account. Students and staff applicants can view
/// their batch portal; staff tools are enabled only after HOD approval.
class AccountSetupScreen extends StatefulWidget {
  final User user;
  const AccountSetupScreen({super.key, required this.user});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final _db = FirebaseFirestore.instance;
  final _name = TextEditingController();
  final _enrollment = TextEditingController();
  final _phone = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _batches = [];
  String? _batchId;
  String _kind = 'student';
  String _designation = 'assistantProfessor';
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  @override
  void dispose() {
    _name.dispose();
    _enrollment.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadBatches() async {
    try {
      final snap = await _db.collection('batches').get();
      if (!mounted) return;
      setState(() {
        _batches = snap.docs;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load branches: $e'; });
    }
  }

  String _normalizeEnrollment(String value) =>
      value.trim().replaceAll('/', '-');

  Future<void> _submit() async {
    final email = widget.user.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) {
      setState(() => _error = 'This sign-in did not provide an email address. Use an email account or a Google account with an email address.');
      return;
    }
    if (_batchId == null) {
      setState(() => _error = 'Choose your branch and year.');
      return;
    }
    final batch = _batches.firstWhere((b) => b.id == _batchId!);
    final batchData = batch.data();
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Enter your name and phone number.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final profile = <String, dynamic>{
        'name': name,
        'email': email,
        'phone': phone,
        'departmentId': batchData['departmentId'],
        'branch': batchData['branch'],
        'year': batchData['year'],
        'accountStatus': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final write = _db.batch();
      if (_kind == 'student') {
        profile.addAll({
          'role': 'student',
          'batchId': batch.id,
        });
        final rollNo = _normalizeEnrollment(_enrollment.text);
        if (rollNo.isNotEmpty) profile['requestedRollNo'] = rollNo;
        write.set(_db.collection('users').doc(widget.user.uid), profile);
      } else {
        profile.addAll({
          'role': 'student',
          'requestedRole': 'teacher',
          'designation': _designation,
          'authorizationStatus': 'pending',
          'batchId': batch.id,
        });
        write.set(_db.collection('users').doc(widget.user.uid), profile);
      }
      await write.commit();
      if (_kind == 'student') {
        final rollNo = _normalizeEnrollment(_enrollment.text);
        if (rollNo.isNotEmpty) {
          try {
            await _db.doc('batches/${batch.id}/roster/$rollNo').update({
              'authUid': widget.user.uid,
              'linkedEmail': email,
              'linkedPhone': phone,
              'linkedAt': FieldValue.serverTimestamp(),
            });
            await _db.collection('users').doc(widget.user.uid).update({
              'rollNo': rollNo,
            });
          } catch (_) {
            // A missing or non-matching roster row does not block basic portal access.
          }
        }
      }
    } catch (e) {
      final message = e.toString();
      if (mounted) {
        setState(() => _error = message.contains('permission-denied')
            ? 'Could not save your account. Check the selected branch and year, then make sure the latest Firestore rules are deployed.'
            : message.replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final batches = _batches.where((b) => b.data()['departmentId'] != null).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your account'),
        actions: [IconButton(tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
            Text('One quick setup', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Signed in as ${widget.user.email ?? 'Google account'}'),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'student', label: Text('Student'), icon: Icon(Icons.school_outlined)),
                ButtonSegment(value: 'staff', label: Text('Staff'), icon: Icon(Icons.badge_outlined)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() { _kind = s.first; _error = null; }),
            ),
            const SizedBox(height: 18),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _batchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Branch · year · section', prefixIcon: Icon(Icons.account_tree_outlined)),
              items: batches.map((b) {
                final d = b.data();
                return DropdownMenuItem(value: b.id, child: Text('${d['branch']} · Year ${d['year']} · ${d['section'] ?? ''}', overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (value) => setState(() => _batchId = value),
            ),
            if (_kind == 'student') ...[
              const SizedBox(height: 12),
              TextField(controller: _enrollment, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Enrollment number (optional)', prefixIcon: Icon(Icons.confirmation_number_outlined))),
              const SizedBox(height: 10),
              const Text('You can use the portal now. Enrollment is optional and can be linked to your timetable when your teacher adds you to the class list.'),
            ] else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _designation,
                decoration: const InputDecoration(labelText: 'Staff designation'),
                items: const [
                  DropdownMenuItem(value: 'professor', child: Text('Professor')),
                  DropdownMenuItem(value: 'assistantProfessor', child: Text('Assistant professor')),
                ],
                onChanged: (v) => setState(() => _designation = v!),
              ),
              const SizedBox(height: 10),
              const Text('You can use the basic student portal while your request is reviewed. HOD approval upgrades your account to teacher tools.'),
            ],
            if (batches.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('No branch lists have been imported yet. Ask your department to set up a batch first.')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            FilledButton(onPressed: _saving || batches.isEmpty ? null : _submit, child: Text(_saving ? 'Saving…' : 'Complete setup')),
          ]),
        ),
      ),
    );
  }
}
