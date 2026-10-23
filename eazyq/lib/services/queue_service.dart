import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class QueueService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _s(String sid) =>
      _db.collection('sessions').doc(sid);
  CollectionReference<Map<String, dynamic>> _g(String sid) =>
      _s(sid).collection('groups');

  /// Split students (already sorted) into groups of [size].
  /// With [replace] true, existing groups are deleted first.
  Future<void> buildGroups(String sid, List<String> studentIds,
      {int size = 4, bool replace = false}) async {
    final b = _db.batch();
    if (replace) {
      final old = await _g(sid).get();
      for (final d in old.docs) {
        b.delete(d.reference);
      }
    }
    for (var i = 0; i < studentIds.length; i += size) {
      final n = i ~/ size + 1;
      b.set(_g(sid).doc('g$n'), {
        'number': n,
        'status': 'waiting',
        'studentIds': studentIds.skip(i).take(size).toList(),
      });
    }
    await b.commit();
  }

  Future<void> moveStudent(
          String sid, String studentId, String fromG, String toG) =>
      _db.runTransaction((tx) async {
        tx.update(_g(sid).doc(fromG), {
          'studentIds': FieldValue.arrayRemove([studentId])
        });
        tx.update(_g(sid).doc(toG), {
          'studentIds': FieldValue.arrayUnion([studentId])
        });
      });

  /// Lowest-numbered waiting group becomes `called`; session goes `live`.
  Future<void> callNext(String sid) async {
    final snap = await _g(sid).orderBy('number').get();
    final next = snap.docs.where((d) => d['status'] == 'waiting');
    if (next.isEmpty) return;
    await next.first.reference.update({
      'status': 'called',
      'calledAt': FieldValue.serverTimestamp(),
    });
    await _s(sid).update({'status': 'live'});
  }

  Future<void> startGroup(String sid, String gid) =>
      _g(sid).doc(gid).update({'status': 'inProgress'});

  Future<void> finishGroup(String sid, String gid) =>
      _g(sid).doc(gid).update({'status': 'done'});

  /// Absent / late students go to the last group so nobody blocks the line.
  Future<void> callLater(String sid, String studentId, String fromG) async {
    final last =
        await _g(sid).orderBy('number', descending: true).limit(1).get();
    if (last.docs.isEmpty || last.docs.first.id == fromG) return;
    await moveStudent(sid, studentId, fromG, last.docs.first.id);
  }

  /// Save one student's marks. Never touches `published` / `locked` on update.
  Future<void> saveMarks(String sid, String studentId, Scheme scheme,
      Map<String, double> values, String teacherUid) async {
    for (final f in scheme.fields) {
      final v = values[f.key];
      if (v != null && (v < 0 || v > f.max)) {
        throw ArgumentError('${f.label} must be between 0 and ${f.max}');
      }
    }
    final total = values.values.fold<double>(0, (a, b) => a + b);
    final ref = _s(sid).collection('marks').doc(studentId);
    final snap = await ref.get();
    final data = <String, dynamic>{
      'values': values,
      'total': total,
      'enteredBy': teacherUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (snap.exists) {
      await ref.update(data);
    } else {
      await ref.set({...data, 'locked': false, 'published': false});
    }
  }
}
