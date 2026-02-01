  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:google_sign_in/google_sign_in.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:procrastinator/utils/logger.dart';
  import '../models/task_model.dart';
  import '../services/storage_service.dart';
  

  class SyncService {
    // Add this line to ensure only ONE instance exists
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
    final FirebaseAuth _auth = FirebaseAuth.instance;
    final FirebaseFirestore _db = FirebaseFirestore.instance;
    
    // 1. Enhanced Scopes: Explicitly requesting 'profile' ensures the photo URL is sent
   // 🛡️ S.INC SHIELD: Modern 2026 Constructor
// 🛡️ S.INC SHIELD: Explicit generic type initialization
// ✅ USE THE MODERN SINGLETON
// 🛡️ S.INC SHIELD: We use the Singleton instance 
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
    // 2. Track Last Sync locally for the UI to display
    static DateTime? lastSyncedAt;

    Future<String?> getUserId() async {
      return _auth.currentUser?.uid;
    }

    // 🛡️ S.INC SHIELD: The "Handshake" Guard
  bool _isInitialized = false;

  
Future<void> _ensureInitialized() async {
  if (!_isInitialized) {
    L.d("🛡️ S.INC: Preparing Google Auth Handshake...");
    await _googleSignIn.initialize(
      // 🔥 YOUR CLIENT ID GOES HERE ONCE 
      serverClientId: '31245559081-i1mjcihhc5fr6edobt1vdh00um0ve0ra.apps.googleusercontent.com',
    );
    _isInitialized = true;
  }
}
  Future<User?> signInWithGoogle() async {
  try {
    await _ensureInitialized();
    // 🛡️ S.INC SHIELD: Mandatory 2026 Warm-up
    // 1. THE AUTOMATIC RE-ENTRY (No UI)
    // This looks for an existing session. If found, it skips the modal logic.
    GoogleSignInAccount? googleUser = await _googleSignIn.attemptLightweightAuthentication();

    // 2. THE MODAL FALLBACK (Only for fresh logins)
    if (googleUser == null) {
      L.d("☁️ S.INC: No cached session. Triggering UI Handshake...");
      
      
      // ✅ In v7.0+, authenticate() returns non-null or throws. 
      // This is why the compiler called your previous null-check "Dead Code".
      googleUser = await _googleSignIn.authenticate();
    }

  

    // 🛡️ S.INC SHIELD: Since authenticate() can throw rather than return null,
    // we handle the "User Backed Out" logic in the 'catch' block below.

    // 3. THE 2026 AUTHORIZATION STEP
    final auth = await googleUser.authorizationClient.authorizeScopes([
      'email', 
      'openid', 
      'https://www.googleapis.com/auth/userinfo.profile'
    ]);

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken, // 👈 Uses 'auth' variable
      idToken: googleUser.authentication.idToken,
    );

    // 4. SECURE FIREBASE SESSION (Keep this!)
    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    final User? firebaseUser = userCredential.user;
    
    if (firebaseUser != null) {
  final userDoc = await _db.collection('users').doc(firebaseUser.uid).get();
  final bool isInLimbo = userDoc.exists && (userDoc.data()?['deletion_pending'] ?? false);

  // 🛡️ S.INC SHIELD: If in Limbo, skip the 'last_active' update.
  // This prevents the login from triggering a PERMISSION_DENIED.
  if (!isInLimbo) {
    await _db.collection('users').doc(firebaseUser.uid).set({
      'email': firebaseUser.email,
      'displayName': firebaseUser.displayName,
      'photoUrl': firebaseUser.photoURL,
      'last_active': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } else {
    L.d("⏳ S.INC: User in Limbo. Skipping profile sync to avoid rule conflict.");
  }

      // 💾 STORAGE SERVICE (Keep this!)
      await StorageService.saveAuthHint(
        initial: (firebaseUser.displayName ?? "U")[0].toUpperCase(), 
        isActive: true, 
        photoUrl: googleUser.photoUrl,
      );
    }

    return firebaseUser;
  } catch (e) {
    // Catch-all for "User closed modal" or "No SHA-1 match"
    L.d("🚨 S.INC Auth Error: $e");
    return null;
  }
}


    Future<void> signOut() async {
      await _googleSignIn.signOut();
      await _auth.signOut();
      lastSyncedAt = null; // Reset on logout
    }

    // 3. SECURE PUSH: Reconciles local and cloud data to prevent wipes
    Future<void> syncTasksToCloud(List<Task> localTasks) async {
  final User? user = _auth.currentUser;
  if (user == null) return;

  try {
    // 🔥 THE FIX: Stop fetching and merging cloudTasks.
    // If we want a task gone, we just don't include it in this list.
    final taskData = localTasks.map((t) => t.toMap()).toList();

    // We use .set with merge: true for the document, but since we 
    // provide the full 'tasks' list, it REPLACES the old list entirely.
    await _db.collection('users').doc(user.uid).set({
      'email': user.email,
      'lastSync': FieldValue.serverTimestamp(),
      'tasks': taskData, 
    }, SetOptions(merge: true));

    lastSyncedAt = DateTime.now();
    L.d("☁️ S.INC: Cloud Ledger reconciled (Authoritative).");
  } catch (e) {
    L.d("🚨 Cloud Sync Failed: $e");
  }
}
Future<void> requestAccountDeletion() async {
  final User? user = _auth.currentUser;
  if (user == null) return;

  final String uid = user.uid;

  try {
    L.d("⏳ S.INC: Initializing Soft Limbo for $uid...");

    // 🛡️ S.INC SHIELD: The Unified Limbo Update
    // We consolidate everything into the 'users' collection.
    await _db.collection('users').doc(uid).set({
      'deletion_pending': true,
      'deletion_requested_at': FieldValue.serverTimestamp(),
      'status': 'limbo',
      'isBetaApproved': false, // 🔥 THE ATOMIC FLICK: Kill AI instantly
    }, SetOptions(merge: true));

    L.d("☢️ S.INC: Account decommissioning active. AI services suspended.");
    
  } catch (e) {
    L.d("🚨 S.INC Deletion Request Failure: $e");
    rethrow;
  }
}
Future<void> abortAccountDeletion() async {
  final User? user = _auth.currentUser;
  if (user == null) return;

  try {
    L.d("🟢 S.INC: Attempting Deletion Abort for ${user.uid}...");

    // 🛡️ S.INC SHIELD: The Surgical Update
    // We ONLY send the fields whitelisted in Path B of your rules.
    // If you add 'last_active' or 'email' here, it will trigger PERMISSION_DENIED.
    await _db.collection('users').doc(user.uid).update({
      'deletion_pending': false,
      'status': 'active',
      'last_active': FieldValue.serverTimestamp(), // ✅ Re-enable activity here
      'deletion_requested_at': FieldValue.delete(), // Clears the cloud timer
    });

    L.d("✅ S.INC: Account successfully restored.");
  } catch (e) {
    L.d("🚨 S.INC Restore Failed: $e");
    rethrow;
  }
}
    Future<List<Task>> fetchTasksFromCloud() async {
      final User? user = _auth.currentUser;
      if (user == null) return [];

      try {
        var doc = await _db.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['tasks'] != null) {
          List<dynamic> cloudList = doc.data()!['tasks'];
          
          // If the cloud has a timestamp, we can sync our local 'lastSyncedAt' to it
          if (doc.data()?['lastSync'] != null) {
            lastSyncedAt = (doc.data()?['lastSync'] as Timestamp).toDate();
          }

          return cloudList.map((item) => Task.fromJson(item)).toList();
        }
      } catch (e) {
        L.d("Cloud Fetch Failed: $e");
      }
      return [];
    }
  }