enum Role { student, teacher, deptAdmin }

enum Designation { hod, professor, assistantProfessor }

enum Perm {
  manageUsers,
  manageBatches,
  defineSchemes,
  createSession,
  runSession, // call groups, start/finish
  enterMarks,
  unlockMarks,
  exportMarks,
  viewDeptMarks,
}

T? _byName<T extends Enum>(List<T> values, String? n) {
  for (final v in values) {
    if (v.name == n) return v;
  }
  return null;
}

class Profile {
  final String uid, name, departmentId;
  final Role role;
  final Designation? designation; // teachers + admins only
  final String? rollNo, branch, batchId;
  final int? year;
  final String accountStatus;

  Profile({
    required this.uid,
    required this.name,
    required this.departmentId,
    required this.role,
    this.designation,
    this.rollNo,
    this.branch,
    this.batchId,
    this.year,
    this.accountStatus = 'active',
  });

  factory Profile.fromMap(String uid, Map<String, dynamic> m) => Profile(
        uid: uid,
        name: m['name'] ?? '',
        departmentId: m['departmentId'] ?? '',
        role: _byName(Role.values, m['role']) ?? Role.student,
        designation: _byName(Designation.values, m['designation']),
        rollNo: m['rollNo'],
        branch: m['branch'],
        batchId: m['batchId'],
        year: m['year'],
        accountStatus: m['accountStatus'] ?? 'active',
      );

  bool get isHod => designation == Designation.hod;

  /// UI-level checks only. Firestore rules are the real enforcement.
  bool can(Perm p) {
    if (role == Role.student) return false;
    if (isHod) return true;
    switch (designation) {
      case Designation.professor:
        return const {
          Perm.defineSchemes,
          Perm.createSession,
          Perm.runSession,
          Perm.enterMarks,
          Perm.exportMarks,
          Perm.viewDeptMarks,
        }.contains(p);
      case Designation.assistantProfessor:
        return const {Perm.runSession, Perm.enterMarks, Perm.exportMarks}
            .contains(p);
      default: // non-HOD dept admin (office staff)
        return const {
          Perm.manageUsers,
          Perm.manageBatches,
          Perm.exportMarks,
          Perm.viewDeptMarks,
        }.contains(p);
    }
  }
}
