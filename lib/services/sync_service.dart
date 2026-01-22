  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:google_sign_in/google_sign_in.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:procrastinator/utils/logger.dart';
  import '../models/task_model.dart';

  class SyncService {
    // Add this line to ensure only ONE instance exists
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
    final FirebaseAuth _auth = FirebaseAuth.instance;
    final FirebaseFirestore _db = FirebaseFirestore.instance;
    
    // 1. Enhanced Scopes: Explicitly requesting 'profile' ensures the photo URL is sent
    final GoogleSignIn _googleSignIn = GoogleSignIn(
      scopes: [
        'email',
        'https://www.googleapis.com/auth/userinfo.profile',
        'openid',
      ],
    );

    // 2. Track Last Sync locally for the UI to display
    static DateTime? lastSyncedAt;

    Future<String?> getUserId() async {
      return _auth.currentUser?.uid;
    }

    Future<User?> signInWithGoogle() async {
    try {
      // 1. 🔥 PERSISTENCE CHECK: Try to sign in silently first.
      // If the app was killed from memory, this finds the existing session 
      // on the device (S23 FE / OnePlus) without showing a popup.
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();

      // 2. FALLBACK: If silent failed (first login or session expired), show the popup.
      googleUser ??= await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Debugging: Keeping your Photo URL verification
      L.d("📸 S.INC: GOOGLE PHOTO URL: ${googleUser.photoUrl}");

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 3. HANDSHAKE: Sign into Firebase with the Google credentials
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      L.d("☁️ S.INC: Session secured for ${userCredential.user?.email}");
      return userCredential.user;
    } catch (e) {
      L.d("🚨 S.INC Sign-In Error: $e");
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
    // 1. RE-AUTH (Fresh Handshake)
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

    if (googleAuth != null) {
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
    }

    // 2. WIPE FIRESTORE FIRST (While Auth is still valid)
    // This is where your PERMISSION_DENIED was happening
    L.d("🗑️ S.INC: Wiping Firestore document for ${user.uid}...");
    await _db.collection('users').doc(user.uid).delete();
    
    // Optional: Wipe the beta request too
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