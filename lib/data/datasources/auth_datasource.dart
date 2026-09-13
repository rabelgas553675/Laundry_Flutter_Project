import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Raw Firebase Auth calls. No business rules, no Firestore — just
/// the auth SDK. Mirrors the pattern used by UserDatasource for
/// Firestore, so auth and profile data stay cleanly separated.
class AuthDatasource {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  /// Part 17 — "Add users". Creates a brand-new Firebase Auth account
  /// for [email]/[password] WITHOUT touching the currently signed-in
  /// session.
  ///
  /// The problem this solves: [FirebaseAuth.createUserWithEmailAndPassword]
  /// on the *default* app instance signs the caller into the new
  /// account immediately, replacing whoever was signed in before —
  /// fine for PART 04's self-registration flow, but not for an Admin
  /// creating someone else's account, which would otherwise log the
  /// Admin out of their own session mid-task.
  ///
  /// The fix: create a short-lived second [FirebaseApp] (same
  /// project config, different name) purely to run the account
  /// creation on, then delete it immediately after. The default app —
  /// and therefore [FirebaseAuth.instance.currentUser], i.e. the
  /// signed-in Admin — is never touched. No Cloud Functions or Admin
  /// SDK needed, which this client-only project doesn't have.
  Future<UserCredential> registerWithoutSigningIn({
    required String email,
    required String password,
  }) async {
    final secondaryApp = await Firebase.initializeApp(
      name: 'AdminUserCreation-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );

    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Belt-and-suspenders: the secondary app is about to be deleted
      // anyway, but explicitly signing out first ensures nothing on
      // this throwaway instance is left "logged in" even momentarily.
      await secondaryAuth.signOut();
      return credential;
    } finally {
      // Always clean up the temporary app, even if account creation
      // itself threw (e.g. email-already-in-use) — otherwise a
      // string of failed "Add User" attempts would leak FirebaseApp
      // instances for the lifetime of the running app.
      await secondaryApp.delete();
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() {
    return _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
}