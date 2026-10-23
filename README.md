# EazyQ (Flutter + Firebase)

## Roles and hierarchy

| Role (`role`) | Designation | Can do |
|---|---|---|
| `deptAdmin` | `hod` | Everything in the department: users, batches, schemes, sessions, run sessions, enter/unlock marks, export |
| `teacher` | `professor` | Define marking schemes, create sessions, run sessions, enter marks, export |
| `teacher` | `assistantProfessor` | Run sessions they are assigned to (examiner), enter marks, export |
| `deptAdmin` | (none/office) | Manage users and batches, export. Cannot edit marks |
| `student` | n/a | See live queue for own batch, own group, own marks (only after published) |

Rules are enforced in `firestore.rules`. `Profile.can()` in `lib/core/roles.dart` only hides UI.

## Firestore model

```
users/{uid}        name, role, designation?, departmentId, rollNo?, branch?, year?, batchId?, fcmTokens[]
batches/{id}       departmentId, branch, year, section
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
2. Create a Firebase project, run `flutterfire configure`, enable Auth (email/password), Firestore, Cloud Messaging.
3. Deploy: `firebase deploy --only firestore:rules,functions`
4. Seed the first HOD manually in the console: create an Auth user, then a `users/{uid}` doc with `role: deptAdmin`, `designation: hod`, `departmentId`. After that, the HOD creates everyone else.
5. Not yet built (next steps): login screen, teacher dashboard (call next / start / finish buttons wired to `QueueService`), admin screens, Excel import (AI column mapping via Cloud Function), Excel export, saving FCM token to `users/{uid}.fcmTokens`.