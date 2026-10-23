import 'package:cloud_firestore/cloud_firestore.dart';

class MarkField {
  final String key, label;
  final double max;
  const MarkField(this.key, this.label, this.max);
  factory MarkField.fromMap(Map<String, dynamic> m) =>
      MarkField(m['key'], m['label'], (m['max'] as num).toDouble());
  Map<String, dynamic> toMap() => {'key': key, 'label': label, 'max': max};
}

class Scheme {
  final String id, name;
  final List<MarkField> fields;
  Scheme(this.id, this.name, this.fields);
  factory Scheme.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) => Scheme(
        d.id,
        d['name'],
        (d['fields'] as List)
            .map((f) => MarkField.fromMap(Map.from(f)))
            .toList(),
      );
}

class Session {
  final String id, subject, batchId, schemeId, status; // scheduled|live|closed
  final String? room;
  final int avgMinutesPerGroup;
  Session.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        subject = d['subject'],
        batchId = d['batchId'],
        schemeId = d['schemeId'],
        status = d['status'],
        room = d.data()!['room'],
        avgMinutesPerGroup = d.data()!['avgMinutesPerGroup'] ?? 10;
}

class Group {
  final String id, status; // waiting|called|inProgress|done
  final int number;
  final List<String> studentIds;
  Group.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        number = d['number'],
        status = d['status'],
        studentIds = List<String>.from(d['studentIds']);
}
