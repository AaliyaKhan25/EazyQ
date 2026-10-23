import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';

class QueueService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _s(String sid) =>
      _db.collection('sessions').doc(sid);
  CollectionReference<Map<String, dynamic>> _g(String sid) =>
      _s(sid).collection('groups');

  /// Split students (already sorted by roll no.) into groups of [size].
  Future<void> buildGroups(
    String sid,
    List<String> sortedStudentIds, {
    int size = 4,
  }) async {
    final b = _db.batch();
    for (var i = 0; i < sortedStudentIds.length; i += size) {
      final n = i ~/ size + 1;
      b.set(_g(sid).doc('g$n'), {
        'number': n,
        'status': 'waiting',
        'studentIds': sortedStudentIds.skip(i).take(size).toList(),
      });
    }
    await b.commit();
  }

  /// Move a student between groups (drag & drop in UI).
  Future<void> moveStudent(
    String sid,
    String studentId,
    String fromG,
    String toG,
  ) => _db.runTransaction((tx) async {
    tx.update(_g(sid).doc(fromG), {
      'studentIds': FieldValue.arrayRemove([studentId]),
    });
    tx.update(_g(sid).doc(toG), {
      'studentIds': FieldValue.arrayUnion([studentId]),
    });
  });

  /// "Call next group": lowest-numbered waiting group becomes `called`.
  /// A Cloud Function reacts to this change and pushes notifications.
  Future<void> callNext(String sid) async {
    final snap = await _g(sid).orderBy('number').get();
    final next = snap.docs.where((d) => d['status'] == 'waiting');
    if (next.isEmpty) return;
    await next.first.reference.update({
      'status': 'called',
      'calledAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> startGroup(String sid, String gid) =>
      _g(sid).doc(gid).update({'status': 'inProgress'});

  Future<void> finishGroup(String sid, String gid) =>
      _g(sid).doc(gid).update({'status': 'done'});

  /// Absent / late students: push them to the last group so nobody blocks the line.
  Future<void> callLater(String sid, String studentId, String fromG) async {
    final last = await _g(sid)
        .orderBy('number', descending: true)
        .limit(1)
        .get();
    if (last.docs.isEmpty) return;
    await moveStudent(sid, studentId, fromG, last.docs.first.id);
  }

  /// Save one student's marks. Scheme fields are validated against their max.
  Future<void> saveMarks(
    String sid,
    String studentId,
    Scheme scheme,
    Map<String, double> values,
    String teacherUid,
  ) {
    for (final f in scheme.fields) {
      final v = values[f.key];
      if (v != null && (v < 0 || v > f.max)) {
        throw ArgumentError('${f.label} must be between 0 and ${f.max}');
      }
    }
    final total = values.values.fold<double>(0, (a, b) => a + b);
    return _s(sid).collection('marks').doc(studentId).set({
      'values': values,
      'total': total,
      'enteredBy': teacherUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'locked': false,
      'published': false,
    }, SetOptions(merge: true));
  }
}
