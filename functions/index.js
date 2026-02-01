const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// --- ⚡ 1. THE AUTO-GRANT WELCOME (Immediate AI Access) ---
// This handles your "Crew Release" needs. As soon as a user signs in, 
// they get AI access and a token wallet initialized.
exports.autoApproveNewUser = onDocumentCreated({
    document: "users/{userId}",
    region: "asia-south1" 
}, async (event) => {
    const userId = event.params.userId;
    const db = admin.firestore();

    logger.log(`🚀 S.INC: New Architect detected: ${userId}. Initializing Beta Access...`);

    return db.collection('users').doc(userId).set({
        isBetaApproved: true,     // Grant access instantly for the 12-person crew
        tokens_used: 0,           // Initialize the AI budget
        status: 'active',
        deletion_pending: false 
    }, { merge: true });
});

// --- 🧹 2. THE MIDNIGHT JANITOR (Nightly Purge) ---
// This runs at 00:00 UTC and wipes users who haven't aborted their deletion.
exports.midnightPurge = onSchedule("0 0 * * *", async (event) => {
    const db = admin.firestore();
    const auth = admin.auth();

    logger.log("🕵️ S.INC Janitor: Starting nightly sweep in the 'users' ledger...");

    const snapshot = await db.collection('users')
        .where('deletion_pending', '==', true)
        .get();

    if (snapshot.empty) {
        logger.log("✅ S.INC: No accounts marked for purge.");
        return null;	
    }

    const batch = db.batch();
    const authDeletions = [];

    for (const doc of snapshot.docs) {
        const uid = doc.id;
        
        // Wipe User Profile (and their tasks array)
        batch.delete(db.collection('users').doc(uid));
        
        // Wipe Beta Request history
        batch.delete(db.collection('beta_requests').doc(uid));
        
        // Delete from Firebase Auth list
        authDeletions.push(
            auth.deleteUser(uid).catch((e) => logger.error(`Auth Error for ${uid}:`, e))
        );
    }

    await Promise.all([batch.commit(), ...authDeletions]);
    logger.log(`☢️ S.INC: Successfully purged ${snapshot.size} decommissioned accounts.`);
});