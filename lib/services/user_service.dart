import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ludotitian/models/user_model.dart';
import '../constants/app_constants.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ==================== USER AUTHENTICATION & CREATION ====================

  /// Create or get user (called after authentication)
  Future<UserModel> createOrGetUser() async {
  final user = _auth.currentUser;
  if (user == null) throw Exception('No authenticated user');

  try {
    final userDoc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc.data() != null) {
      // ✅ Use fromFirestore which handles docId properly
      final existingUser = UserModel.fromFirestore(userDoc.data()!, userDoc.id);

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .update({'lastLogin': DateTime.now().millisecondsSinceEpoch});

      return existingUser.copyWith(lastLogin: DateTime.now());
    } else {
      // Create new user
      final newUser = UserModel.fromFirebaseUser(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'Player${user.uid.substring(0, 6)}',
        photoUrl: user.photoURL,
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(newUser.toMap());

      return newUser;
    }
  } catch (e) {
    print('❌ Error in createOrGetUser: $e');
    throw 'Error creating/getting user: $e';
  }
}

  // ==================== USER RETRIEVAL ====================

  /// Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      final userDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        return UserModel.fromMap(userDoc.data()!);
      }
      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  /// Get current authenticated user
  Future<UserModel?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return getUserById(user.uid);
  }

  /// Stream user data (real-time updates)
  Stream<UserModel?> streamUser(String userId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            return UserModel.fromMap(snapshot.data()!);
          }
          return null;
        });
  }

  /// Stream current user data
  Stream<UserModel?> streamCurrentUser() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);
    return streamUser(user.uid);
  }

  // ==================== USER UPDATES ====================

  /// Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? photoUrl,
  }) async {
    try {
      final Map<String, dynamic> updates = {};

      if (displayName != null) updates['displayName'] = displayName;
      if (photoUrl != null) updates['photoUrl'] = photoUrl;

      if (updates.isNotEmpty) {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(userId)
            .update(updates);
      }
    } catch (e) {
      throw 'Error updating user profile: $e';
    }
  }

  /// Update user coins
  Future<void> updateCoins(String userId, int coinsChange) async {
    try {
      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final currentCoins = userDoc.data()!['coins'] as int? ?? 0;
        transaction.update(userDocRef, {'coins': currentCoins + coinsChange});
      });
    } catch (e) {
      throw 'Error updating coins: $e';
    }
  }

  /// Update user rating
  Future<void> updateRating(String userId, int ratingChange) async {
    try {
      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final currentRating = userDoc.data()!['rating'] as int? ?? 100;
        final newRating = (currentRating + ratingChange).clamp(0, 9999);

        transaction.update(userDocRef, {'rating': newRating});
      });
    } catch (e) {
      throw 'Error updating rating: $e';
    }
  }

  /// Update user game statistics after match
  Future<void> updateUserStats({
    required String userId,
    required int coinsChange,
    required int ratingChange,
    required bool isWin,
  }) async {
    try {
      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final data = userDoc.data()!;
        final currentCoins = data['coins'] as int? ?? 0;
        final currentRating = data['rating'] as int? ?? 100;
        final currentMatches = data['totalMatches'] as int? ?? 0;
        final currentWins = data['wins'] as int? ?? 0;
        final currentLosses = data['losses'] as int? ?? 0;

        transaction.update(userDocRef, {
          'coins': currentCoins + coinsChange,
          'rating': (currentRating + ratingChange).clamp(0, 9999),
          'totalMatches': currentMatches + 1,
          'wins': isWin ? currentWins + 1 : currentWins,
          'losses': isWin ? currentLosses : currentLosses + 1,
          'lastLogin': DateTime.now().millisecondsSinceEpoch,
        });
      });
    } catch (e) {
      throw 'Error updating user stats: $e';
    }
  }

  /// Check if user has enough lives to play
  Future<bool> hasEnoughLives(String userId, {int requiredLives = 1}) async {
    try {
      final user = await getUserById(userId);
      return user != null && user.lives >= requiredLives;
    } catch (e) {
      print('Error checking lives: $e');
      return false;
    }
  }

  /// Deduct lives (for match entry)
  Future<void> deductLives(String userId, {int livesCount = 1}) async {
    try {
      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final currentLives = userDoc.data()!['lives'] as int? ?? 0;

        if (currentLives < livesCount) {
          throw Exception("Insufficient lives");
        }

        transaction.update(userDocRef, {'lives': currentLives - livesCount});
      });
    } catch (e) {
      throw 'Error deducting lives: $e';
    }
  }

  /// Add lives (from purchase or rewards)
  Future<void> addLives(String userId, int livesCount) async {
    try {
      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final currentLives = userDoc.data()!['lives'] as int? ?? 0;

        transaction.update(userDocRef, {'lives': currentLives + livesCount});
      });
    } catch (e) {
      throw 'Error adding lives: $e';
    }
  }

  /// Purchase lives with coins (₦100 per life)
  Future<void> purchaseLives({
    required String userId,
    required int livesCount,
  }) async {
    try {
      const costPerLife = 100; // ₦100 per life
      final totalCost = livesCount * costPerLife;

      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final data = userDoc.data()!;
        final currentCoins = data['coins'] as int? ?? 0;
        final currentLives = data['lives'] as int? ?? 0;

        if (currentCoins < totalCost) {
          throw Exception("Insufficient coins");
        }

        transaction.update(userDocRef, {
          'coins': currentCoins - totalCost,
          'lives': currentLives + livesCount,
        });
      });

      // Add transaction record
      await _addTransaction(
        userId: userId,
        type: 'purchase',
        amount: -totalCost,
        description: 'Purchased $livesCount lives for ₦$totalCost',
      );
    } catch (e) {
      throw 'Error purchasing lives: $e';
    }
  }

  /// Claim daily free lives (3 lives after playing 5 games)
  Future<void> claimDailyLives(String userId) async {
    try {
      final user = await getUserById(userId);
      if (user == null) throw 'User not found';

      if (!user.canClaimDailyLives) {
        throw 'Daily lives already claimed today';
      }

      // Check if user has played at least 5 games today
      // (You'd need to track daily games played - this is simplified)

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
            'lives': user.lives + 3,
            'lastFreeLifesClaim': DateTime.now().millisecondsSinceEpoch,
          });

      await _addTransaction(
        userId: userId,
        type: 'reward',
        amount: 0,
        description: 'Claimed 3 daily free lives',
      );
    } catch (e) {
      throw 'Error claiming daily lives: $e';
    }
  }

  /// Add life from watching ads (10 ads = 1 life)
  Future<void> addLifeFromAds(String userId) async {
    try {
      await addLives(userId, 1);

      await _addTransaction(
        userId: userId,
        type: 'reward',
        amount: 0,
        description: 'Earned 1 life from watching 10 ads',
      );
    } catch (e) {
      throw 'Error adding life from ads: $e';
    }
  }

  // ==================== VALIDATION HELPERS ====================

  /// Check if user has enough coins
  Future<bool> hasEnoughCoins(String userId, int requiredCoins) async {
    try {
      final user = await getUserById(userId);
      return user != null && user.coins >= requiredCoins;
    } catch (e) {
      print('Error checking coins: $e');
      return false;
    }
  }

  /// Check if user can join tier (based on rating/coins)
  Future<bool> canJoinTier(String userId, String tier) async {
    try {
      final user = await getUserById(userId);
      if (user == null) return false;

      final entryFee = AppConstants.tierEntryFees[tier] ?? 0;
      print(user.lives);
      // Check if user has enough lives and coins
      return user.lives >= 1 && user.coins >= entryFee;
    } catch (e) {
      print('Error checking tier eligibility: $e');
      return false;
    }
  }

  // ==================== LEADERBOARD ====================

  /// Get top players by coins
  Future<List<UserModel>> getTopPlayersByCoins({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .orderBy('coins', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => UserModel.fromMap(doc.data())).toList();
    } catch (e) {
      print('Error getting leaderboard: $e');
      return [];
    }
  }

  /// Get top players by rating
  Future<List<UserModel>> getTopPlayersByRating({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .orderBy('rating', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => UserModel.fromMap(doc.data())).toList();
    } catch (e) {
      print('Error getting leaderboard: $e');
      return [];
    }
  }

  /// Stream leaderboard (real-time)
  Stream<List<UserModel>> streamLeaderboard({int limit = 100}) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .orderBy('coins', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UserModel.fromMap(doc.data()))
              .toList(),
        );
  }

  // ==================== PRIVATE HELPERS ====================

  /// Add transaction record
  Future<void> _addTransaction({
    required String userId,
    required String type,
    required int amount,
    required String description,
  }) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('transactions')
          .add({
            'type': type,
            'amount': amount,
            'description': description,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error adding transaction: $e');
    }
  }

  // ==================== ACCOUNT DELETION ====================

  /// Delete user account and all associated data
  Future<void> deleteUserAccount(String userId) async {
    try {
      // Delete user document
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .delete();

      // Delete auth account
      final user = _auth.currentUser;
      if (user != null && user.uid == userId) {
        await user.delete();
      }
    } catch (e) {
      throw 'Error deleting account: $e';
    }
  }
}
