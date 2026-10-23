// Notifies students when their group is called, and warns the next group.
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

async function tokensFor(studentIds) {
  const snaps = await Promise.all(studentIds.map((id) => db.doc(`users/${id}`).get()));
  return snaps.flatMap((s) => (s.exists ? s.data().fcmTokens || [] : []));
}

async function push(studentIds, title, body) {
  const tokens = await tokensFor(studentIds);
  if (!tokens.length) return;
  await admin.messaging().sendEachForMulticast({ tokens, notification: { title, body } });
}

exports.onGroupStatus = onDocumentUpdated("sessions/{sid}/groups/{gid}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status || after.status !== "called") return;

  const session = (await db.doc(`sessions/${event.params.sid}`).get()).data();
  const room = session.room || "the viva room";

  await push(after.studentIds, "Your turn!", `Group ${after.number}: please go to ${room} now.`);

  // heads-up for the next waiting group
  const groups = await db.collection(`sessions/${event.params.sid}/groups`).orderBy("number").get();
  const next = groups.docs.find((d) => d.data().status === "waiting");
  if (next) {
    await push(next.data().studentIds, "You're next",
      `Group ${next.data().number}: be near ${room}.`);
  }
});