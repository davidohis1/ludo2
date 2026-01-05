import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '/models/game_model.dart';
import '/services/game_service.dart';
import '/services/database_service.dart';

// ==================== STATES ====================

abstract class GameState extends Equatable {
  const GameState();
  @override
  List<Object?> get props => [];
}

class GameInitial extends GameState {}

class GameLoading extends GameState {
  final String? message;
  const GameLoading({this.message});
  @override
  List<Object?> get props => [message];
}

class GameLoaded extends GameState {
  final GameModel game;
  final bool isMyTurn;
  final int? lastDiceRoll;
  final List<int> movableTokens;
  // ✅ NEW: Time remaining for the game
  final Duration? timeRemaining;

  const GameLoaded({
    required this.game,
    required this.isMyTurn,
    this.lastDiceRoll,
    this.movableTokens = const [],
    this.timeRemaining,
  });

  @override
  List<Object?> get props => [
    game,
    isMyTurn,
    lastDiceRoll,
    movableTokens,
    timeRemaining,
  ];
}

// ... (Matchmaking, GameCompleted, GameError classes unchanged)
// ... (GameCubit class start)

class Matchmaking extends GameState {
  final String tier;
  final List<Map<String, dynamic>> playersInQueue;
  const Matchmaking({required this.tier, required this.playersInQueue});
  @override
  List<Object?> get props => [tier, playersInQueue];
}

class GameCompleted extends GameState {
  final GameModel game;
  final String winnerId;
  final Map<String, int> rankings;

  const GameCompleted({
    required this.game,
    required this.winnerId,
    required this.rankings,
  });

  @override
  List<Object?> get props => [game, winnerId, rankings];
}

class GameError extends GameState {
  final String message;
  const GameError(this.message);
  @override
  List<Object?> get props => [message];
}

// ==================== CUBIT ====================

class GameCubit extends Cubit<GameState> {
  final GameService _gameService = GameService();
  final DatabaseService _databaseService = DatabaseService();

  StreamSubscription<GameModel?>? _gameStreamSubscription;
  StreamSubscription<List<Map<String, dynamic>>>?
  _matchmakingStreamSubscription;

  String? _currentGameId;
  String? _currentUserId;
  bool _isStreamActive = false;
  Timer? _gameTimer; // ✅ NEW: Local periodic timer

  GameCubit() : super(GameInitial());

  // ==================== CREATE GAME (MANUAL) ====================

  Future<String> createGame({
    required String hostId,
    required String hostName,
    required String hostPhoto,
    required String tier,
    required int maxPlayers,
    required int turnDuration,
  }) async {
    try {
      print('\n🎯 STEP 1: createGame() executing');
      print('   Expected: Game created in Firestore, status = waiting');

      emit(const GameLoading(message: 'Creating game room...'));

      final entryFee = _getEntryFee(tier);

      // ✅ NEW: Deduct entry fee from host before creating game
      await _gameService.deductEntryFee(userId: hostId, entryFee: entryFee);

      final game = GameModel(
        id: '',
        tier: tier,
        entryFee: entryFee,
        prizePool: _getPrizePool(tier),
        playerIds: [hostId],
        playerNames: {hostId: hostName},
        playerPhotos: {hostId: hostPhoto},
        playerColors: {hostId: PlayerColor.red},
        playerCoins: {hostId: entryFee},
        status: GameStatus.waiting,
        createdAt: DateTime.now(),
        currentPlayerId: hostId,
        tokenPositions: {},
      );

      final gameId = await _databaseService.createGame(game);
      await _databaseService.updateGame(gameId, {'id': gameId});

      _currentGameId = gameId;
      _currentUserId = hostId;

      print('   ✅ Got: Game created with ID: $gameId');
      print('   ✅ Got: Entry fee deducted from host');
      print('   ✅ Got: Status = ${GameStatus.waiting}');

      _startGameStream(gameId, hostId);

      return gameId;
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      // emit(GameError('Failed to create game: $e')); // Don't emit error to avoid UI rebuild
      rethrow;
    }
  }

  // ==================== JOIN EXISTING GAME ====================

  Future<void> joinExistingGame({
    required String gameId,
    required String userId,
  }) async {
    try {
      print('\n🎯 STEP 2: joinExistingGame() executing');
      print('   Expected: User added to game.playerIds, color assigned');

      if (gameId.isEmpty) throw Exception('Game ID cannot be empty');
      if (userId.isEmpty) throw Exception('User ID cannot be empty');

      emit(const GameLoading(message: 'Joining game...'));

      final user = await _databaseService.getUser(userId);
      if (user == null) throw Exception('User not found');

      final existingGame = await _databaseService.getGame(gameId);
      if (existingGame == null) throw Exception('Game not found');

      if (existingGame.status != GameStatus.waiting) {
        throw Exception('Game is not accepting players');
      }

      // ✅ NEW: Deduct entry fee from joining player
      await _gameService.deductEntryFee(
        userId: userId,
        entryFee: existingGame.entryFee,
      );

      _currentGameId = gameId;
      _currentUserId = userId;

      final updatedPlayerIds = [...existingGame.playerIds, userId];
      final updatedPlayerNames = {
        ...existingGame.playerNames,
        userId: user.displayName,
      };
      final updatedPlayerPhotos = {
        ...existingGame.playerPhotos,
        userId: user.photoUrl ?? '',
      };
      final updatedPlayerColors = {...existingGame.playerColors};
      final updatedPlayerCoins = {
        ...existingGame.playerCoins,
        userId: existingGame.entryFee,
      };

      if (updatedPlayerColors.length < PlayerColor.values.length) {
        final color = PlayerColor.values[updatedPlayerColors.length];
        updatedPlayerColors[userId] = color;
      }

      await _databaseService.updateGame(gameId, {
        'playerIds': updatedPlayerIds,
        'playerNames': updatedPlayerNames,
        'playerPhotos': updatedPlayerPhotos,
        'playerColors': updatedPlayerColors.map((k, v) => MapEntry(k, v.index)),
        'playerCoins': updatedPlayerCoins,
      });

      print('   ✅ Got: Player added to game');
      print('   ✅ Got: Entry fee deducted from player');
      print('   ✅ Got: Total players = ${updatedPlayerIds.length}');
      print('   ✅ Got: Player color = ${updatedPlayerColors[userId]}');

      _startGameStream(gameId, userId);
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      emit(GameError('Failed to join game: $e'));
    }
  }

  // ==================== START GAME AS HOST ====================

  Future<void> startGameAsHost(String gameId) async {
    try {
      print('\n🎯 STEP 3: startGameAsHost() executing');
      print('   Expected: Game status → inProgress, tokens initialized');

      emit(const GameLoading(message: 'Starting game...'));

      await _gameService.startGame(gameId, _currentUserId!);

      print('   ✅ Got: Game started');
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      emit(GameError('Failed to start game: $e'));
    }
  }

  // ==================== JOIN GAME (FROM GAMESCREEN) ====================

  Future<void> joinGame(String gameId, String userId) async {
    try {
      if (_isStreamActive && _currentGameId == gameId) {
        print('\n⚠️ joinGame() skipped - already listening to game $gameId');
        return;
      }

      print('\n🎯 STEP 4: joinGame() executing (from GameScreen)');
      print('   Expected: Start listening to game stream');

      if (state is! GameLoaded) {
        emit(const GameLoading(message: 'Loading game...'));
      }

      _currentGameId = gameId;
      _currentUserId = userId;

      print('   ✅ Got: Set gameId = $gameId, userId = $userId');

      _startGameStream(gameId, userId);
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      emit(GameError('Failed to join game: $e'));
    }
  }

  // ==================== START GAME STREAM ====================

  void _startGameStream(String gameId, String userId) {
    if (_isStreamActive && _currentGameId == gameId) {
      print('\n⚠️ _startGameStream() skipped - already active');
      return;
    }

    print('\n🎯 STEP 5: _startGameStream() executing');
    print('   Expected: Listen to Firestore game updates');

    _gameStreamSubscription?.cancel();
    _isStreamActive = true;

    _gameStreamSubscription = _databaseService
        .gameStream(gameId)
        .listen(
          (game) {
            if (game == null) {
              print('   ❌ Got: Game not found');
              emit(const GameError('Game not found'));
              _isStreamActive = false;
              _gameStreamSubscription
                  ?.cancel(); // ✅ Cancel stream to prevent spamming
              return;
            }

            print('\n📊 GAME UPDATE RECEIVED:');
            print('   Status: ${game.status}');
            print('   Current turn: ${game.currentPlayerId}');
            print('   Last dice: ${game.lastDiceRoll}');
            print('   My ID: $userId');

            if (game.status == GameStatus.completed) {
              print('\n🎯 STEP X: Game completed');
              final rankings = _calculateRankings(game);
              emit(
                GameCompleted(
                  game: game,
                  winnerId: game.winnerId ?? '',
                  rankings: rankings,
                ),
              );
              _isStreamActive = false;
              return;
            }

            final isMyTurn = game.currentPlayerId == userId;
            print('   Is my turn: $isMyTurn');

            List<int> movableTokens = [];
            if (isMyTurn && game.lastDiceRoll > 0) {
              final myTokens = game.tokenPositions[userId] ?? [];
              final myColor = game.playerColors[userId];

              if (myColor != null) {
                movableTokens = _gameService.getMovableTokens(
                  tokens: myTokens,
                  diceRoll: game.lastDiceRoll,
                  playerColor: myColor,
                );
                print('   Movable tokens: $movableTokens');
              }
            }

            Duration? timeRemaining;
            if (game.expectedEndTime != null) {
              timeRemaining = game.expectedEndTime!.difference(DateTime.now());
              if (timeRemaining.isNegative) timeRemaining = Duration.zero;
            }

            emit(
              GameLoaded(
                game: game,
                isMyTurn: isMyTurn,
                lastDiceRoll: game.lastDiceRoll > 0 ? game.lastDiceRoll : null,
                movableTokens: movableTokens,
                timeRemaining: timeRemaining, // ✅ Pass calculated time
              ),
            );

            print(
              '   ✅ Emitted: GameLoaded(isMyTurn: $isMyTurn, dice: ${game.lastDiceRoll}, movable: $movableTokens)',
            );
          },
          onError: (error) {
            print('   ❌ Got ERROR: $error');
            emit(GameError('Game error: $error'));
            _isStreamActive = false;
          },
        );

    // ✅ NEW: Periodic timer to refresh UI countdown every second (optional, or just rely on stream?)
    // Firestore stream doesn't update every second.
    _gameTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_currentGameId != null && _currentUserId != null) {
        _checkGameTimer(_currentGameId!, _currentUserId!);
      }
    });

    print('   ✅ Got: Stream started successfully');
  }

  Future<void> _checkGameTimer(String gameId, String userId) async {
    await _gameService.checkGameTimer(gameId, userId);
  }

  // ==================== ROLL DICE ====================

  Future<int> rollDice() async {
    try {
      print('\n🎯 STEP 6: rollDice() executing');
      print('   Expected: Dice value 1-6, game.lastDiceRoll updated');

      if (_currentGameId == null || _currentUserId == null) {
        throw Exception('No active game');
      }

      final diceValue = await _gameService.rollDice(
        gameId: _currentGameId!,
        playerId: _currentUserId!,
      );

      print('   ✅ Got: Rolled $diceValue');

      return diceValue;
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      // emit(GameError('Failed to roll dice: $e')); // Don't emit error to avoid UI rebuild
      rethrow;
    }
  }

  // ==================== MOVE TOKEN ====================

  Future<void> moveToken(int tokenId, int diceRoll) async {
    try {
      print('\n🎯 STEP 7: moveToken() executing');
      print('   Expected: Token position updated, turn passed');
      print('   Token: $tokenId, Dice: $diceRoll');

      if (_currentGameId == null || _currentUserId == null) {
        throw Exception('No active game');
      }

      await _gameService.moveToken(
        gameId: _currentGameId!,
        playerId: _currentUserId!,
        tokenId: tokenId,
        diceRoll: diceRoll,
      );

      print('   ✅ Got: Token moved');

      // Emit an immediate state update clearing lastDiceRoll so UI
      // doesn't wait for the Firestore stream roundtrip.
      final currentState = state;
      if (currentState is GameLoaded) {
        final isSinglePlayer = currentState.game.playerIds.length == 1;

        // The move consumed the roll locally; clear lastDiceRoll.
        // In single-player, it's always the same player's turn
        // In multi-player, turn passes to next player UNLESS they rolled a 6
        final nextIsMyTurn = isSinglePlayer ? true : (diceRoll == 6);

        emit(
          GameLoaded(
            game: currentState.game,
            isMyTurn: nextIsMyTurn,
            lastDiceRoll: null,
            movableTokens: const [],
          ),
        );
      }
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      // emit(GameError('Failed to move token: $e')); // Don't emit error to avoid UI rebuild
      rethrow; // Let UI handle it
    }
  }

  /// Consume a roll when player cannot move - advances turn and clears lastDiceRoll
  Future<void> consumeRoll() async {
    try {
      if (_currentGameId == null || _currentUserId == null) {
        throw Exception('No active game');
      }

      await _gameService.consumeRoll(
        gameId: _currentGameId!,
        playerId: _currentUserId!,
      );

      final currentState = state;
      if (currentState is GameLoaded) {
        final isSinglePlayer = currentState.game.playerIds.length == 1;

        // In single-player mode, it's always the same player's turn
        // In multi-player mode, turn passes to next player (isMyTurn becomes false)
        final nextIsMyTurn = isSinglePlayer ? true : false;

        emit(
          GameLoaded(
            game: currentState.game,
            isMyTurn: nextIsMyTurn,
            lastDiceRoll: null,
            movableTokens: const [],
          ),
        );
      }
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      // emit(GameError('Failed to consume roll: $e')); // Don't emit error to avoid UI rebuild
      rethrow;
    }
  }

  // ==================== LEAVE GAME ====================

  Future<void> leaveGame() async {
    try {
      print('\n🎯 STEP X: leaveGame() executing');

      // First, check if I am the host (first player in list)
      bool isHost = false;
      if (_currentGameId != null) {
        final game = await _databaseService.getGame(_currentGameId!);
        if (game != null &&
            game.playerIds.isNotEmpty &&
            game.playerIds.first == _currentUserId) {
          isHost = true;
        }
      }

      if (isHost && _currentGameId != null) {
        print('   👑 Host leaving - deleting game');
        await _databaseService.deleteGame(_currentGameId!);
      } else if (_currentGameId != null && _currentUserId != null) {
        try {
          await _databaseService.removePlayerFromGame(
            _currentGameId!,
            _currentUserId!,
          );
          print('   ✅ Player removed from game in database');
        } catch (e) {
          print('   ⚠️ Failed to remove player from DB: $e');
        }
      }

      // Then cancel streams and clear local state
      _gameStreamSubscription?.cancel();
      _matchmakingStreamSubscription?.cancel();
      _isStreamActive = false;
      _gameTimer?.cancel();
      _currentGameId = null;
      _currentUserId = null;
      emit(GameInitial());
      print('   ✅ Got: Left game successfully');
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      emit(GameError('Failed to leave: $e'));
    }
  }

  Future<void> leaveGameLobby(String gameId, String userId, bool isHost) async {
    try {
      if (isHost) {
        await _databaseService.deleteGame(gameId);
      } else {
        await _databaseService.removePlayerFromGame(gameId, userId);
      }
      _gameStreamSubscription?.cancel();
      _isStreamActive = false;
      _gameTimer?.cancel();
      _currentGameId = null;
      _currentUserId = null;
      emit(GameInitial());
    } catch (e) {
      emit(GameError('Failed to leave: $e'));
    }
  }

  Stream<List<GameModel>> getAvailableGames(String tier) {
    return _databaseService.getAvailableGamesStream(tier);
  }

  Map<String, int> _calculateRankings(GameModel game) {
    final rankings = <String, int>{};
    if (game.winnerId != null) rankings[game.winnerId!] = 1;
    final playerScores = <String, int>{};
    for (var entry in game.tokenPositions.entries) {
      if (entry.key == game.winnerId) continue;
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

  int _getEntryFee(String tier) {
    const fees = {'bronze': 100, 'silver': 500, 'gold': 1000};
    return fees[tier.toLowerCase()] ?? 100;
  }

  int _getPrizePool(String tier) {
    const prizes = {'bronze': 500, 'silver': 2500, 'gold': 5000};
    return prizes[tier.toLowerCase()] ?? 500;
  }

  void clear() {
    _gameStreamSubscription?.cancel();
    _matchmakingStreamSubscription?.cancel();
    _isStreamActive = false;
    _currentGameId = null;
    _currentUserId = null;
    emit(GameInitial());
  }

  @override
  Future<void> close() {
    _gameStreamSubscription?.cancel();
    _matchmakingStreamSubscription?.cancel();
    _isStreamActive = false;
    _gameTimer?.cancel();
    return super.close();
  }
}
