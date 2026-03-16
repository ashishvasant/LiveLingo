import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models.dart';
import 'firebase_bootstrap.dart';

class AuthService extends ChangeNotifier {
  AuthService._({required bool testing})
    : _testing = testing,
      _googleSignIn = GoogleSignIn.instance;

  final bool _testing;
  final GoogleSignIn _googleSignIn;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventsSubscription;

  bool initialized = false;
  bool configured = false;
  bool busy = false;
  String? error;
  AuthenticatedUser? currentUser;

  static Future<AuthService> bootstrap() async {
    final AuthService service = AuthService._(testing: false);
    await service._initialize();
    return service;
  }

  factory AuthService.test({AuthenticatedUser? user}) {
    return AuthService._(testing: true)
      ..initialized = true
      ..configured = true
      ..currentUser = user;
  }

  Future<void> _initialize() async {
    if (_testing) {
      initialized = true;
      configured = true;
      notifyListeners();
      return;
    }
    final FirebaseBootstrapResult bootstrapResult =
        await FirebaseBootstrap.initialize();
    configured = bootstrapResult.configured;
    error = bootstrapResult.message;
    if (!bootstrapResult.initialized) {
      initialized = true;
      notifyListeners();
      return;
    }

    await _googleSignIn.initialize(
      clientId: FirebaseBootstrap.googleClientId.isEmpty
          ? null
          : FirebaseBootstrap.googleClientId,
      serverClientId: FirebaseBootstrap.googleServerClientId.isEmpty
          ? null
          : FirebaseBootstrap.googleServerClientId,
    );
    _authEventsSubscription = _googleSignIn.authenticationEvents.listen(
      _handleAuthenticationEvent,
      onError: (Object eventError) {
        error = 'Google sign-in failed: $eventError';
        notifyListeners();
      },
    );

    await _syncCurrentFirebaseUser();
    final Future<GoogleSignInAccount?>? lightweightAttempt =
        _googleSignIn.attemptLightweightAuthentication();
    if (lightweightAttempt != null) {
      try {
        await lightweightAttempt;
      } catch (attemptError) {
        error = 'Google lightweight auth failed: $attemptError';
      }
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> _handleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        final GoogleSignInAccount googleUser = event.user;
        final String? idToken = googleUser.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          error = 'Google sign-in did not return an ID token.';
          break;
        }
        await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
        await _syncCurrentFirebaseUser();
        error = null;
        notifyListeners();
        return;
      case GoogleSignInAuthenticationEventSignOut():
        await FirebaseAuth.instance.signOut();
        currentUser = null;
        error = null;
        notifyListeners();
        return;
    }
  }

  Future<void> _syncCurrentFirebaseUser() async {
    final User? firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      currentUser = null;
      return;
    }
    final String? idToken = await firebaseUser.getIdToken();
    currentUser = AuthenticatedUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? 'Signed-in user',
      photoUrl: firebaseUser.photoURL,
      idToken: idToken ?? '',
    );
  }

  Future<void> signInWithGoogle() async {
    if (_testing || !configured) {
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _googleSignIn.authenticate();
      await _syncCurrentFirebaseUser();
    } catch (signInError) {
      error = 'Google sign-in failed: $signInError';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_testing) {
      currentUser = null;
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await _googleSignIn.signOut();
      await FirebaseAuth.instance.signOut();
      currentUser = null;
      error = null;
    } catch (signOutError) {
      error = 'Sign-out failed: $signOutError';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> getFreshIdToken() async {
    if (_testing) {
      return currentUser?.idToken ?? 'test-id-token';
    }
    final User? firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('No authenticated Firebase user.');
    }
    final String? idToken = await firebaseUser.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Firebase did not return an ID token.');
    }
    currentUser = AuthenticatedUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? 'Signed-in user',
      photoUrl: firebaseUser.photoURL,
      idToken: idToken,
    );
    notifyListeners();
    return idToken;
  }

  @override
  void dispose() {
    unawaited(_authEventsSubscription?.cancel());
    super.dispose();
  }
}
