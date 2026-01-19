  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:google_sign_in/google_sign_in.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:procrastinator/utils/logger.dart';
  import '../models/task_model.dart';

  class SyncService {
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
        // FORCE REFRESH: This ensures Google re-checks permissions and sends the latest photo URL
        await _googleSignIn.signOut(); 
        
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null;

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        // Debugging: This will print the URL to your console so you can verify it exists
        L.d("GOOGLE PHOTO URL: ${googleUser.photoUrl}");

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        return userCredential.user;
      } catch (e) {
        L.d("Sign-In Error: $e");
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
        // Step A: Fetch the current state of the Cloud Vault
        var doc = await _db.collection('users').doc(user.uid).get();
        List<Task> cloudTasks = [];
        
        if (doc.exists && doc.data()?['tasks'] != null) {
          List<dynamic> cloudList = doc.data()!['tasks'];
          cloudTasks = cloudList.map((item) => Task.fromJson(item)).toList();
        }

        // Step B: Business Reconciliation (Merge based on Task ID)
        // This ensures if Samsung has Task A and OnePlus has Task B, 
        // the result is [Task A, Task B], not one deleting the other.
        final Map<String, Task> reconciledMap = {};
        
        // Load cloud tasks first
        for (var t in cloudTasks) {
          reconciledMap[t.id] = t;
        }
        
        // Overwrite/Add with local tasks (treating local as the newest truth)
        for (var t in localTasks) {
          reconciledMap[t.id] = t;
        }

        List<Map<String, dynamic>> finalTaskData = 
            reconciledMap.values.map((t) => t.toMap()).toList();

        // Step C: Push the finalized ledger
        await _db.collection('users').doc(user.uid).set({
          'email': user.email,
          'lastSync': FieldValue.serverTimestamp(),
          'tasks': finalTaskData,
        }, SetOptions(merge: true));

        lastSyncedAt = DateTime.now();
        L.d("Cloud Reconciled Successfully at $lastSyncedAt");
      } catch (e) {
        L.d("Cloud Sync Failed: $e");
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