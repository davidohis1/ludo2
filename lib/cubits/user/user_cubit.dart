import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/models/user_model.dart';
import '/services/database_service.dart';
import '/services/user_service.dart';

part 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  final DatabaseService _databaseService = DatabaseService();
  final UserService _userService = UserService();

  StreamSubscription<UserModel?>? _userStreamSubscription;
  StreamSubscription<List<UserModel>>? _leaderboardStreamSubscription;

  UserCubit() : super(const UserInitial());

  /// Load current user data (one-time fetch)
  Future<void> loadUserData(String userId) async {
    try {
      emit(const UserLoading());

      final currentUser = await _databaseService.getUser(userId);

      if (currentUser != null) {
        emit(UserLoaded(currentUser: currentUser));
      } else {
        emit(const UserError(message: 'Failed to load user data'));
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ UserCubit: Error loading user data - $e');
      }
      emit(UserError(message: e.toString()));
    }
  }

  /// Update user profile
  Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? photoUrl,
  }) async {
    try {
      print('📝 Updating profile for user: $userId');

      final updates = <String, dynamic>{};

      if (displayName != null && displayName.isNotEmpty) {
        updates['displayName'] = displayName;
      }

      if (photoUrl != null) {
        updates['photoUrl'] = photoUrl;
      }

      if (updates.isEmpty) {
        print('⚠️ No updates to apply');
        return;
      }

      await _databaseService.updateUser(userId, updates);

      // Refresh user data
      await refreshUserData();

      print('✅ Profile updated successfully');
    } catch (e) {
      print('❌ Error updating profile: $e');
      throw 'Failed to update profile: $e';
    }
  }

  
  /// Upload profile picture to Firebase Storage
  Future<String> uploadProfilePicture(String userId, File imageFile) async {
    try {
      print('📸 Uploading profile picture for user: $userId');

      // Create a reference to Firebase Storage
      // final storageRef =Firebas.instance
      //     .ref()
      //     .child('profile_pictures')
      //     .child('$userId.jpg');

      // // Upload the file
      // final uploadTask = storageRef.putFile(
      //   imageFile,
      //   SettableMetadata(
      //     contentType: 'image/jpeg',
      //     customMetadata: {'userId': userId},
      //   ),
      // );

      // Wait for upload to complete
      // final snapshot = await uploadTask;

      // // Get download URL
      // final downloadUrl = await snapshot.ref.getDownloadURL();

      // print('✅ Profile picture uploaded: $downloadUrl');

      return '';
    } catch (e) {
      print('❌ Error uploading profile picture: $e');
      throw 'Failed to upload profile picture: $e';
    }
  }

  /// Refresh user data
  /// Refresh user data
Future<void> refreshUserData() async {  // ← Remove userId parameter
  try {
    final currentState = state;
    if (currentState is UserLoaded) {
      final user = await _databaseService.getUser(currentState.currentUser.id);
      if (user != null) {
        emit(
          UserLoaded(
            currentUser: user,
            leaderboard: currentState.leaderboard,
          ),
        );
      }
    }
  } catch (e) {
    print('❌ Error refreshing user data: $e');
  }
}

  /// Load leaderboard
  Future<void> loadLeaderboard() async {
    try {
      print('📊 Loading leaderboard...');

      final leaderboard = await _databaseService.getTopPlayersByCoins(
        limit: 100,
      );

      if (state is UserLoaded) {
        emit(
          UserLoaded(
            currentUser: (state as UserLoaded).currentUser,
            leaderboard: leaderboard,
          ),
        );
      }

      print('✅ Leaderboard loaded: ${leaderboard.length} players');
    } catch (e) {
      print('❌ Error loading leaderboard: $e');
    }
  }

  /// Start real-time leaderboard stream
  void startLeaderboardStream() {
    print('🔄 Starting leaderboard stream...');

    _leaderboardStreamSubscription?.cancel();

    _leaderboardStreamSubscription = _databaseService
        .streamLeaderboard(limit: 100)
        .listen(
          (leaderboard) {
            print('📊 Leaderboard updated: ${leaderboard.length} players');

            if (state is UserLoaded) {
              emit(
                UserLoaded(
                  currentUser: (state as UserLoaded).currentUser,
                  leaderboard: leaderboard,
                ),
              );
            }
          },
          onError: (error) {
            print('❌ Leaderboard stream error: $error');
          },
        );
  }

  /// Stop leaderboard stream
  void stopLeaderboardStream() {
    _leaderboardStreamSubscription?.cancel();
    print('🛑 Leaderboard stream stopped');
  }

  /// Start real-time user data stream
  void startUserStream(String userId) {
    if (kDebugMode) {
      print('🔄 UserCubit: Starting user stream for $userId');
    }

    // Cancel existing subscription if any
    _userStreamSubscription?.cancel();

    _userStreamSubscription = _userService
        .streamUser(userId)
        .listen(
          (user) {
            if (kDebugMode) {
              print(
                '📡 UserCubit: Received user update - ${user?.displayName}',
              );
            }

            final currentState = state;
            if (currentState is UserLoaded) {
              if (user != null) {
                emit(currentState.copyWith(currentUser: user));
              }
            } else if (user != null) {
              emit(UserLoaded(currentUser: user));
            }
          },
          onError: (error) {
            if (kDebugMode) {
              print('❌ UserCubit: Stream error - $error');
            }
            emit(UserError(message: error.toString()));
          },
        );
  }

  /// Stop user stream
  void stopUserStream() {
    if (kDebugMode) {
      print('🛑 UserCubit: Stopping user stream');
    }
    _userStreamSubscription?.cancel();
    _userStreamSubscription = null;
  }

  /// Update user lives
  Future<void> updateLives(String userId, int newLives) async {
    try {
      print('💖 Updating lives for user: $userId to $newLives');

      await _databaseService.updateUser(userId, {'lives': newLives});

      // Refresh user data
      await refreshUserData();

      print('✅ Lives updated successfully');
    } catch (e) {
      print('❌ Error updating lives: $e');
      throw 'Failed to update lives: $e';
    }
  }

  /// Update user coins
  Future<void> updateCoins(String userId, int newCoins) async {
    try {
      print('💰 Updating coins for user: $userId to $newCoins');

      await _databaseService.updateUser(userId, {'coins': newCoins});

      // Refresh user data
      await refreshUserData();

      print('✅ Coins updated successfully');
    } catch (e) {
      print('❌ Error updating coins: $e');
      throw 'Failed to update coins: $e';
    }
  }

  /// Update user data (generic)
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    try {
      print('📝 Updating user data: $userId');

      await _databaseService.updateUser(userId, data);

      // Refresh user data
      await refreshUserData();

      print('✅ User data updated successfully');
    } catch (e) {
      print('❌ Error updating user: $e');
      throw 'Failed to update user: $e';
    }
  }

  /// Record a transaction
  Future<void> recordTransaction({
    required String userId,
    required String type,
    required int amount,
    required String description,
  }) async {
    try {
      print('📝 Recording transaction: $type, $amount for $userId');

      await _databaseService.addTransaction(
        userId: userId,
        type: type,
        amount: amount,
        description: description,
      );

      print('✅ Transaction recorded');
    } catch (e) {
      print('❌ Error recording transaction: $e');
      // Don't throw - transaction recording is not critical
    }
  }

  /// Get user by ID without modifying current user state
  Future<UserModel?> getUser(String userId) async {
    try {
      return await _databaseService.getUser(userId);
    } catch (e) {
      if (kDebugMode) {
        print('❌ UserCubit: Error fetching user $userId - $e');
      }
      return null;
    }
  }

  /// Clear user data
  void clearUser() {
    if (kDebugMode) {
      print('🛑 UserCubit: Clearing user data');
    }
    stopUserStream();
    emit(const UserInitial());
  }

  @override
  Future<void> close() {
    _userStreamSubscription?.cancel();
    _leaderboardStreamSubscription?.cancel();
    return super.close();
  }
}
