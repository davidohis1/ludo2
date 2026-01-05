import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../models/game_tier.dart';

// Assuming MatchmakingResult is defined in this file or imported from models
class MatchmakingResult {
  final String gameId;
  final String playerId;
  final int playerPosition;

  const MatchmakingResult({
    required this.gameId,
    required this.playerId,
    required this.playerPosition,
  });
}

class MatchmakingService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // -------------------------------------------------------------
  // PUBLIC METHOD: joinMatchmaking (FIXED return type and logic)
  // -------------------------------------------------------------

  Future<MatchmakingResult> joinMatchmaking({
    required String userId,
    required GameTier tier,
    required int entryFee,
  }) async {
    try {
      final tierRef = _dbRef.child('matchmaking/${tier.name.toLowerCase()}');
      final snapshot = await tierRef.get();

      if (snapshot.exists) {
        final games = Map<String, dynamic>.from(snapshot.value as Map);

        String? availableGameId;
        for (var entry in games.entries) {
          final gameData = Map<String, dynamic>.from(entry.value);
          final playerCount = (gameData['players'] as Map?)?.length ?? 0;

          if (playerCount < 4 && gameData['status'] == 'waiting') {
            availableGameId = entry.key;
            break;
          }
        }

        if (availableGameId != null) {
          // ✅ FIX: Call _addPlayerToGame and return its MatchmakingResult
          return await _addPlayerToGame(availableGameId, userId, tier);
        } else {
          // ✅ FIX: Call _createNewGame and return its MatchmakingResult
          return await _createNewGame(userId, tier, entryFee);
        }
      } else {
        // ✅ FIX: Call _createNewGame and return its MatchmakingResult
        return await _createNewGame(userId, tier, entryFee);
      }
    } catch (e) {
      print('Matchmaking error: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // PRIVATE METHOD: _createNewGame (FIXED return type and value)
  // -------------------------------------------------------------

  // Changed return type from Future<String> to Future<MatchmakingResult>
  Future<MatchmakingResult> _createNewGame(String userId, GameTier tier, int entryFee) async {
    final gameRef = _dbRef.child('matchmaking/${tier.name.toLowerCase()}').push();
    final gameId = gameRef.key!;

    const playerPosition = 0;
    // We use the Firebase userId (UID) as the internal playerId
    final playerId = userId; 

    await gameRef.set({
      'gameId': gameId,
      'tier': tier.name.toLowerCase(),
      'entryFee': entryFee,
      'status': 'waiting',
      'createdAt': ServerValue.timestamp,
      'players': {
        '$playerPosition': { // Use position key (0)
          'userId': playerId,
          'position': playerPosition,
          'joinedAt': ServerValue.timestamp,
        }
      },
    });

    // ✅ FIX: Return the full result object
    return MatchmakingResult(
      gameId: gameId,
      playerId: playerId,
      playerPosition: playerPosition,
    );
  }

  // -------------------------------------------------------------
  // PRIVATE METHOD: _addPlayerToGame (FIXED return type and value)
  // -------------------------------------------------------------

  // Changed return type from Future<void> to Future<MatchmakingResult>
  Future<MatchmakingResult> _addPlayerToGame(String gameId, String userId, GameTier tier) async {
    final gameRef = _dbRef.child('matchmaking/${tier.name.toLowerCase()}/$gameId');
    final snapshot = await gameRef.get();
    
    if (snapshot.exists) {
      final gameData = Map<String, dynamic>.from(snapshot.value as Map);
      final players = Map<String, dynamic>.from(gameData['players'] ?? {});
      
      final playerPosition = players.length; // Next available position
      final playerId = userId; // Using Firebase userId as internal playerId
      
      await gameRef.child('players/$playerPosition').set({
        'userId': playerId,
        'position': playerPosition,
        'joinedAt': ServerValue.timestamp,
      });

      // If 4 players, start the game
      if (playerPosition >= 3) {
        await _startGame(gameId, tier, gameData);
      }

      // ✅ FIX: Return the full result object
      return MatchmakingResult(
        gameId: gameId,
        playerId: playerId,
        playerPosition: playerPosition,
      );
    }
    // Handle the case where the game might have been deleted just now
    throw Exception("Game disappeared during join attempt.");
  }

  // ... (The rest of the service methods remain the same) ...

  Future<void> _startGame(String gameId, GameTier tier, Map<String, dynamic> gameData) async {
    final players = Map<String, dynamic>.from(gameData['players']);
    
    // Create game session
    final gameSessionRef = _dbRef.child('game_sessions/$gameId');
    
    await gameSessionRef.set({
      'gameId': gameId,
      'tier': tier.name.toLowerCase(),
      'entryFee': gameData['entryFee'],
      'status': 'playing',
      'currentTurn': 0,
      'lastDiceValue': 6,
      'startedAt': ServerValue.timestamp,
      'timeRemaining': 600, // 10 minutes
      'players': players,
      'tokenPositions': {
        '0': [-1, -1, -1, -1],
        '1': [-1, -1, -1, -1],
        '2': [-1, -1, -1, -1],
        '3': [-1, -1, -1, -1],
      },
      'scores': {
        '0': 0,
        '1': 0,
        '2': 0,
        '3': 0,
      },
    });

    // Update matchmaking status
    await _dbRef
        .child('matchmaking/${tier.name.toLowerCase()}/$gameId/status')
        .set('started');
  }

  Stream<Map<String, dynamic>?> streamMatchmaking(String gameId, GameTier tier) {
    return _dbRef
        .child('matchmaking/${tier.name.toLowerCase()}/$gameId')
        .onValue
        .map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }
}