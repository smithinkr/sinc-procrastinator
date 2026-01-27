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
      // 🕵️ CRITICAL: Paste your Web Client ID from Firebase Console here
      await _googleSignIn.initialize(
        serverClientId: 'YOUR_CLIENT_ID_FROM_FIREBASE.apps.googleusercontent.com',
      );
      _isInitialized = true;
    }
  }

  Future<User?> signInWithGoogle() async {
  try {
    await _ensureInitialized();
    // 🛡️ S.INC SHIELD: Mandatory 2026 Warm-up
      await _googleSignIn.initialize(
      serverClientId: '31245559081-i1mjcihhc5fr6edobt1vdh00um0ve0ra.apps.googleusercontent.com',
    );
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

    // 4. SECURE FIREBASE SESSION
    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    
    if (userCredential.user != null) {
      await StorageService.saveAuthHint(
        initial: (userCredential.user!.displayName ?? "U")[0].toUpperCase(), 
        isActive: true, 
        photoUrl: googleUser.photoUrl,
      );
    }

    return userCredential.user;
  } catch (e) {
    // 🕵️ This is where we catch "User closed the modal" or "No SHA-1 match"
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
Future<void> deleteUserAccount() async {
  final User? user = _auth.currentUser;
  if (user == null) return;

  try {
    // 1. RE-AUTH (The 2026 Handshake)
    // Removed '?' because authenticate() is now non-nullable or throws an error.
    final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

    // 🛡️ S.INC SHIELD: The NEW step to get the accessToken
    // Re-authentication requires the same scopes used during login.
    final authorization = await googleUser.authorizationClient.authorizeScopes([
      'email',
      'openid',
    ]);

    // Removed 'await' because .authentication is now a synchronous getter.
    final googleAuth = googleUser.authentication;

    // Create the credential using the new authorization object
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: authorization.accessToken, // FIXED: No longer undefined
      idToken: googleAuth.idToken,
    );

    // Perform the security re-authentication
    await user.reauthenticateWithCredential(credential);

    // 2. WIPE FIRESTORE (Authoritative Wipe)
    L.d("🗑️ S.INC: Wiping Firestore document for ${user.uid}...");
    await _db.collection('users').doc(user.uid).delete();
    
    await _db.collection('beta_requests').doc(user.uid).delete();

    // 3. FINALLY DELETE AUTH ACCOUNT
    await user.delete();
    
    L.d("☢️ S.INC: Cloud and Identity wiped successfully.");
  } catch (e) {
    L.d("🚨 S.INC Permission Error: $e");
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