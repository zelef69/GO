import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn =
          googleSignIn ?? GoogleSignIn(scopes: const <String>['email']);

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  User? get currentUser => _firebaseAuth.currentUser;
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    if (kDebugMode) {
      debugPrint('[GO_PLAY-Auth] Google sign-in started');
    }
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      if (kDebugMode) {
        debugPrint(
          '[GO_PLAY-Auth] Google sign-in canceled/no account selected',
        );
      }
      return null;
    }
    if (kDebugMode) {
      debugPrint('[GO_PLAY-Auth] Google account selected');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    final uid = userCredential.user?.uid ?? 'unknown';
    if (kDebugMode) {
      debugPrint('[GO_PLAY-Auth] Firebase credential sign-in success uid=$uid');
    }
    return userCredential;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }
}
