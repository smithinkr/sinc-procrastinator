const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

if (!admin.apps.length) {
    admin.initializeApp();
}

// --- ⚡ 1. THE AUTO-GRANT WELCOME ---
exports.autoApproveNewUser = onDocumentCreated({
    document: "users/{userId}",
    region: "asia-south1" 
}, async (event) => {
    const userId = event.params.userId;
    const db = admin.firestore();
    logger.log(`🚀 S.INC: New Architect detected: ${userId}`);
    return db.collection('users').doc(userId).set({
        isBetaApproved: true,
        tokens_used: 0,
        status: 'active',
        deletion_pending: false 
    }, { merge: true });
});

// --- 🧹 THE MIDNIGHT JANITOR (Purge & Token Reset) ---
exports.midnightJanitor = onSchedule({
    schedule: "0 0 * * *",
    timeZone: "Asia/Kolkata", // Added your specific time zone!
    region: "asia-south1"
}, async (event) => {
    const db = admin.firestore();
    const auth = admin.auth();
    const usersRef = db.collection('users');
    const snapshot = await usersRef.get();

    if (snapshot.empty) return null;

    const batch = db.batch();
    const authDeletions = [];
    let purgeCount = 0;
    let refreshCount = 0;

    snapshot.forEach((doc) => {
        const userData = doc.data();
        if (userData.deletion_pending === true) {
            batch.delete(usersRef.doc(doc.id));
            authDeletions.push(auth.deleteUser(doc.id).catch(e => logger.error(e)));
            purgeCount++;
        } else {
            // Resetting tokens_used to 0
            batch.update(usersRef.doc(doc.id), { tokens_used: 0 });
            refreshCount++;
        }
    });

    await batch.commit();
    await Promise.all(authDeletions);
    
    logger.log(`☢️ S.INC Summary: Purged ${purgeCount}. 💎 Refreshed ${refreshCount}.`);
});