# EazyQ (Flutter + Firebase)

## Roles and hierarchy

| Role (`role`) | Designation | Can do |
|---|---|---|
| `deptAdmin` | `hod` | Everything in the department: users, batches, schemes, sessions, run sessions, enter/unlock marks, export |
| `teacher` | `professor` | After HOD approval: define marking schemes, create sessions, run assigned sessions, enter marks, export |
| `teacher` | `assistantProfessor` | After HOD approval: run assigned sessions, enter marks, export |
| `deptAdmin` | (none/office) | Manage users and batches, export. Cannot edit marks |
| `student` | n/a | See live queue for own batch, own group, own marks (only after published) |

Rules are enforced in `firestore.rules`. `Profile.can()` in `lib/core/roles.dart` only hides UI. Students can create an active basic account and view their batch's viva sessions before their name is added to a class list. Enrollment is optional at signup. When a teacher imports a spreadsheet or adds a student manually, EazyQ links a matching account and the student becomes identifiable in the queue. Staff applicants also start with basic student access; HOD approval upgrades their account to teacher permissions. Only approved teachers can be assigned to sessions or enter marks.

## Firestore model

```
users/{uid}        name, email, phone, role, requestedRole?, authorizationStatus?, designation?, departmentId, requestedRollNo?, rollNo?, branch?, year?, batchId?, fcmTokens[]
batches/{id}       departmentId, branch, year, section
  roster/{enrollmentNo} name, rollNo, email?, phone?, authUid?, linkedEmail?, linkedPhone?
schemes/{id}       departmentId, name, fields: [{key,label,max}]   // file, viva, practical, attendance, midsem...
sessions/{sid}     departmentId, batchId, schemeId, subject, type(viva|internal|external),
                   room, status(scheduled|live|closed), examinerIds[], avgMinutesPerGroup
  groups/{gid}     number, status(waiting|called|inProgress|done), studentIds[], calledAt
  marks/{studentId} values{key:number}, total, enteredBy, locked, published
```

## Live flow
waiting -> **Call next** (called, push sent, student sees "Go to room NOW") -> **Start** (inProgress) -> **Finish** (done).
The next waiting group gets a "You're next" push. Absent students go to the last group via `callLater`.

## Setup
1. `flutter create .` then `flutter pub get`
2. Create a Firebase project, run `flutterfire configure`, enable Auth (email/password and Google), Firestore, Cloud Messaging. Configure the platform OAuth client for Google sign-in.
3. Deploy the database rules: `firebase deploy --only firestore:rules --project eazyq-e1c17`
4. Seed the first HOD manually in the Firebase Console or with the Admin SDK: create an Auth user, then a `users/{uid}` doc with `role: deptAdmin`, `designation: hod`, `accountStatus: active`, and `departmentId`. HOD status is never available through public self-registration.
5. Students and staff create accounts with email/password or Google and can immediately open the basic portal. Students may enter an enrollment number now or wait until they are added to the class list. Teachers can import Excel/CSV rosters or add a student manually; matching accounts are linked, and rebuilding the session groups allocates queue slots. Staff accounts remain basic until the HOD authorizes them, which upgrades the profile and enables teacher permissions.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
