import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '/constants/app_constants.dart';
import '/models/user_model.dart';
import '/models/game_model.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== USER OPERATIONS ====================

  Future<void> createUser(UserModel user) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.id)
          .set(user.toMap());
    } catch (e) {
      throw 'Error creating user: $e';
    }
  }

  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();

      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw 'Error getting user: $e';
    }
  }

  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      throw 'Error updating user: $e';
    }
  }

  /// Get user transactions once (not as stream)
Future<List<Map<String, dynamic>>> getUserTransactionsOnce(String userId) async {
  try {
    final querySnapshot = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .get();
    
    return querySnapshot.docs
        .map((doc) => {
          ...doc.data(),
          'id': doc.id,
          'timestamp': doc.data()['timestamp'] ?? Timestamp.now(),
        })
        .toList();
  } catch (e) {
    print('Error getting transactions once: $e');
    return [];
  }
}

// Run this once in a separate script or in your app startup
Future<void> migrateAllUsers() async {
  try {
    final usersSnapshot = await _firestore.collection('users').get();
    
    for (var doc in usersSnapshot.docs) {
      final data = doc.data();
      if (data['depositCoins'] == null) {
        final oldCoins = data['coins'] as int? ?? 0;
        await _firestore.collection('users').doc(doc.id).update({
          'totalCoins': oldCoins,
          'depositCoins': oldCoins,
          'winningCoins': 0,
          'weeklyWinnings': 0,
        });
        print('Migrated user: ${doc.id}');
      }
    }
    
    print('✅ All users migrated successfully!');
  } catch (e) {
    print('❌ Migration error: $e');
  }
}

  Future<void> migrateUserBalance(String userId) async {
  try {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (!userDoc.exists) return;
    
    final data = userDoc.data()!;
    final currentCoins = data['coins'] as int? ?? 0;
    
    // Check if migration is needed
    if (data['depositCoins'] == null) {
      await _firestore.collection('users').doc(userId).update({
        'totalCoins': currentCoins,
        'depositCoins': currentCoins,
        'winningCoins': 0,
      });
      print('✅ User balance migrated: $userId');
    }
  } catch (e) {
    print('❌ Migration error: $e');
  }
}
Future<bool> deductEntryFeeWithPriority({
  required String userId,
  required int entryFee,
}) async {
  try {
    final userDocRef = _firestore.collection('users').doc(userId);
    
    await _firestore.runTransaction((transaction) async {
      final userDoc = await transaction.get(userDocRef);
      if (!userDoc.exists) throw 'User not found';
      
      final data = userDoc.data()!;
      final depositCoins = (data['depositCoins'] ?? 0) as int;
      final winningCoins = (data['winningCoins'] ?? 0) as int;
      final totalCoins = depositCoins + winningCoins;
      
      if (totalCoins < entryFee) {
        throw 'Insufficient coins';
      }
      
      int remainingFee = entryFee;
      int newDepositCoins = depositCoins;
      int newWinningCoins = winningCoins;
      
      // Use deposit coins first
      if (depositCoins > 0) {
        final fromDeposit = depositCoins < remainingFee ? depositCoins : remainingFee;
        newDepositCoins -= fromDeposit;
        remainingFee -= fromDeposit;
      }
      
      // Then use winning coins if needed
      if (remainingFee > 0 && winningCoins > 0) {
        final fromWinning = winningCoins < remainingFee ? winningCoins : remainingFee;
        newWinningCoins -= fromWinning;
        remainingFee -= fromWinning;
      }
      
      if (remainingFee > 0) {
        throw 'Insufficient coins';
      }
      
      transaction.update(userDocRef, {
        'depositCoins': newDepositCoins,
        'winningCoins': newWinningCoins,
      });
    });
    
    return true;
  } catch (e) {
    print('Error deducting entry fee: $e');
    return false;
  }
}

Future<void> addWinningCoins(String userId, int amount) async {
  try {
    await _firestore.collection('users').doc(userId).update({
      'winningCoins': FieldValue.increment(amount),
      'weeklyWinnings': FieldValue.increment(amount),
    });
  } catch (e) {
    print('Error adding winning coins: $e');
  }
}

Future<void> addDepositCoins(String userId, int amount) async {
  try {
    await _firestore.collection('users').doc(userId).update({
      'depositCoins': FieldValue.increment(amount),
    });
  } catch (e) {
    print('Error adding deposit coins: $e');
  }
}

Future<void> processWithdrawal(String userId, int amount) async {
  try {
    final userDocRef = _firestore.collection('users').doc(userId);
    
    await _firestore.runTransaction((transaction) async {
      final userDoc = await transaction.get(userDocRef);
      if (!userDoc.exists) throw 'User not found';
      
      final winningCoins = (userDoc.data()!['winningCoins'] ?? 0) as int;
      
      if (winningCoins < amount) {
        throw 'Insufficient withdrawable balance';
      }
      
      transaction.update(userDocRef, {
        'winningCoins': winningCoins - amount,
        'weeklyWinnings': FieldValue.increment(-amount),
      });
    });
  } catch (e) {
    print('Error processing withdrawal: $e');
  }
}

Future<void> updateUserGameStats({
  required String userId,
  required bool won,
  required int coinsChange,
  required int ratingChange,
}) async {
  final userDocRef = _firestore.collection('users').doc(userId);

  try {
    await _firestore.runTransaction((transaction) async {
      final userDocSnapshot = await transaction.get(userDocRef);

      if (!userDocSnapshot.exists) {
        throw Exception("User document not found");
      }

      final currentData = userDocSnapshot.data()!;
      final currentDepositCoins = currentData['depositCoins'] as int? ?? 0;
      final currentWinningCoins = currentData['winningCoins'] as int? ?? 0;
      final currentRating = currentData['rating'] as int? ?? 0;
      final currentMatches = currentData['totalMatches'] as int? ?? 0;
      final currentWins = currentData['wins'] as int? ?? 0;
      final currentLosses = currentData['losses'] as int? ?? 0;

      if (won && coinsChange > 0) {
        // Add winnings to winning coins
        transaction.update(userDocRef, {
          'winningCoins': currentWinningCoins + coinsChange,
          'rating': currentRating + ratingChange,
          'totalMatches': currentMatches + 1,
          'wins': currentWins + 1,
          'weeklyWinnings': FieldValue.increment(coinsChange),
        });
      } else if (!won) {
        // Loss - coins were already deducted from entry fee
        transaction.update(userDocRef, {
          'rating': currentRating + ratingChange,
          'totalMatches': currentMatches + 1,
          'losses': currentLosses + 1,
        });
      }
    });
  } catch (e) {
    throw 'Error updating game stats: $e';
  }
}

  Future<void> updateUserCoins(String userId, int coins) async {
    try {
      await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
        {'coins': coins},
        SetOptions(merge: true),
      );
    } catch (e) {
      throw 'Error updating coins: $e';
    }
  }

  // In your GameService or DatabaseService
  Future<void> updateWeeklyWinnings(String userId, int amount) async {
    try {
      final userDocRef = _firestore.collection('users').doc(userId);
      
      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);
        if (!userDoc.exists) return;
        
        final currentWeeklyWinnings = userDoc.data()!['weeklyWinnings'] ?? 0;
        transaction.update(userDocRef, {
          'weeklyWinnings': currentWeeklyWinnings + amount,
        });
      });
    } catch (e) {
      print('Error updating weekly winnings: $e');
    }
  }

  /// Get weekly leaderboard data from transactions
Future<Map<String, int>> getWeeklyNetEarnings(String userId) async {
  try {
    final now = DateTime.now();
    final startOfWeek = _getStartOfWeek(now);
    
    // Get all transactions for this week
    final transactionsQuery = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
        .get();
    
    int totalWinnings = 0;
    int totalWithdrawals = 0;
    int totalEntryFees = 0;
    
    for (var doc in transactionsQuery.docs) {
      final transaction = doc.data();
      final type = transaction['type'] as String? ?? '';
      final amount = transaction['amount'] as int? ?? 0;
      
      if (type == 'win') {
        totalWinnings += amount;
      } else if (type == 'withdrawal') {
        totalWithdrawals += amount.abs(); // Withdrawals are negative
      } else if (type == 'loss') {
        // Losses represent entry fees paid
        totalEntryFees += amount.abs(); // Losses are negative
      }
      // 'purchase' type is ignored (deposits don't count for leaderboard)
    }
    
    // Net weekly earnings = Winnings - Entry Fees - Withdrawals
    final netEarnings = totalWinnings - totalEntryFees - totalWithdrawals;
    
    return {
      'netEarnings': netEarnings > 0 ? netEarnings : 0,
      'winnings': totalWinnings,
      'entryFees': totalEntryFees,
      'withdrawals': totalWithdrawals,
    };
  } catch (e) {
    print('Error getting weekly net earnings: $e');
    return {'netEarnings': 0, 'winnings': 0, 'entryFees': 0, 'withdrawals': 0};
  }
}

/// Get start of week (Monday)
DateTime _getStartOfWeek(DateTime date) {
  // Calculate days since Monday (1 = Monday, 7 = Sunday)
  int daysSinceMonday = date.weekday - DateTime.monday;
  if (daysSinceMonday < 0) daysSinceMonday += 7;
  
  return DateTime(date.year, date.month, date.day - daysSinceMonday);
}

/// Get weekly leaderboard
Future<List<Map<String, dynamic>>> getWeeklyLeaderboard() async {
  try {
    // Get all users
    final usersSnapshot = await _firestore.collection('users').get();
    
    final List<Map<String, dynamic>> leaderboardData = [];
    
    // Calculate weekly net earnings for each user
    for (var userDoc in usersSnapshot.docs) {
      final userId = userDoc.id;
      final userData = userDoc.data();
      
      final earnings = await getWeeklyNetEarnings(userId);
      
      if (earnings['netEarnings']! > 0) {
        leaderboardData.add({
          'id': userId,
          'displayName': userData['displayName'] ?? 'Player',
          'photoUrl': userData['photoUrl'] ?? '',
          'rating': userData['rating'] ?? 0,
          'netEarnings': earnings['netEarnings'],
          'winnings': earnings['winnings'],
          'entryFees': earnings['entryFees'],
          'withdrawals': earnings['withdrawals'],
        });
      }
    }
    
    // Sort by net earnings (highest first)
    leaderboardData.sort((a, b) => b['netEarnings'].compareTo(a['netEarnings']));
    
    return leaderboardData;
  } catch (e) {
    print('Error getting weekly leaderboard: $e');
    return [];
  }
}
  Future<void> updateUserRating(String userId, int rating) async {
    try {
      await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
        {'rating': rating},
        SetOptions(merge: true),
      );
    } catch (e) {
      throw 'Error updating rating: $e';
    }
  }

  

  Stream<List<UserModel>> getLeaderboard({int limit = 100}) {
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

  /// Get top players by coins for leaderboard
  Future<List<UserModel>> getTopPlayersByCoins({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .orderBy('coins', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ Error getting top players: $e');
      throw 'Error loading leaderboard: $e';
    }
  }

  /// Get top players by rating for leaderboard
  Future<List<UserModel>> getTopPlayersByRating({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .orderBy('rating', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ Error getting top players by rating: $e');
      throw 'Error loading leaderboard: $e';
    }
  }

  /// Stream leaderboard updates (real-time)
  Stream<List<UserModel>> streamLeaderboard({int limit = 100}) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .orderBy('coins', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
              .toList();
        });
  }
  // ==================== GAME OPERATIONS ====================

  Future<String> createGame(GameModel game) async {
    try {
      final docRef = await _firestore
          .collection(AppConstants.gamesCollection)
          .add(game.toMap());
      return docRef.id;
    } catch (e) {
      throw 'Error creating game: $e';
    }
  }

  Stream<List<GameModel>> getAvailableGamesStream(String tier) {
    // ✅ Calculate cutoff time: 30 minutes ago
    final thirtyMinutesAgo = DateTime.now().subtract(
      const Duration(minutes: 30),
    );

    return _firestore
        .collection('games')
        .where('tier', isEqualTo: tier)
        .where('status', isEqualTo: GameStatus.waiting.index)
        .where(
          'createdAt',
          isGreaterThan: Timestamp.fromDate(thirtyMinutesAgo),
        ) // ✅ Filter old rooms
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GameModel.fromMap(doc.data()))
              .toList();
        });
  }

  /// Delete a game (for host cancellation)
  Future<void> deleteGame(String gameId) async {
    try {
      await _firestore.collection('games').doc(gameId).delete();

      // Also delete from Realtime Database
      await FirebaseDatabase.instance.ref('game_sessions/$gameId').remove();

      print('✅ Game deleted: $gameId');
    } catch (e) {
      throw 'Error deleting game: $e';
    }
  }

  Future<GameModel?> getGame(String gameId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.gamesCollection)
          .doc(gameId)
          .get();

      if (doc.exists && doc.data() != null) {
        return GameModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw 'Error getting game: $e';
    }
  }

  Stream<GameModel?> gameStream(String gameId) {
    return _firestore
        .collection(AppConstants.gamesCollection)
        .doc(gameId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return GameModel.fromMap(doc.data()!);
          }
          return null;
        });
  }

  Future<void> updateGame(String gameId, Map<String, dynamic> data) async {
    if (gameId.isEmpty) {
      throw 'Error updating game: Game ID cannot be an empty string.';
    }
    try {
      await _firestore
          .collection(AppConstants.gamesCollection)
          .doc(gameId)
          .update(data);
    } catch (e) {
      if (e is FirebaseException && e.code == 'not-found') {
        throw 'Error updating game: Game document not found ($gameId).';
      }
      throw 'Error updating game: $e';
    }
  }

  Stream<List<GameModel>> getUserGameHistory(String userId) {
    return _firestore
        .collection(AppConstants.gamesCollection)
        .where('playerIds', arrayContains: userId)
        .where('status', isEqualTo: GameStatus.completed.index)
        .orderBy('completedAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GameModel.fromMap(doc.data()))
              .toList(),
        );
  }

  // ==================== REAL-TIME MATCHMAKING OPERATIONS ====================

  /// Add player to matchmaking queue with real-time presence
  Future<void> enterMatchmaking({
    required String userId,
    required String tier,
    required String displayName,
    required String photoUrl,
    required int rating,
  }) async {
    try {
      final queueRef = _firestore
          .collection('matchmaking_queue')
          .doc(tier)
          .collection('players')
          .doc(userId);

      await queueRef.set({
        'userId': userId,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'rating': rating,
        'tier': tier,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'searching', // searching, matched, in_game
      });
    } catch (e) {
      throw 'Error entering matchmaking: $e';
    }
  }

  /// Remove player from matchmaking queue
  Future<void> leaveMatchmaking(String userId, String tier) async {
    try {
      await _firestore
          .collection('matchmaking_queue')
          .doc(tier)
          .collection('players')
          .doc(userId)
          .delete();
    } catch (e) {
      throw 'Error leaving matchmaking: $e';
    }
  }

  /// Stream players in matchmaking queue for a specific tier
  Stream<List<Map<String, dynamic>>> matchmakingQueueStream(String tier) {
    return _firestore
        .collection('matchmaking_queue')
        .doc(tier)
        .collection('players')
        .where('status', isEqualTo: 'searching')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList(),
        );
  }

  /// Update player status in matchmaking queue
  Future<void> updateMatchmakingStatus(
    String userId,
    String tier,
    String status,
  ) async {
    try {
      await _firestore
          .collection('matchmaking_queue')
          .doc(tier)
          .collection('players')
          .doc(userId)
          .update({'status': status});
    } catch (e) {
      throw 'Error updating matchmaking status: $e';
    }
  }

  /// Create a matched game from matchmaking
  Future<String> createMatchedGame({
    required String tier,
    required List<String> playerIds,
    required Map<String, String> playerNames,
    required Map<String, String> playerPhotos,
    required int entryFee,
    required int prizePool,
  }) async {
    try {
      // Initialize player colors and coins
      // Map playerId -> PlayerColor (matches GameModel's expected type)
      final Map<String, PlayerColor> playerColors = {};
      final Map<String, int> playerCoins = {};

      for (int i = 0; i < playerIds.length; i++) {
        final pid = playerIds[i];
        final color = PlayerColor.values[i % PlayerColor.values.length];
        playerColors[pid] = color;
        playerCoins[pid] = entryFee;
      }

      final game = GameModel(
        id: '',
        tier: tier,
        entryFee: entryFee,
        prizePool: prizePool,
        playerIds: playerIds,
        playerColors: playerColors,
        playerNames: playerNames,
        playerPhotos: playerPhotos,
        playerCoins: playerCoins,
        status: GameStatus.inProgress,
        createdAt: DateTime.now(),
        startedAt: DateTime.now(),
        tokenPositions: {}, // Will be initialized by game service
        currentPlayerId: playerIds[0],
      );

      final gameId = await createGame(game);

      await updateGame(gameId, {'id': gameId});

      // Update all players' status to 'matched'
      for (String playerId in playerIds) {
        await updateMatchmakingStatus(playerId, tier, 'matched');
      }

      return gameId;
    } catch (e) {
      throw 'Error creating matched game: $e';
    }
  }

  /// Check if player is still in queue (for cleanup)
  Future<bool> isPlayerInQueue(String userId, String tier) async {
    try {
      final doc = await _firestore
          .collection('matchmaking_queue')
          .doc(tier)
          .collection('players')
          .doc(userId)
          .get();

      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Remove a player from a game (when they leave lobby)
  /// Only works for non-host players - host should use deleteGame instead
  Future<void> removePlayerFromGame(String gameId, String userId) async {
    try {
      print('🚪 [DATABASE] Removing player $userId from game $gameId');

      // Get current game data
      final gameDoc = await _firestore
          .collection(AppConstants.gamesCollection)
          .doc(gameId)
          .get();

      if (!gameDoc.exists) {
        throw 'Game not found';
      }

      final gameData = gameDoc.data()!;
      final status = gameData['status'] as int;

      // Can only remove from waiting games
      if (status != GameStatus.waiting.index) {
        throw 'Cannot leave game that has already started';
      }

      final playerIds = List<String>.from(gameData['playerIds'] ?? []);

      // Check if player is in the game
      if (!playerIds.contains(userId)) {
        print('⚠️ Player not in game, nothing to remove');
        return;
      }

      // Check if player is the host (first player)
      if (playerIds.first == userId) {
        throw 'Host cannot leave using this method. Use deleteGame instead.';
      }

      // Remove player from all maps
      final updatedPlayerIds = List<String>.from(playerIds)..remove(userId);

      // If no players left after removing, delete the game
      if (updatedPlayerIds.isEmpty) {
        print('🗑️ [DATABASE] No players left, deleting game');
        await deleteGame(gameId);
        return;
      }

      // Get and update player colors map
      final playerColorsMap = Map<String, dynamic>.from(
        gameData['playerColors'] ?? {},
      );
      playerColorsMap.remove(userId);

      // Get and update player names map
      final playerNamesMap = Map<String, dynamic>.from(
        gameData['playerNames'] ?? {},
      );
      playerNamesMap.remove(userId);

      // Get and update player photos map
      final playerPhotosMap = Map<String, dynamic>.from(
        gameData['playerPhotos'] ?? {},
      );
      playerPhotosMap.remove(userId);

      // Get and update player coins map
      final playerCoinsMap = Map<String, dynamic>.from(
        gameData['playerCoins'] ?? {},
      );
      playerCoinsMap.remove(userId);

      // Update Firestore
      await _firestore
          .collection(AppConstants.gamesCollection)
          .doc(gameId)
          .update({
            'playerIds': updatedPlayerIds,
            'playerColors': playerColorsMap,
            'playerNames': playerNamesMap,
            'playerPhotos': playerPhotosMap,
            'playerCoins': playerCoinsMap,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      print('✅ [DATABASE] Player removed from Firestore');

      // Update Realtime Database session
      final realtimeRef = FirebaseDatabase.instance.ref(
        'game_sessions/$gameId',
      );

      final sessionSnapshot = await realtimeRef.get();

      if (sessionSnapshot.exists) {
        await realtimeRef.update({
          'playerCount': updatedPlayerIds.length,
          'lastUpdate': ServerValue.timestamp,
        });

        print('✅ [DATABASE] Realtime session updated');
      }

      print(
        '✅ [DATABASE] Player removed successfully. ${updatedPlayerIds.length} players remaining',
      );
    } catch (e) {
      print('❌ [DATABASE] Error removing player: $e');
      throw 'Error removing player from game: $e';
    }
  }

  // ==================== TRANSACTION OPERATIONS ====================

  Future<void> addTransaction({
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
      throw 'Error adding transaction: $e';
    }
  }

  Stream<List<Map<String, dynamic>>> getUserTransactions(String userId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList(),
        );
  }

  // ==================== DAILY CHALLENGES ====================

  /// ✅ NEW: Claim daily challenge reward with anti-cheat measures
  /// Verifies challenge hasn't been claimed yet today
  /// Stores data in main user document (no subcollection queries needed)
  Future<bool> claimDailyChallengeReward({
    required String userId,
    required String challengeType,
    required int reward,
  }) async {
    try {
      print('\n💎 Claiming daily challenge: $challengeType for $reward coins');

      final userDocRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId);

      // Use transaction to prevent double-claiming
      final result = await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userDocRef);

        if (!userDoc.exists) {
          throw Exception("User not found");
        }

        final userData = userDoc.data()!;
        final currentCoins = userData['coins'] as int? ?? 0;

        // ✅ NEW: Check if this challenge was completed today
        // Store completed challenges in a Map with date key
        final completedChallenges =
            (userData['dailyChallengesCompleted'] as Map?) ?? {};

        // Use today's date as key (format: "yyyy-MM-dd")
        final today = DateTime.now();
        final dateKey =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        // Get list of completed challenges for today
        final todaysChallenges = (completedChallenges[dateKey] as List?) ?? [];

        // Check if this specific challenge was already completed today
        if (todaysChallenges.contains(challengeType)) {
          print('   ⚠️ Challenge already claimed today. Cannot claim twice.');
          return false; // Already claimed
        }

        // Award coins and record completion
        final updatedChallenges = {...completedChallenges};
        updatedChallenges[dateKey] = [...todaysChallenges, challengeType];

        transaction.update(userDocRef, {
          'coins': currentCoins + reward,
          'dailyChallengesCompleted': updatedChallenges,
        });

        return true; // Successfully claimed
      });

      if (result) {
        // Record transaction only if claim was successful
        await addTransaction(
          userId: userId,
          type: 'challenge',
          amount: reward,
          description:
              'Completed daily challenge: $challengeType (+$reward coins)',
        );

        print('   ✅ Challenge claimed! +$reward coins');
      }

      return result;
    } catch (e) {
      print('   ❌ Error claiming challenge: $e');
      throw 'Error claiming daily challenge: $e';
    }
  }

  /// ✅ NEW: Get completed daily challenges for a user (for today only)
  /// Shows which challenges were completed today
  Future<List<String>> getCompletedDailyChallenges(String userId) async {
    try {
      final userDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        return [];
      }

      final userData = userDoc.data()!;
      final completedChallenges =
          (userData['dailyChallengesCompleted'] as Map?) ?? {};

      // Get today's date key
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Return completed challenges for today
      final todaysChallenges = (completedChallenges[dateKey] as List?) ?? [];
      return todaysChallenges.cast<String>();
    } catch (e) {
      print('❌ Error getting completed challenges: $e');
      return [];
    }
  }

  // ==================== LIVES MANAGEMENT ====================

  /// Purchase lives (₦100 per life)
  Future<void> purchaseLives({
    required String userId,
    required int livesCount,
    required int totalCost,
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

        final currentLives = userDoc.data()!['lives'] as int? ?? 0;

        transaction.update(userDocRef, {'lives': currentLives + livesCount});
      });

      // Add transaction record
      await addTransaction(
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
      final user = await getUser(userId);
      if (user == null) throw 'User not found';

      if (!user.canClaimDailyLives) {
        throw 'Daily lives already claimed today';
      }

      await updateUser(userId, {
        'lives': user.lives + 3,
        'lastFreeLifesClaim': DateTime.now().millisecondsSinceEpoch,
      });

      await addTransaction(
        userId: userId,
        type: 'reward',
        amount: 0,
        description: 'Claimed 3 daily free lives',
      );
    } catch (e) {
      throw 'Error claiming daily lives: $e';
    }
  }

  /// Add lives from watching ads (10 ads = 1 life)
  Future<void> addLifeFromAds(String userId) async {
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

        transaction.update(userDocRef, {'lives': currentLives + 1});
      });

      await addTransaction(
        userId: userId,
        type: 'reward',
        amount: 0,
        description: 'Earned 1 life from watching 10 ads',
      );
    } catch (e) {
      throw 'Error adding life from ads: $e';
    }
  }
}
