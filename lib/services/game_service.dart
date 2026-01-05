import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/models/game_model.dart';
import 'database_service.dart';
import '../constants/app_constants.dart';

class GameService {
  final DatabaseService _databaseService = DatabaseService();
  final Random _random = Random();
  final DatabaseReference _realtimeDb = FirebaseDatabase.instance.ref();

  // ==================== GAME INITIALIZATION ====================

  /// Start the game - called by host after game is created
  Future<void> startGame(String gameId, String hostId) async {
    print('\n🎯 STEP 3A: GameService.startGame() executing');
    print('   Expected: Tokens initialized, status → inProgress');

    try {
      // Get game from Firestore
      final game = await _databaseService.getGame(gameId);
      if (game == null) throw 'Game not found';

      // Create or verify Realtime Database session
      final sessionSnapshot = await _realtimeDb
          .child('game_sessions/$gameId')
          .get();

      if (!sessionSnapshot.exists) {
        await _realtimeDb.child('game_sessions/$gameId').set({
          'roomCode': _generateRoomCode(),
          'hostId': hostId,
          'maxPlayers': game.playerIds.length,
          'turnDuration': AppConstants.turnDuration,
          'status': 'waiting',
          'createdAt': ServerValue.timestamp,
          'playerCount': game.playerIds.length,
        });
      }

      // Initialize token positions
      final tokenPositions = {
        for (var playerId in game.playerIds)
          playerId: List.generate(
            4,
            (index) => TokenPosition(
              tokenId: index,
              position: 0,
              isHome: true,
              isFinished: false,
            ),
          ),
      };

      // Initialize scores
      final playerScores = {for (var pid in game.playerIds) pid: 0};

      // Initialize timer (10 minutes)
      final expectedEndTime = DateTime.now().add(const Duration(minutes: 10));
      final expectedEndTimeTimestamp = Timestamp.fromDate(expectedEndTime);

      print('   ✅ Got: ${tokenPositions.length} players initialized');
      // Update game in Firestore
      await _databaseService.updateGame(gameId, {
        'status': GameStatus.inProgress.index,
        'startedAt': Timestamp.now(),
        // ✅ NEW: Save expected end time
        'expectedEndTime': expectedEndTimeTimestamp,
        'tokenPositions': tokenPositions.map(
          (playerId, tokens) =>
              MapEntry(playerId, tokens.map((t) => t.toMap()).toList()),
        ),
        'currentPlayerId': game.playerIds[0],
        'currentTurn': 0,
        'lastDiceRoll': 0,
        // ✅ NEW: Initialize scores
        'playerScores': playerScores,
      });

      // Update Realtime Database
      await _realtimeDb.child('game_sessions/$gameId').update({
        'status': 'in_progress',
        'startedAt': ServerValue.timestamp,
        'expectedEndTime': expectedEndTime.millisecondsSinceEpoch,
      });
      print('   ✅ Got: Status set to inProgress');
    } catch (e) {
      print('❌ [SERVICE] Start game error: $e');
      throw 'Error starting game: $e';
    }
  }

  /// Verify player has sufficient coins and lives, then deduct entry fee
  /// Returns true if deduction successful, false otherwise
  Future<bool> deductEntryFee({
  required String userId,
  required int entryFee,
}) async {
  try {
    return await _databaseService.deductEntryFeeWithPriority(
      userId: userId,
      entryFee: entryFee,
    );
  } catch (e) {
    print('Error deducting entry fee: $e');
    return false;
  }
}

  // ==================== GAME ACTIONS ====================

  /// Roll dice
  /// Roll dice - MODIFIED VERSION
Future<int> rollDice({
  required String gameId,
  required String playerId,
}) async {
  try {
    print('\n🎯 STEP 6A: GameService.rollDice() executing');
    print('   Expected: Random 1-6, Firestore updated');

    final game = await _databaseService.getGame(gameId);
    if (game == null) throw 'Game not found';

    if (game.currentPlayerId != playerId) {
      throw 'Not your turn';
    }

    if (game.status != GameStatus.inProgress) {
      throw 'Game not in progress';
    }

    // Roll dice (1-6)
    final diceRoll = _random.nextInt(6) + 1;

    // ✅ NEW: Add dice roll value to player's score
    Map<String, int> updatedScores = Map.from(game.playerScores);
    updatedScores[playerId] = (updatedScores[playerId] ?? 0) + diceRoll; // Add dice value to score

    // Update Firestore
    await _databaseService.updateGame(gameId, {
      'lastDiceRoll': diceRoll,
      'playerScores': updatedScores, // ✅ NEW: Save updated scores
    });

    // Update Realtime Database
    await _realtimeDb.child('game_sessions/$gameId').update({
      'lastDiceRoll': diceRoll,
      'lastRollTime': ServerValue.timestamp,
    });

    print('   ✅ Got: Rolled $diceRoll');
    print('   ✅ Got: Added $diceRoll points to player $playerId');
    print('   ✅ Got: Updated Firestore & Realtime DB');
    return diceRoll;
  } catch (e) {
    print('❌ [SERVICE] Dice roll error: $e');
    throw 'Error rolling dice: $e';
  }
}

  /// Move token
  Future<void> moveToken({
    required String gameId,
    required String playerId,
    required int tokenId,
    required int diceRoll,
  }) async {
    try {
      print('\n🎯 STEP 7A: GameService.moveToken() executing');
      print('   Token: $tokenId, Dice: $diceRoll, Player: $playerId');
      print('   Expected: Position updated, turn changed');

      final game = await _databaseService.getGame(gameId);
      if (game == null) throw 'Game not found';

      if (game.currentPlayerId != playerId) {
        throw 'Not your turn';
      }

      // Get player data
      final playerTokens = game.tokenPositions[playerId] ?? [];
      final playerColor = game.playerColors[playerId]!;

      // Find token
      final token = playerTokens.firstWhere(
        (t) => t.tokenId == tokenId,
        orElse: () => throw 'Token not found',
      );

      // Validate move
      if (!isValidMove(
        token: token,
        diceRoll: diceRoll,
        playerColor: playerColor,
        playerTokens: playerTokens,
      )) {
        throw 'Invalid move';
      }

      // Calculate new position
      final movedToken = _calculateMovedToken(
        token: token,
        diceRoll: diceRoll,
        playerColor: playerColor,
      );

      // Update token list
      final updatedTokens = playerTokens.map((t) {
        return t.tokenId == tokenId ? movedToken : t;
      }).toList();

      // Check for captures
      final capturedPlayerIds = checkForCaptures(
        newPosition: movedToken.position,
        currentPlayerId: playerId,
        allTokenPositions: game.tokenPositions,
        playerColors: game.playerColors,
      );

      // Process captures & Scoring
      Map<String, List<TokenPosition>> updatedAllTokens = {
        ...game.tokenPositions,
        playerId: updatedTokens,
      };

      Map<String, int> updatedScores = Map.from(game.playerScores);
      if (!updatedScores.containsKey(playerId)) {
        updatedScores[playerId] = 0;
      }

      bool didKill = false;

      for (var capturedPlayerId in capturedPlayerIds) {
        didKill = true;
        // Captured token goes HOME
        final capturedTokens = captureToken(
          tokens: game.tokenPositions[capturedPlayerId]!,
          position: movedToken.position,
        );
        updatedAllTokens[capturedPlayerId] = capturedTokens;

        // Capturer earns 1 point for the Kill
        updatedScores[playerId] = (updatedScores[playerId] ?? 0) + 5;
        print(
          '   ⚔️ KILL! Player $playerId captured $capturedPlayerId (+5 point)',
        );
      }

      // ✅ NEW: Killing Logic - Capturer goes to FINISH immediately
      if (didKill) {
        updatedAllTokens[playerId] = updatedAllTokens[playerId]!.map((t) {
          if (t.tokenId == tokenId) {
            final path = colorPaths[playerColor]!;
            return t.copyWith(
              position: path.length - 1, // Move to last index
              isFinished: true,
            );
          }
          return t;
        }).toList();
        print('   🚀 Capturer moving to FINISH immediately!');
      }

      // Check if the moved token JUST finished (either by normal move or by kill-jump)
      // We need to re-fetch the token to see its finding state after potential kill-jump
      final finalTokenState = updatedAllTokens[playerId]!.firstWhere(
        (t) => t.tokenId == tokenId,
      );

      // If it became finished in this move (and wasn't before)
      if (finalTokenState.isFinished && !token.isFinished) {
        updatedScores[playerId] = (updatedScores[playerId] ?? 0) + 10;
        print('   🏁 FINISHED! Player $playerId reached end (+10 point)');
      }

      // Check for win (Standard win condition or Score based? Prompt says "highest point wins" after timer)
      // But standard "all tokens finished" should probably still end game or just add max points?
      // Prompt says: "any token that is finished gets one point".
      // "the player with the highest point wins" (implied at time limit, or early win?)
      // We will keep "All Tokens Finished" as an early win condition (effectively max score).
      final playerWon = hasPlayerWon(updatedAllTokens[playerId]!);

      // Determine next player
      String nextPlayerId;
      bool getsExtraTurn = getsAnotherTurn(diceRoll) && !playerWon;

      if (getsExtraTurn) {
        nextPlayerId = playerId;
        print('🎉 [SERVICE] Player gets another turn (rolled 6)');
      } else {
        nextPlayerId = getNextPlayer(
          playerIds: game.playerIds,
          currentPlayerId: playerId,
        );
        print('➡️ [SERVICE] Next player: $nextPlayerId');
      }

      // Handle game end or continue
      if (playerWon) {
        print('🏆 [SERVICE] Player $playerId won by finishing all tokens!');
        await _handleGameWin(
          gameId: gameId,
          winnerId: playerId,
          game: game.copyWith(playerScores: updatedScores),
        );
      } else {
        // Update game state
        await _databaseService.updateGame(gameId, {
          'tokenPositions': updatedAllTokens.map(
            (pid, tokens) =>
                MapEntry(pid, tokens.map((t) => t.toMap()).toList()),
          ),
          'currentPlayerId': nextPlayerId,
          'currentTurn': game.currentTurn + 1,
          'lastDiceRoll': 0,
          'playerScores': updatedScores,
        });

        // Update Realtime Database
        await _realtimeDb.child('game_sessions/$gameId').update({
          'currentPlayerId': nextPlayerId,
          'lastMoveTime': ServerValue.timestamp,
          'timeRemaining': AppConstants.turnDuration,
        });
      }
      print(
        '   ✅ Got: Token moved (Position: ${finalTokenState.position}, Finished: ${finalTokenState.isFinished})',
      );
      print('   ✅ Got: Turn passed to next player');
    } catch (e) {
      print('❌ [SERVICE] Move token error: $e');
      throw 'Error moving token: $e';
    }
  }

  /// Consume a roll without moving (pass turn when no moves available)
  Future<void> consumeRoll({
    required String gameId,
    required String playerId,
  }) async {
    try {
      final game = await _databaseService.getGame(gameId);
      if (game == null) throw 'Game not found';

      if (game.currentPlayerId != playerId) {
        throw 'Not your turn';
      }

      if (game.status != GameStatus.inProgress) {
        throw 'Game not in progress';
      }

      final isSinglePlayer = game.playerIds.length == 1;

      // ✅ SERVER-SIDE GUARD: Verify no moves are possible
      final playerTokens = game.tokenPositions[playerId] ?? [];
      final playerColor = game.playerColors[playerId];

      if (playerColor != null && game.lastDiceRoll > 0) {
        final movableTokens = getMovableTokens(
          tokens: playerTokens,
          diceRoll: game.lastDiceRoll,
          playerColor: playerColor,
        );

        if (movableTokens.isNotEmpty) {
          print(
            '❌ [SERVICE] consumeRoll blocked: User has ${movableTokens.length} movable tokens',
          );
          throw 'Cannot pass turn: You have movable tokens';
        }
      }

      // Determine next player (same player in single-player mode)
      final nextPlayerId = isSinglePlayer
          ? playerId
          : getNextPlayer(playerIds: game.playerIds, currentPlayerId: playerId);

      // Update Firestore - consume the roll and pass turn
      await _databaseService.updateGame(gameId, {
        'currentPlayerId': nextPlayerId,
        'currentTurn': isSinglePlayer ? game.currentTurn : game.currentTurn + 1,
        'lastDiceRoll': 0,
      });

      // Update Realtime Database
      await _realtimeDb.child('game_sessions/$gameId').update({
        'currentPlayerId': nextPlayerId,
        'lastMoveTime': ServerValue.timestamp,
        'timeRemaining': AppConstants.turnDuration,
      });
    } catch (e) {
      print('❌ [SERVICE] consumeRoll error: $e');
      throw 'Error consuming roll: $e';
    }
  }

  // ==================== GAME COMPLETION ====================
  
  Future<void> _handleGameWin({
    required String gameId,
    required String winnerId,
    required GameModel game,
  }) async {
    try {
      print('🏆 [SERVICE] Handling game win');

      final rankings = _calculateRankings(game.tokenPositions, winnerId);

      // Update Firestore
      await _databaseService.updateGame(gameId, {
        'status': GameStatus.completed.index,
        'winnerId': winnerId,
        'completedAt': Timestamp.now(),
      });

      // Distribute rewards
      await _distributeRewards(
        gameId: gameId,
        tier: game.tier,
        rankings: rankings,
        playerIds: game.playerIds,
        prizePool: game.prizePool,
        entryFee: game.entryFee,
      );

      // Update Realtime Database
      await _realtimeDb.child('game_sessions/$gameId').update({
        'status': 'completed',
        'winnerId': winnerId,
        'completedAt': ServerValue.timestamp,
      });

      print('✅ [SERVICE] Game completed');
    } catch (e) {
      print('❌ [SERVICE] Handle win error: $e');
      throw 'Error handling win: $e';
    }
  }

  Map<String, int> _calculateRankings(
    Map<String, List<TokenPosition>> tokenPositions,
    String winnerId,
  ) {
    final rankings = <String, int>{};
    rankings[winnerId] = 1;

    final playerScores = <String, int>{};
    for (var entry in tokenPositions.entries) {
      if (entry.key == winnerId) continue;

      final finishedCount = entry.value.where((t) => t.isFinished).length;
      playerScores[entry.key] = finishedCount;
    }

    final sortedPlayers = playerScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    int currentRank = 2;
    for (var entry in sortedPlayers) {
      rankings[entry.key] = currentRank++;
    }

    return rankings;
  }

  Future<void> _distributeRewards({
  required String gameId,
  required String tier,
  required Map<String, int> rankings,
  required List<String> playerIds,
  required int prizePool,
  required int entryFee,
}) async {
  try {
    print('\n💰 Distributing rewards...');
    
    final totalCollected = entryFee * playerIds.length;
    final prizePoolForWinner = (totalCollected * 0.75).toInt();
    
    print('   Prize for winner: +$prizePoolForWinner coins');

    for (var playerId in playerIds) {
      final rank = rankings[playerId] ?? 4;
      bool isWin = false;
      int coinChange = 0;

      if (playerIds.length == 1) {
        // Single-player: always a win
        coinChange = prizePool;
        isWin = true;
      } else {
        // Multi-player: only winner gets coins
        if (rank == 1) {
          coinChange = prizePoolForWinner;
          isWin = true;
        }
      }

      final ratingChange = isWin 
          ? AppConstants.winRatingIncrease
          : AppConstants.loseRatingDecrease;

      await _databaseService.updateUserGameStats(
        userId: playerId,
        won: isWin,
        coinsChange: coinChange,
        ratingChange: ratingChange,
      );

      // Add transaction record
      if (isWin) {
        await _databaseService.addTransaction(
          userId: playerId,
          type: 'win',
          amount: coinChange,
          description: playerIds.length == 1
              ? 'Single player game completed'
              : 'Game won - Rank #1',
        );
      } else {
        await _databaseService.addTransaction(
          userId: playerId,
          type: 'loss',
          amount: -entryFee,
          description: 'Game lost - entry fee',
        );
      }
    }
  } catch (e) {
    print('❌ Distribute rewards error: $e');
  }
}

  /// Check if game timer has expired
  Future<void> checkGameTimer(String gameId, String playerId) async {
    try {
      final game = await _databaseService.getGame(gameId);
      if (game == null || game.status == GameStatus.completed) return;

      // Only the host (or current player) needs to trigger the end game
      // To avoid race conditions, let's say the current player triggers it
      // or if current player is offline, anyone can.
      // Ideally this should be a cloud function, but for this client-side logic:
      if (game.expectedEndTime != null &&
          DateTime.now().isAfter(game.expectedEndTime!)) {
        print('⏰ [SERVICE] Timer expired! Ending game...');

        // Determine winner based on highest score
        String winnerId = game.playerIds.first;
        int maxScore = -1;

        // If scores are tied, maybe use token positions?
        // For now, strict score comparison.
        game.playerScores.forEach((pid, score) {
          if (score > maxScore) {
            maxScore = score;
            winnerId = pid;
          }
        });

        await _handleGameWin(gameId: gameId, winnerId: winnerId, game: game);
      }
    } catch (e) {
      print('❌ [SERVICE] Check timer error: $e');
    }
  }

  // ==================== TOKEN LOGIC ====================

  TokenPosition _calculateMovedToken({
    required TokenPosition token,
    required int diceRoll,
    required PlayerColor playerColor,
  }) {
    final currentPath = colorPaths[playerColor]!;

    // Moving from home - go to first position (index 0)
    if (token.isHome) {
      return TokenPosition(
        tokenId: token.tokenId,
        position: 0, // Start at index 0 of the path
        isHome: false,
        isFinished: false,
      );
    }

    // Moving on board - position is already the index
    final currentIndex = token.position;
    final newIndex = currentIndex + diceRoll;

    // ✅ FIX: Must land EXACTLY on finish position (last index)
    if (newIndex == currentPath.length - 1) {
      return TokenPosition(
        tokenId: token.tokenId,
        position: currentPath.length - 1,
        isHome: false,
        isFinished: true,
      );
    }

    // ❌ Overshooting - return unchanged (invalid move will be caught by isValidMove)
    if (newIndex >= currentPath.length) {
      return token; // Cannot overshoot
    }

    // Normal move - just increment the index
    return TokenPosition(
      tokenId: token.tokenId,
      position: newIndex,
      isHome: false,
      isFinished: false,
    );
  }

  Map<String, List<TokenPosition>> initializeTokens(List<String> playerIds) {
    final Map<String, List<TokenPosition>> positions = {};

    for (var playerId in playerIds) {
      positions[playerId] = List.generate(
        AppConstants.tokensPerPlayer,
        (index) => TokenPosition(
          tokenId: index,
          position: 0,
          isHome: true,
          isFinished: false,
        ),
      );
    }

    return positions;
  }

  bool isValidMove({
    required TokenPosition token,
    required int diceRoll,
    required PlayerColor playerColor,
    required List<TokenPosition> playerTokens,
  }) {
    if (token.isHome) return true;
    if (token.isFinished) return false;

    final currentPath = colorPaths[playerColor]!;
    final currentIndex = token.position; // Position is already the index

    // Check if position is valid
    if (currentIndex < 0 || currentIndex >= currentPath.length) return false;

    final newIndex = currentIndex + diceRoll;
    // ✅ FIX: Must land exactly on or before finish (no overshooting)
    return newIndex <= currentPath.length - 1;
  }

  List<int> getMovableTokens({
    required List<TokenPosition> tokens,
    required int diceRoll,
    required PlayerColor playerColor,
  }) {
    return tokens
        .where(
          (token) => isValidMove(
            token: token,
            diceRoll: diceRoll,
            playerColor: playerColor,
            playerTokens: tokens,
          ),
        )
        .map((token) => token.tokenId)
        .toList();
  }

  List<String> checkForCaptures({
    required int newPosition,
    required String currentPlayerId,
    required Map<String, List<TokenPosition>> allTokenPositions,
    required Map<String, PlayerColor> playerColors,
  }) {
    // Convert current player's relative position to global coordinate
    final currentGlobalPos = _getGlobalCoordinate(
      currentPlayerId,
      newPosition,
      playerColors,
    );

    // If null, we are in a safe zone (home stretch/finish) or invalid
    if (currentGlobalPos == null) return [];

    // Check if we landed on a safe spot using global ID
    if (safeSpots.contains(currentGlobalPos)) return [];

    return allTokenPositions.entries
        .where((entry) => entry.key != currentPlayerId)
        .where((entry) {
          final opponentId = entry.key;
          final opponentTokens = entry.value;

          return opponentTokens.any((token) {
            if (token.isHome || token.isFinished) return false;

            // Convert opponent token position to global
            final tokenGlobalPos = _getGlobalCoordinate(
              opponentId,
              token.position,
              playerColors,
            );

            // Compare Global Coordinates
            return tokenGlobalPos != null && tokenGlobalPos == currentGlobalPos;
          });
        })
        .map((entry) => entry.key)
        .toList();
  }

  // Helper to map relative path index (0-51) to Global Board Index (0-51)
  int? _getGlobalCoordinate(
    String playerId,
    int pathPosition,
    Map<String, PlayerColor> playerColors,
  ) {
    // 0-51 are perimeter positions. 52+ are Safe House/Finish.
    if (pathPosition > 51) return null;

    final color = playerColors[playerId];
    if (color == null) return null;

    int offset = 0;
    switch (color) {
      case PlayerColor.red:
        offset = 0;
        break;
      case PlayerColor.green:
        offset = 13;
        break;
      case PlayerColor.yellow:
        offset = 26;
        break;
      case PlayerColor.blue:
        offset = 39;
        break;
    }

    return (pathPosition + offset) % 52;
  }

  List<TokenPosition> captureToken({
    required List<TokenPosition> tokens,
    required int position,
  }) {
    return tokens.map((token) {
      if (!token.isHome && !token.isFinished && token.position == position) {
        return token.copyWith(position: 0, isHome: true);
      }
      return token;
    }).toList();
  }

  bool hasPlayerWon(List<TokenPosition> tokens) {
    return tokens.every((token) => token.isFinished);
  }

  bool getsAnotherTurn(int diceRoll) => diceRoll == 6;

  String getNextPlayer({
    required List<String> playerIds,
    required String currentPlayerId,
  }) {
    final currentIndex = playerIds.indexOf(currentPlayerId);
    return playerIds[(currentIndex + 1) % playerIds.length];
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  // ==================== CONSTANTS ====================

  // ✅ FIXED: Use sequential 0-based indices to match UI grid coordinate arrays
  // Each path represents the journey from start to finish
  // Position stored in TokenPosition.position is the INDEX into this array
  static const Map<PlayerColor, List<int>> colorPaths = {
    // Red: 59 positions total (52 perimeter + 6 safe house + 1 finish)
    PlayerColor.red: [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
      20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
      38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, // Perimeter
      52, 53, 54, 55, 56, 57, // Safe house
      58, // Finish
    ],
    // Green: 59 positions total
    PlayerColor.green: [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
      20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
      38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, // Perimeter
      52, 53, 54, 55, 56, 57, // Safe house
      58, // Finish
    ],
    // Yellow: 59 positions total
    PlayerColor.yellow: [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
      20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
      38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, // Perimeter
      52, 53, 54, 55, 56, 57, // Safe house
      58, // Finish
    ],
    // Blue: 59 positions total
    PlayerColor.blue: [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
      20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
      38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, // Perimeter
      52, 53, 54, 55, 56, 57, // Safe house
      58, // Finish
    ],
  };

  // Safe spots are now indices in the path (not abstract position numbers)
  // These correspond to positions where tokens cannot be captured
  static const List<int> safeSpots = [
    0,
    8,
    13,
    21,
    26,
    34,
    39,
    47,
  ]; // Start positions and key spots
}
