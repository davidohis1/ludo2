import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/models/user_model.dart';
import '/services/auth_service.dart';
import '/services/user_service.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  AuthCubit() : super(const AuthInitial()) {
    // Listen to Firebase auth state changes
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  /// Handle Firebase auth state changes
  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      // User signed out
      if (kDebugMode) {
        print('🔓 AuthCubit: User signed out');
      }
      emit(const AuthUnauthenticated());
    } else {
      // User signed in
      if (kDebugMode) {
        print('🔐 AuthCubit: User signed in - ${firebaseUser.uid}');
        print('   Firebase Email: ${firebaseUser.email}');
        print('   Firebase DisplayName: ${firebaseUser.displayName}');
        print('   Firebase PhotoURL: ${firebaseUser.photoURL}');
      }

      // Load or create user data from Firestore
      try {
        final currentUser = await _userService.createOrGetUser();

        if (kDebugMode) {
          print('✅ AuthCubit: User data loaded successfully');
          print('   ID: ${currentUser.id}');
          print('   Display Name: ${currentUser.displayName}');
          print('   Email: ${currentUser.email}');
          print('   Total Coins: ${currentUser.totalCoins}');
          print('   Deposit Coins: ${currentUser.depositCoins}');
          print('   Winning Coins: ${currentUser.winningCoins}');
          print('   Lives: ${currentUser.lives}');
          print('   Rating: ${currentUser.rating}');
          print('   PhotoURL: ${currentUser.photoUrl}');
        }

        emit(
          AuthAuthenticated(currentUser: currentUser, userId: firebaseUser.uid),
        );
      } catch (e, stackTrace) {
        if (kDebugMode) {
          print('❌ AuthCubit: Failed to load user data');
          print('   Error: $e');
          print('   Stack trace: $stackTrace');
        }
        emit(AuthError(message: 'Failed to load user data: $e'));
      }
    }
  }

  /// Sign in with email and password
  Future<void> signInWithEmail(String email, String password) async {
    try {
      if (kDebugMode) {
        print('🔄 AuthCubit: Starting email sign in...');
        print('   Email: $email');
      }

      emit(const AuthLoading());

      final user = await _authService.signInWithEmail(email, password);

      if (user != null) {
        // Auth state listener will handle the rest
        if (kDebugMode) {
          print('✅ AuthCubit: Email sign in successful');
        }
      } else {
        throw Exception('Sign in failed - no user returned');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ AuthCubit: Sign in failed');
        print('   Error: $e');
        print('   Stack trace: $stackTrace');
      }
      emit(AuthError(message: _getErrorMessage(e)));
    }
  }

  /// Register with email and password
  Future<void> registerWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      if (kDebugMode) {
        print('🔄 AuthCubit: Starting registration...');
        print('   Email: $email');
        print('   Display Name: $displayName');
      }

      emit(const AuthLoading());

      final user = await _authService.registerWithEmail(
        email,
        password,
        displayName,
      );

      if (user != null) {
        // Auth state listener will handle the rest
        if (kDebugMode) {
          print('✅ AuthCubit: Registration successful');
        }
      } else {
        throw Exception('Registration failed - no user returned');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ AuthCubit: Registration failed');
        print('   Error: $e');
        print('   Stack trace: $stackTrace');
      }
      emit(AuthError(message: _getErrorMessage(e)));
    }
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      if (kDebugMode) {
        print('🔄 AuthCubit: Starting Google sign in...');
      }

      emit(const AuthLoading());

      final user = await _authService.signInWithGoogle();

      if (user != null) {
        // Auth state listener will handle the rest
        if (kDebugMode) {
          print('✅ AuthCubit: Google sign in successful');
        }
      } else {
        throw Exception('Google sign in failed - no user returned');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ AuthCubit: Google sign in failed');
        print('   Error: $e');
        print('   Stack trace: $stackTrace');
      }
      emit(AuthError(message: _getErrorMessage(e)));
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      if (kDebugMode) {
        print('🔄 AuthCubit: Signing out...');
      }

      await _authService.signOut();
      emit(const AuthUnauthenticated());

      if (kDebugMode) {
        print('✅ AuthCubit: Sign out successful');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ AuthCubit: Sign out failed');
        print('   Error: $e');
        print('   Stack trace: $stackTrace');
      }
      emit(AuthError(message: _getErrorMessage(e)));
    }
  }

  /// Get user-friendly error message
  String _getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email';
        case 'wrong-password':
          return 'Incorrect password';
        case 'email-already-in-use':
          return 'Email is already registered';
        case 'weak-password':
          return 'Password is too weak';
        case 'invalid-email':
          return 'Invalid email address';
        default:
          return error.message ?? 'Authentication failed';
      }
    }
    return error.toString();
  }
}