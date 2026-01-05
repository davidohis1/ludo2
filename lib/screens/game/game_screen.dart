import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:math';
import 'dart:async';
import '../../models/game_model.dart';
import '../../cubits/game/game_cubit.dart';
import '../../cubits/auth/auth_cubit.dart';
import '../../constants/colors.dart';
import '../../utils/toast_utils.dart';

class GameScreen extends StatefulWidget {
  final String gameId;

  const GameScreen({super.key, required this.gameId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  Timer? _gameTimer; // For turn countdown
  int turnTimeRemaining = 10;

  Timer? _gameEndTimer; // For 7-min game countdown
  Duration gameTimeRemaining = Duration.zero;

  int? diceValue;
  bool isDiceRolling = false;
  bool canRollDice = false;

  late AnimationController _diceController;
  late Animation<double> _diceAnimation;

  String? _myPlayerId;
  String?
  _lastCurrentPlayerId; // ✅ Track turn changes to prevent timer reset on every state update
  double boardScaleFactor = 1;

  // Game event messages
  final List<String> _gameEvents = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    print('🎮 [SCREEN] GameScreen initialized with gameId: ${widget.gameId}');

    // ✅ CRITICAL: Join the game on init
    _joinGame();
  }

  void _initializeAnimations() {
    _diceController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _diceAnimation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _diceController, curve: Curves.easeInOut),
    );
  }

  // ✅ Join game when screen opens
  Future<void> _joinGame() async {
    try {
      print('\n🎯 STEP 4A: GameScreen._joinGame() executing');
      print('   Expected: GameCubit.joinGame() called');

      final authState = context.read<AuthCubit>().state;
      if (authState is! AuthAuthenticated) {
        throw 'Not authenticated';
      }

      _myPlayerId = authState.userId;
      print('   My player ID: $_myPlayerId');
      print('   Game ID: ${widget.gameId}');

      // ✅ FORCE: Always call joinGame - let Cubit decide what to do
      await context.read<GameCubit>().joinGame(widget.gameId, _myPlayerId!);

      // ✅ CRITICAL: If state is already GameLoaded, manually trigger setup
      final currentState = context.read<GameCubit>().state;
      if (currentState is GameLoaded) {
        print('   🔄 State already loaded - manually triggering setup');

        // Manually call the listener logic
        _handleGameLoadedState(currentState);
      }

      print('   ✅ Got: joinGame() completed');
    } catch (e) {
      print('   ❌ Got ERROR: $e');
      if (mounted) {
        ToastUtils.showSuccess(context, 'Failed to join game: $e');
      }
    }
  }

  void _handleGameLoadedState(GameLoaded state) {
    final game = state.game;
    final currentPlayerName = _getPlayerName(game, game.currentPlayerId);
    final isSinglePlayer = game.playerIds.length == 1;

    final turnChanged = _lastCurrentPlayerId != game.currentPlayerId;
    _lastCurrentPlayerId = game.currentPlayerId;
    if (state.timeRemaining != null) {
      gameTimeRemaining = state.timeRemaining!;
      _startLocalGameTimer();
    }
    if (state.isMyTurn) {
      _addGameEvent('🎯 YOUR TURN!');

      // ✅ CRITICAL FIX: Only start timer when turn changes, not on every state update
      if (turnChanged) {
        _startTurnTimer();
      }
      setState(() {
        // Sync game timer from state

        canRollDice = state.lastDiceRoll == null || state.lastDiceRoll == 0;
        diceValue = (state.lastDiceRoll != null && state.lastDiceRoll! > 0)
            ? state.lastDiceRoll
            : null;
      });

      // Check for rolled 6 (gets another turn after moving)
      if (state.lastDiceRoll == 6) {
        _addGameEvent('🎉 You rolled a 6! Move a token, then roll again');
      }

      // If there's a dice roll but no movable tokens, auto-consume the roll (pass)
      // BUT: Skip this in single-player mode - player keeps their turn
      if (!isSinglePlayer &&
          state.lastDiceRoll != null &&
          state.lastDiceRoll! > 0 &&
          state.movableTokens.isEmpty) {
        // Guard: A 6 should almost never be auto-consumed unless truly blocked.
        // We'll proceed but with strict checking.
        _addGameEvent('Checking if need to pass turn...');

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            // 🛡️ SECURITY GUARD: Wait a brief moment to ensure state is stable
            // and no other updates (like movable tokens calculation) are pending.
            await Future.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;

            // 🛡️ DOUBLE CHECK: Re-read the *latest* state to ensure we truly have no moves.
            final currentState = context.read<GameCubit>().state;
            if (currentState is GameLoaded &&
                currentState.isMyTurn &&
                currentState.lastDiceRoll != null &&
                currentState.lastDiceRoll! > 0 &&
                currentState.movableTokens.isEmpty) {
              print(
                '🔒 [SCREEN] Auto-consuming roll ${currentState.lastDiceRoll} confirmed - No moves available',
              );
              _addGameEvent('⏩ No moves - passing turn');
              context.read<GameCubit>().consumeRoll();
            } else {
              print(
                '🛑 [SCREEN] Auto-consume ABORTED - State changed or moves became available',
              );
            }
          }
        });
      } else if (isSinglePlayer &&
          state.lastDiceRoll != null &&
          state.lastDiceRoll! > 0 &&
          state.movableTokens.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            // 🛡️ Same guard for single player
            await Future.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;

            final currentState = context.read<GameCubit>().state;
            if (currentState is GameLoaded &&
                currentState.movableTokens.isEmpty &&
                currentState.lastDiceRoll != null &&
                currentState.lastDiceRoll! > 0) {
              _addGameEvent('⚠️ No moves - roll again');
              context.read<GameCubit>().consumeRoll();
            }
          }
        });
      }
    } else {
      // In single-player mode, this shouldn't happen (you're always the current player)
      if (isSinglePlayer) {
        _addGameEvent('🎮 Single Player Mode');
      } else {
        _addGameEvent('⏳ $currentPlayerName\'s turn');
      }
      _gameTimer?.cancel();
      setState(() {
        canRollDice = false;
      });
    }
  }

  @override
  void dispose() {
    _diceController.dispose();
    _gameTimer?.cancel();
    _gameEndTimer?.cancel();
    super.dispose();
  }

  void _startTurnTimer() {
    print('⏱️ [SCREEN] Starting turn timer');
    _gameTimer?.cancel();

    setState(() {
      turnTimeRemaining = 10;
    });

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        turnTimeRemaining--;
      });

      if (turnTimeRemaining <= 0) {
        timer.cancel();
        print('⏰ [SCREEN] Turn timeout!');
      }
    });
  }

  void _startLocalGameTimer() {
    if (_gameEndTimer != null && _gameEndTimer!.isActive) return;

    _gameEndTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (gameTimeRemaining.inSeconds > 0) {
          gameTimeRemaining = gameTimeRemaining - const Duration(seconds: 1);
        } else {
          timer.cancel();
        }
      });
    });
  }

  void _addGameEvent(String event) {
    setState(() {
      _gameEvents.insert(0, event);
      if (_gameEvents.length > 5) {
        _gameEvents.removeLast();
      }
    });
  }

  void _showWinDialog(
    GameModel game,
    String winnerId,
    Map<String, int> rankings,
  ) {
    final isWinner = winnerId == _myPlayerId;
    final winnerName = game.playerNames[winnerId] ?? 'Player';

    showDialog(
      context: context,
      barrierDismissible: false, // Must use button to close
      builder: (context) => AlertDialog(
        title: Text(
          isWinner ? '🏆 YOU WON!' : '😔 Game Over',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isWinner ? Colors.green : Colors.orange,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isWinner)
              Text(
                '$winnerName won the game!',
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            Text(
              'Prize: ${game.prizePool} coins',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text(
              'Final Rankings:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...rankings.entries.map((entry) {
              final playerName = game.playerNames[entry.key] ?? 'Player';
              final rank = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '#$rank - $playerName',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: entry.key == _myPlayerId
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              context.read<GameCubit>().leaveGame();
              Navigator.pop(context); // Leave game screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: const Text(
              'Back to Home',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rollDice() async {
    print('🎲 [SCREEN] Attempting to roll dice...');
    if (!canRollDice || isDiceRolling) {
      print(
        '🚫 [SCREEN] Cannot roll dice - canRoll: $canRollDice, isRolling: $isDiceRolling',
      );
      return;
    }

    print('🎲 [SCREEN] Rolling dice...');

    setState(() {
      isDiceRolling = true;
      canRollDice = false;
    });

    // Start animation
    _diceController.repeat();

    try {
      // Call cubit to roll dice
      final newDiceValue = await context.read<GameCubit>().rollDice();

      print('✅ [SCREEN] Rolled: $newDiceValue');
      _addGameEvent('🎲 You rolled a $newDiceValue');

      if (mounted) {
        // Stop animation
        _diceController.stop();
        _diceController.reset();

        setState(() {
          diceValue = newDiceValue;
          isDiceRolling = false;
        });
        print('reached here');
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
      }
    } catch (e) {
      print('❌ [SCREEN] Dice roll error: $e');

      if (mounted) {
        _diceController.stop();
        _diceController.reset();

        setState(() {
          isDiceRolling = false;
          canRollDice = true;
        });

        // ToastUtils.showError(context, 'Failed to roll dice: $e');
      }
    }
  }

  Future<void> _movePiece(TokenPosition token) async {
    if (diceValue == null) {
      print('🚫 [SCREEN] No dice value to move with');
      return;
    }

    _addGameEvent('🏃 Moving token ${token.tokenId + 1}');
    print('token position: ${token.position}');
    try {
      if (token.position == 1) {
        await context.read<GameCubit>().moveToken(token.tokenId, diceValue!);
      } else {
        await context.read<GameCubit>().moveToken(token.tokenId, diceValue!);
      }
      if (mounted) {
        setState(() {
          diceValue = null;
        });
      }

      print('✅ [SCREEN] Token moved successfully');
      _addGameEvent('✅ Token ${token.tokenId + 1} moved');
    } catch (e) {
      print('❌ [SCREEN] Move error: $e');
      _addGameEvent('❌ Move failed');

      if (mounted) {
        // ToastUtils.showError(context, 'Failed to move token: $e');
      }
    }
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Color _getPlayerColorValue(PlayerColor playerColor) {
    switch (playerColor) {
      case PlayerColor.red:
        return Colors.red;
      case PlayerColor.blue:
        return Colors.blue;
      case PlayerColor.yellow:
        return Colors.yellow[700]!;
      case PlayerColor.green:
        return Colors.green;
    }
  }

  String _getPlayerName(GameModel game, String playerId) {
    if (playerId == _myPlayerId) return 'You';
    return game.playerNames[playerId] ?? 'Player';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave Game?'),
            content: const Text('Are you sure you want to leave this game?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (shouldLeave == true) {
          // Leave game and wait for it to complete
          await context.read<GameCubit>().leaveGame();
          // Then navigate back to home
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }

        return false; // Don't let WillPopScope handle it - we already navigated
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5DC),
        body: BlocConsumer<GameCubit, GameState>(
          listener: (context, state) {
            print('\n📊 GAMESCREEN STATE CHANGE: ${state.runtimeType}');

            if (state is GameLoaded) {
              _handleGameLoadedState(state); // ✅ Use extracted method
            } else if (state is GameCompleted) {
              _addGameEvent('🏆 GAME OVER!');
              _showWinDialog(state.game, state.winnerId, state.rankings);
            } else if (state is GameError) {
              // ✅ NEW: Handle game not found (deleted by host)
              if (state.message.contains('Game not found')) {
                ToastUtils.showError(context, 'Game ended by host');
                Navigator.of(context).popUntil((route) => route.isFirst);
                return;
              }

              _addGameEvent('❌ Error: ${state.message}');
              ToastUtils.showError(context, state.message);
            }
          },
          builder: (context, state) {
            if (state is GameLoading) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      state.message ?? 'Loading game...',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              );
            }

            // ✅ FIX: Don't show waiting screen when game is completed (dialog handles it)
            if (state is GameCompleted) {
              return const SizedBox.shrink();
            }

            if (state is! GameLoaded) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading game...',
                    ), // ✅ Changed from "Waiting for game to start"
                  ],
                ),
              );
            }

            final game = state.game;

            print(
              '🎨 [SCREEN] Building UI with ${game.playerIds.length} players',
            );

            return SafeArea(
              child: Column(
                children: [
                  // Game Events Feed & Game Timer
                  Row(
                    children: [
                      Expanded(child: _buildGameEventsFeed()),
                      _buildGameTimer(),
                    ],
                  ),
                  
                  // if (!(state.game.playerIds.length == 1)) _buildTurnTimer(),
                  _buildPlayers(game),

                  

                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: _buildGameBoard(
                            game,
                            _myPlayerId ?? game.playerIds.first,
                            state.movableTokens,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Turn indicator
                  _buildTurnIndicator(game, state.isMyTurn),

                  const SizedBox(height: 8),
                  _buildDiceButton(game, state.isMyTurn),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ✅ NEW: Game events feed at top
  Widget _buildGameEventsFeed() {
    return Container(
      height: 100,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Game Info',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _gameEvents.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for game to start...',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    reverse: false,
                    itemCount: _gameEvents.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _gameEvents[index],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Turn indicator
  Widget _buildTurnIndicator(GameModel game, bool isMyTurn) {
    final isSinglePlayer = game.playerIds.length == 1;
    final currentPlayerName = _getPlayerName(game, game.currentPlayerId);
    final currentColor = game.playerColors[game.currentPlayerId];
    final colorValue = currentColor != null
        ? _getPlayerColorValue(currentColor)
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isMyTurn ? colorValue.withOpacity(0.2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorValue, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSinglePlayer
                ? Icons.person
                : (isMyTurn ? Icons.touch_app : Icons.hourglass_empty),
            color: colorValue,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isSinglePlayer
                ? 'Single Player - Roll the dice!'
                : (isMyTurn
                      ? 'YOUR TURN - Roll the dice!'
                      : '$currentPlayerName is playing...'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorValue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnTimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            color: turnTimeRemaining <= 10 ? Colors.red : AppColors.primaryRed,
          ),
          const SizedBox(width: 8),
          Text(
            'Turn: ${_formatTime(turnTimeRemaining)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: turnTimeRemaining <= 10 ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameTimer() {
    // Format duration mm:ss
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(gameTimeRemaining.inMinutes.remainder(60));
    final seconds = twoDigits(gameTimeRemaining.inSeconds.remainder(60));

    // Determine timer color based on time remaining
    Color timerColor;
    if (gameTimeRemaining.inSeconds <= 60) {
      timerColor = Colors.red[900]!; // Red for last minute
    } else if (gameTimeRemaining.inSeconds <= 180) {
      timerColor = Colors.orange[800]!; // Orange for last 3 minutes
    } else {
      timerColor = Colors.blue[800]!; // Blue for normal time
    }

    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: timerColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "GAME TIME",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            gameTimeRemaining.inSeconds > 0 ? "$minutes:$seconds" : "--:--",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayers(GameModel game) {
    final playerIds = game.playerIds;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: playerIds.map((playerId) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildPlayerInfo(
              game,
              playerId,
              isActive: game.currentPlayerId == playerId,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlayerInfo(
    GameModel game,
    String playerId, {
    required bool isActive,
  }) {
    final playerName = _getPlayerName(game, playerId);
    final playerColor = game.playerColors[playerId];
    final colorValue = playerColor != null
        ? _getPlayerColorValue(playerColor)
        : Colors.grey;
    final tokens = game.tokenPositions[playerId] ?? [];
    final finishedCount = tokens.where((t) => t.isFinished).length;
    final isMe = playerId == _myPlayerId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? colorValue.withOpacity(0.2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? colorValue : Colors.grey.withOpacity(0.3),
          width: isActive ? 3 : 1,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: colorValue.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorValue,
                backgroundImage:
                    game.playerPhotos[playerId] != null &&
                        game.playerPhotos[playerId]!.isNotEmpty
                    ? NetworkImage(game.playerPhotos[playerId]!)
                    : null,
                child:
                    game.playerPhotos[playerId] == null ||
                        game.playerPhotos[playerId]!.isEmpty
                    ? Text(
                        game.playerNames[playerId]![0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              if (isMe)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                playerName,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                  color: isActive ? colorValue : Colors.black87,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text(
                    'Score: ${game.playerScores[playerId] ?? 0}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiceButton(GameModel game, bool isMyTurn) {
    final currentColor = game.playerColors[game.currentPlayerId];
    final colorValue = currentColor != null
        ? _getPlayerColorValue(currentColor)
        : Colors.grey;

    return AnimatedBuilder(
      animation: _diceAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _diceAnimation.value,
          child: GestureDetector(
            onTap: canRollDice && isMyTurn ? _rollDice : null,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: canRollDice && isMyTurn
                    ? LinearGradient(
                        colors: [colorValue, colorValue.withOpacity(0.85)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(colors: [Colors.grey, Colors.grey[600]!]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: diceValue != null && diceValue! > 0
                    ? Text(
                        diceValue.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : const Icon(
                        Icons.casino,
                        color: Colors.white,
                        size: 38,
                      ), // Scaled up from 42
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGameBoard(
    GameModel game,
    String myPlayerId,
    List<int> movableTokens,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double size = constraints.maxWidth * boardScaleFactor;
        double cellSize = size / 15;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // Board background
                CustomPaint(
                  size: Size(size, size),
                  painter: LudoBoardPainter(cellSize: cellSize),
                ),

                // Render all player tokens
                ...game.tokenPositions.entries.expand((entry) {
                  final playerId = entry.key;
                  final tokens = entry.value;
                  final playerColor = game.playerColors[playerId];

                  if (playerColor == null) return [const SizedBox.shrink()];

                  final colorValue = _getPlayerColorValue(playerColor);
                  final isMyPlayer = playerId == myPlayerId;

                  return tokens.map((token) {
                    // Render finished tokens at the side of the board
                    if (token.isFinished) {
                      // Finished tokens render at the side based on color
                      final finishedOffset = _getFinishedTokenPosition(
                        token,
                        playerColor,
                        cellSize,
                        size,
                      );

                      return Positioned(
                        left: finishedOffset.dx,
                        top: finishedOffset.dy,
                        child: Container(
                          width: cellSize * 0.85,
                          height: cellSize * 0.85,
                          decoration: BoxDecoration(
                            color: colorValue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.amber, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.8),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${token.tokenId + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 8,
                                shadows: [
                                  Shadow(color: Colors.black45, blurRadius: 2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    // Handle home tokens - render in home areas
                    if (token.isHome) {
                      return _renderHomeToken(
                        token: token,
                        playerColor: playerColor,
                        colorValue: colorValue,
                        isMyPlayer: isMyPlayer,
                        isMovable:
                            isMyPlayer &&
                            movableTokens.contains(token.tokenId) &&
                            diceValue != null &&
                            diceValue! > 0,
                        cellSize: cellSize,
                        boardSize: size,
                      );
                    }

                    // Render tokens on the board
                    final position = _getPiecePosition(
                      token.position,
                      playerColor,
                      cellSize,
                      size,
                    );

                    final isMovable =
                        isMyPlayer &&
                        movableTokens.contains(token.tokenId) &&
                        diceValue != null &&
                        diceValue! > 0;

                    return Positioned(
                      left: position.dx,
                      top: position.dy,
                      child: GestureDetector(
                        onTap: isMovable ? () => _movePiece(token) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: cellSize * 0.85,
                          height: cellSize * 0.85,
                          decoration: BoxDecoration(
                            color: colorValue,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isMovable
                                  ? Colors.yellowAccent
                                  : Colors.white,
                              width: isMovable ? 4 : 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isMovable
                                    ? Colors.yellowAccent.withOpacity(0.6)
                                    : Colors.black.withOpacity(0.3),
                                blurRadius: isMovable ? 12 : 4,
                                spreadRadius: isMovable ? 2 : 0,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${token.tokenId + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 8,
                                shadows: [
                                  Shadow(color: Colors.black45, blurRadius: 2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList();
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Offset _getFinishedTokenPosition(
    TokenPosition token,
    PlayerColor playerColor,
    double cellSize,
    double boardSize,
  ) {
    // ✅ IMPROVED: Render finished tokens VISIBLY outside the board
    final tokenIndex = token.tokenId; // 0-3
    final finishedTokenSpacing =
        cellSize * 1.5; // Increased spacing for visibility

    switch (playerColor) {
      case PlayerColor.red:
        // Red finished tokens appear on the LEFT side (more visible)
        return Offset(
          -cellSize * 1.5, // Further left for visibility
          cellSize * 6 + (tokenIndex * finishedTokenSpacing),
        );
      case PlayerColor.blue:
        // Blue finished tokens appear on the TOP side
        return Offset(
          cellSize * 6 + (tokenIndex * finishedTokenSpacing),
          -cellSize * 1.5, // Further up for visibility
        );
      case PlayerColor.yellow:
        // Yellow finished tokens appear on the RIGHT side
        return Offset(
          boardSize + cellSize * 0.5, // Further right for visibility
          cellSize * 6 + (tokenIndex * finishedTokenSpacing),
        );
      case PlayerColor.green:
        // Green finished tokens appear on the BOTTOM side
        return Offset(
          cellSize * 6 + (tokenIndex * finishedTokenSpacing),
          boardSize + cellSize * 0.5, // Further down for visibility
        );
    }
  }

  Offset _getPiecePosition(
    int position,
    PlayerColor playerColor,
    double cellSize,
    double boardSize,
  ) {
    // ✅ USER-SPECIFIED EXACT MOVEMENT PATHS
    // ======================================
    // All colors follow a SHARED perimeter path!
    // They enter at different points and exit into their own safe houses.
    // The shared perimeter loop is approximately 52 squares.

    // The complete shared perimeter that all tokens follow
    final sharedPerimeter = [
      // RED's starting segment
      // const _GridPos(6, 1),
      const _GridPos(6, 2),
      const _GridPos(6, 3),
      const _GridPos(6, 4),
      const _GridPos(6, 5), // Red exit from home
      const _GridPos(5, 6),
      const _GridPos(4, 6),
      const _GridPos(3, 6),
      const _GridPos(2, 6),
      const _GridPos(1, 6),
      const _GridPos(0, 6), // Up left column
      const _GridPos(0, 7), const _GridPos(0, 8), // Top left corner
      const _GridPos(1, 8),
      const _GridPos(2, 8),
      const _GridPos(3, 8),
      const _GridPos(4, 8),
      const _GridPos(5, 8), // Down from top left (BLUE area)
      const _GridPos(6, 9),
      const _GridPos(6, 10),
      const _GridPos(6, 11),
      const _GridPos(6, 12),
      const _GridPos(6, 13),
      const _GridPos(6, 14), // Right across top
      const _GridPos(7, 14),
      const _GridPos(8, 14),
      const _GridPos(8, 13),

      const _GridPos(8, 12),
      const _GridPos(8, 11),
      const _GridPos(8, 10),
      const _GridPos(8, 9), // GREEN entry area
      const _GridPos(9, 8),
      const _GridPos(10, 8),
      const _GridPos(11, 8),
      const _GridPos(12, 8),
      const _GridPos(13, 8),
      const _GridPos(14, 8), // Down right column
      const _GridPos(14, 7), const _GridPos(14, 6), // Bottom right corner
      const _GridPos(13, 6),
      const _GridPos(12, 6),
      const _GridPos(11, 6),
      const _GridPos(10, 6),
      const _GridPos(9, 6), // Left across bottom (YELLOW area)
      const _GridPos(8, 5),
      const _GridPos(8, 4),
      const _GridPos(8, 3),
      const _GridPos(8, 2),
      const _GridPos(8, 1),
      const _GridPos(8, 0), // Up left column back to edge
    ];

    final redPath = [
      ...sharedPerimeter,
      // After full perimeter loop, RED enters its safe house at (7,0)
      const _GridPos(7, 0),
      const _GridPos(7, 1),
      const _GridPos(7, 2),
      const _GridPos(7, 3),
      const _GridPos(7, 4),
      const _GridPos(7, 5), // Red safe house
      // const _GridPos(7, 6), // Finished
    ];

    final greenPath = [
      // GREEN starts at (8,13) which is in the perimeter
      // From its entry, it continues the shared path
      // const _GridPos(8, 13),
      const _GridPos(8, 12),
      const _GridPos(8, 11),
      const _GridPos(8, 10),
      const _GridPos(8, 9), // Towards (9,8)
      const _GridPos(9, 8),
      const _GridPos(10, 8),
      const _GridPos(11, 8),
      const _GridPos(12, 8),
      const _GridPos(13, 8),
      const _GridPos(14, 8), // Down right column
      const _GridPos(14, 7), const _GridPos(14, 6), // Bottom right corner
      const _GridPos(13, 6),
      const _GridPos(12, 6),
      const _GridPos(11, 6),
      const _GridPos(10, 6),
      const _GridPos(9, 6), // Left across bottom
      const _GridPos(8, 5),
      const _GridPos(8, 4),
      const _GridPos(8, 3),
      const _GridPos(8, 2),
      const _GridPos(8, 1),
      const _GridPos(8, 0), // Up left column
      const _GridPos(7, 0),
      const _GridPos(6, 0),
      const _GridPos(6, 1),
      const _GridPos(6, 2),
      const _GridPos(6, 3),
      const _GridPos(6, 4),
      const _GridPos(6, 5), // Continue shared path
      const _GridPos(5, 6),
      const _GridPos(4, 6),
      const _GridPos(3, 6),
      const _GridPos(2, 6),
      const _GridPos(1, 6),
      const _GridPos(0, 6), // Up left column
      const _GridPos(0, 7), const _GridPos(0, 8), // Top left corner
      const _GridPos(1, 8),
      const _GridPos(2, 8),
      const _GridPos(3, 8),
      const _GridPos(4, 8),
      const _GridPos(5, 8), // Down from top left
      const _GridPos(6, 9),
      const _GridPos(6, 10),
      const _GridPos(6, 11),
      const _GridPos(6, 12),
      const _GridPos(6, 13),
      const _GridPos(6, 14), // Right across top
      // GREEN enters its safe house at (7,14)
      const _GridPos(7, 14),
      const _GridPos(7, 13),
      const _GridPos(7, 12),
      const _GridPos(7, 11),
      const _GridPos(7, 10),
      const _GridPos(7, 9),
      // const _GridPos(7, 8), // Green safe house
    ];

    final yellowPath = [
      // YELLOW starts at (13,6) which is in the perimeter
      // const _GridPos(13, 6),
      const _GridPos(12, 6),
      const _GridPos(11, 6),
      const _GridPos(10, 6),
      const _GridPos(9, 6), // Towards (8,5)
      const _GridPos(8, 5),
      const _GridPos(8, 4),
      const _GridPos(8, 3),
      const _GridPos(8, 2),
      const _GridPos(8, 1),
      const _GridPos(8, 0), // Up left column
      const _GridPos(7, 0),
      const _GridPos(6, 0),
      const _GridPos(6, 1),
      const _GridPos(6, 2),
      const _GridPos(6, 3),
      const _GridPos(6, 4),
      const _GridPos(6, 5), // Continue shared path
      const _GridPos(5, 6),
      const _GridPos(4, 6),
      const _GridPos(3, 6),
      const _GridPos(2, 6),
      const _GridPos(1, 6),
      const _GridPos(0, 6), // Up left column
      const _GridPos(0, 7), const _GridPos(0, 8), // Top left corner
      const _GridPos(1, 8),
      const _GridPos(2, 8),
      const _GridPos(3, 8),
      const _GridPos(4, 8),
      const _GridPos(5, 8), // Down from top left
      const _GridPos(6, 9),
      const _GridPos(6, 10),
      const _GridPos(6, 11),
      const _GridPos(6, 12),
      const _GridPos(6, 13),
      const _GridPos(6, 14), // Right across top
      const _GridPos(7, 14),
      const _GridPos(8, 14),
      const _GridPos(8, 13),
      const _GridPos(8, 12),
      const _GridPos(8, 11),
      const _GridPos(8, 10),
      const _GridPos(8, 9), // To green area
      const _GridPos(9, 8),
      const _GridPos(10, 8),
      const _GridPos(11, 8),
      const _GridPos(12, 8),
      const _GridPos(13, 8),
      const _GridPos(14, 8), // Down right column
      const _GridPos(14, 7), // YELLOW enters its safe house at (14,7)
      const _GridPos(13, 7),
      const _GridPos(12, 7),
      const _GridPos(11, 7),
      const _GridPos(10, 7),
      const _GridPos(9, 7),
      // const _GridPos(8, 7), // Yellow safe house
    ];

    final bluePath = [
      // BLUE starts at (1,8) which is in the perimeter (top-left area)
      // const _GridPos(1, 8),
      const _GridPos(2, 8),
      const _GridPos(3, 8),
      const _GridPos(4, 8),
      const _GridPos(5, 8), // Continue right from entry
      const _GridPos(6, 9),
      const _GridPos(6, 10),
      const _GridPos(6, 11),
      const _GridPos(6, 12),
      const _GridPos(6, 13),
      const _GridPos(6, 14), // Right across top
      const _GridPos(8, 14),
      const _GridPos(8, 13),
      const _GridPos(8, 12),
      const _GridPos(8, 11),
      const _GridPos(8, 10),
      const _GridPos(8, 9), // To GREEN area
      const _GridPos(9, 8),
      const _GridPos(10, 8),
      const _GridPos(11, 8),
      const _GridPos(12, 8),
      const _GridPos(13, 8),
      const _GridPos(14, 8), // Down right column
      const _GridPos(14, 7), const _GridPos(14, 6), // Bottom right corner
      const _GridPos(13, 6),
      const _GridPos(12, 6),
      const _GridPos(11, 6),
      const _GridPos(10, 6),
      const _GridPos(9, 6), // Left across bottom
      const _GridPos(8, 5),
      const _GridPos(8, 4),
      const _GridPos(8, 3),
      const _GridPos(8, 2),
      const _GridPos(8, 1),
      const _GridPos(8, 0), // Up left column
      const _GridPos(7, 0),
      const _GridPos(6, 0),
      const _GridPos(6, 1),
      const _GridPos(6, 2),
      const _GridPos(6, 3),
      const _GridPos(6, 4),
      const _GridPos(6, 5), // Continue shared path
      const _GridPos(5, 6),
      const _GridPos(4, 6),
      const _GridPos(3, 6),
      const _GridPos(2, 6),
      const _GridPos(1, 6),
      const _GridPos(0, 6), // Up left column
      const _GridPos(0, 7),
      const _GridPos(0, 8), // Back to top left corner - perimeter complete
      // ✅ BLUE safe house: (0,7) → (1,7) → (2,7) → (3,7) → (4,7) → (5,7) → finish (6,7)
      const _GridPos(1, 7),
      const _GridPos(2, 7),
      const _GridPos(3, 7),
      const _GridPos(4, 7),
      const _GridPos(5, 7),
      // const _GridPos(6, 7), // Blue safe house - HORIZONTAL
    ];

    _GridPos gridCoords = const _GridPos(7, 7); // Default to center

    if (position == 0) {
      // Token is at home - render in home corner
      switch (playerColor) {
        case PlayerColor.red:
          gridCoords = const _GridPos(6, 1); // RED home corner
          break;
        case PlayerColor.blue:
          gridCoords = const _GridPos(1, 8); // BLUE home corner
          break;
        case PlayerColor.yellow:
          gridCoords = const _GridPos(8, 13); // YELLOW home corner
          break;
        case PlayerColor.green:
          gridCoords = const _GridPos(13, 6); // GREEN home corner
          break;
      }
    } else {
      // Use player's specific path
      final List<_GridPos> currentPath;
      switch (playerColor) {
        case PlayerColor.red:
          currentPath = redPath;
          break;
        case PlayerColor.green:
          currentPath = greenPath;
          break;
        case PlayerColor.yellow:
          currentPath = yellowPath;
          break;
        case PlayerColor.blue:
          currentPath = bluePath;
          break;
      }

      // ✅ FIXED: Position is 1-based index (0 is home)
      // position 1 = path[0], position 2 = path[1], etc.
      if (position > 0 && position <= currentPath.length) {
        gridCoords = currentPath[position - 1];
      } else if (position > currentPath.length) {
        // Beyond path array - stay at last position (finish)
        gridCoords = currentPath.last;
      }
    }

    final row = gridCoords.row;
    final col = gridCoords.col;

    return Offset(
      col * cellSize + (cellSize * 0.15),
      row * cellSize + (cellSize * 0.15),
    );
  }

  Widget _renderHomeToken({
    required TokenPosition token,
    required PlayerColor playerColor,
    required Color colorValue,
    required bool isMyPlayer,
    required bool isMovable,
    required double cellSize,
    required double boardSize,
  }) {
    // Calculate home area positions based on player color
    // Red: top-left (0,0), Blue: top-right (9,0), Yellow: bottom-right (9,9), Green: bottom-left (0,9)
    final homeOffsets = {
      PlayerColor.red: [
        Offset(cellSize * 1, cellSize * 1),
        Offset(cellSize * 4, cellSize * 1),
        Offset(cellSize * 1, cellSize * 4),
        Offset(cellSize * 4, cellSize * 4),
      ],
      PlayerColor.blue: [
        Offset(cellSize * 10, cellSize * 1),
        Offset(cellSize * 13, cellSize * 1),
        Offset(cellSize * 10, cellSize * 4),
        Offset(cellSize * 13, cellSize * 4),
      ],
      PlayerColor.yellow: [
        Offset(cellSize * 10, cellSize * 10),
        Offset(cellSize * 13, cellSize * 10),
        Offset(cellSize * 10, cellSize * 13),
        Offset(cellSize * 13, cellSize * 13),
      ],
      PlayerColor.green: [
        Offset(cellSize * 1, cellSize * 10),
        Offset(cellSize * 4, cellSize * 10),
        Offset(cellSize * 1, cellSize * 13),
        Offset(cellSize * 4, cellSize * 13),
      ],
    };

    final offset = homeOffsets[playerColor]?[token.tokenId] ?? Offset.zero;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onTap: isMovable ? () => _movePiece(token) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: cellSize * 0.85,
          height: cellSize * 0.85,
          decoration: BoxDecoration(
            color: colorValue,
            shape: BoxShape.circle,
            border: Border.all(
              color: isMovable ? Colors.yellowAccent : Colors.white,
              width: isMovable ? 3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isMovable
                    ? Colors.yellowAccent.withOpacity(0.6)
                    : Colors.black.withOpacity(0.3),
                blurRadius: isMovable ? 8 : 2,
                spreadRadius: isMovable ? 1 : 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${token.tokenId + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 8,
                shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== BOARD PAINTER ====================

class LudoBoardPainter extends CustomPainter {
  final double cellSize;

  LudoBoardPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = const Color(0xFFF5F5DC);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw main board path (outer squares)
    _drawMainBoardPath(canvas);

    // Draw home areas (4 corners) - yards
    _drawHomeArea(canvas, cellSize * 0, cellSize * 0, Colors.red);
    _drawHomeArea(canvas, cellSize * 9, cellSize * 0, Colors.blue);
    _drawHomeArea(canvas, cellSize * 0, cellSize * 9, Colors.yellow[700]!);
    _drawHomeArea(canvas, cellSize * 9, cellSize * 9, Colors.green);

    // ✅ Draw colored HOME COLUMN paths with edge positioning
    // RED: Top column - color line at LEFT EDGE (column 6), path from row 1-5
    _drawHomeColumnPath(canvas, 1, 7, 5, 8, Colors.red, isVertical: false);

    _drawHomeColumnPath(canvas, 1, 6, 4, 6, Colors.red, isVertical: true);
    // BLUE: Right column - color line at TOP EDGE (row 6), path from col 8-12
    _drawHomeColumnPath(canvas, 7, 1, 12, 6, Colors.blue, isVertical: true);
    _drawHomeColumnPath(canvas, 8, 1, 8, 6, Colors.blue, isVertical: false);

    // YELLOW: Bottom column - color line at RIGHT EDGE (column 8), path from row 8-12
    _drawHomeColumnPath(
      canvas,
      7,
      6,
      6,
      13,
      Colors.yellow[700]!,
      isVertical: true,
    );
    _drawHomeColumnPath(
      canvas,
      7,
      13,
      6,
      8,
      Colors.yellow[700]!,
      isVertical: false,
    );

    // GREEN: Left column - color line at BOTTOM EDGE (row 8), path from col 1-5
    _drawHomeColumnPath(canvas, 13, 7, 6, 08, Colors.green, isVertical: false);
    _drawHomeColumnPath(canvas, 13, 8, 5, 8, Colors.green, isVertical: true);

    // ✅ Draw colored START squares for each side
    _drawStartSquare(
      canvas,
      6,
      6,
      Colors.red,
    ); // Red start square (top-left area)
    _drawStartSquare(
      canvas,
      8,
      6,
      Colors.blue,
    ); // Blue start square (top-right area)
    _drawStartSquare(
      canvas,
      8,
      8,
      Colors.yellow[700]!,
    ); // Yellow start square (bottom-right area)
    _drawStartSquare(
      canvas,
      6,
      8,
      Colors.green,
    ); // Green start square (bottom-left area)

    // ✅ Draw center square (BLACK) - the finishing square
    final centerPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(cellSize * 6, cellSize * 6, cellSize * 3, cellSize * 3),
      centerPaint,
    );

    // Draw center border
    final centerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromLTWH(cellSize * 6, cellSize * 6, cellSize * 3, cellSize * 3),
      centerBorderPaint,
    );

    // Draw home areas (4 corners) - yards
    _drawHomeArea(canvas, cellSize * 0, cellSize * 0, Colors.red);
    _drawHomeArea(canvas, cellSize * 9, cellSize * 0, Colors.blue);
    _drawHomeArea(canvas, cellSize * 0, cellSize * 9, Colors.yellow[700]!);
    _drawHomeArea(canvas, cellSize * 9, cellSize * 9, Colors.green);

    // Draw starting positions (entry squares)
    _drawStartPosition(canvas, cellSize * 1.5, cellSize * 6.5, Colors.red);
    _drawStartPosition(canvas, cellSize * 8, cellSize * 1.5, Colors.blue);
    _drawStartPosition(
      canvas,
      cellSize * 6.5,
      cellSize * 13,
      Colors.yellow[700]!,
    );
    _drawStartPosition(canvas, cellSize * 13, cellSize * 8, Colors.green);

    // ✅ DEBUG: Path numbers enabled for testing
    // _drawSquareNumbers(canvas);
  }

  /// ✅ NEW: Draw numbers on every square to identify board layout
  void _drawSquareNumbers(Canvas canvas) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    const textStyle = TextStyle(
      color: Colors.black54,
      fontSize: 7,
      fontWeight: FontWeight.bold,
    );

    // Draw (row, col) coordinate on each cell
    for (int row = 0; row < 15; row++) {
      for (int col = 0; col < 15; col++) {
        final text = '$row,$col';
        textPainter.text = TextSpan(text: text, style: textStyle);
        textPainter.layout();

        // Position text in the center of each cell
        final x = col * cellSize + (cellSize - textPainter.width) / 2;
        final y = row * cellSize + (cellSize - textPainter.height) / 2;

        textPainter.paint(canvas, Offset(x, y));
      }
    }
  }

  /// Draw colored HOME column paths at the EDGE with proper positioning
  void _drawHomeColumnPath(
    Canvas canvas,
    int startCol,
    int startRow,
    int endCol,
    int endRow,
    Color color, {
    required bool isVertical,
  }) {
    final fillPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (isVertical) {
      // Vertical path (RED: top, YELLOW: bottom)
      int minRow = startRow < endRow ? startRow : endRow;
      int maxRow = startRow > endRow ? startRow : endRow;
      for (int i = minRow; i <= maxRow; i++) {
        final rect = Rect.fromLTWH(
          startCol * cellSize,
          i * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
      }
    } else {
      // Horizontal path (BLUE: right, GREEN: left)
      int minCol = startCol < endCol ? startCol : endCol;
      int maxCol = startCol > endCol ? startCol : endCol;
      for (int i = minCol; i <= maxCol; i++) {
        final rect = Rect.fromLTWH(
          i * cellSize,
          startRow * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  /// Draw colored START square for each side
  void _drawStartSquare(Canvas canvas, int col, int row, Color color) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rect = Rect.fromLTWH(
      col * cellSize + cellSize * 0.2,
      row * cellSize + cellSize * 0.2,
      cellSize * 0.6,
      cellSize * 0.6,
    );

    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, borderPaint);
  }

  /// Draw the main outer path grid
  void _drawMainBoardPath(Canvas canvas) {
    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw all grid lines
    for (int i = 0; i <= 15; i++) {
      canvas.drawLine(
        Offset(0, i * cellSize),
        Offset(15 * cellSize, i * cellSize),
        gridPaint,
      );
      canvas.drawLine(
        Offset(i * cellSize, 0),
        Offset(i * cellSize, 15 * cellSize),
        gridPaint,
      );
    }

    // Highlight the main path with subtle borders
    final pathBorderPaint = Paint()
      ..color = Colors.grey[600]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw cross path outline
    // Top horizontal
    canvas.drawLine(
      Offset(0, cellSize * 6),
      Offset(cellSize * 6, cellSize * 6),
      pathBorderPaint,
    );
    canvas.drawLine(
      Offset(cellSize * 9, cellSize * 6),
      Offset(cellSize * 15, cellSize * 6),
      pathBorderPaint,
    );

    // Bottom horizontal
    canvas.drawLine(
      Offset(0, cellSize * 9),
      Offset(cellSize * 6, cellSize * 9),
      pathBorderPaint,
    );
    canvas.drawLine(
      Offset(cellSize * 9, cellSize * 9),
      Offset(cellSize * 15, cellSize * 9),
      pathBorderPaint,
    );

    // Left vertical
    canvas.drawLine(
      Offset(cellSize * 6, 0),
      Offset(cellSize * 6, cellSize * 6),
      pathBorderPaint,
    );
    canvas.drawLine(
      Offset(cellSize * 6, cellSize * 9),
      Offset(cellSize * 6, cellSize * 15),
      pathBorderPaint,
    );

    // Right vertical
    canvas.drawLine(
      Offset(cellSize * 9, 0),
      Offset(cellSize * 9, cellSize * 6),
      pathBorderPaint,
    );
    canvas.drawLine(
      Offset(cellSize * 9, cellSize * 9),
      Offset(cellSize * 9, cellSize * 15),
      pathBorderPaint,
    );
  }

  void _drawHomeArea(Canvas canvas, double x, double y, Color color) {
    // ✅ Fill area with SOLID color (not transparent)
    final fillPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(x, y, cellSize * 6, cellSize * 6), fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawRect(
      Rect.fromLTWH(x, y, cellSize * 6, cellSize * 6),
      borderPaint,
    );

    // Draw 4 token home positions (circles)
    final positions = [
      Offset(x + cellSize * 1.5, y + cellSize * 1.5),
      Offset(x + cellSize * 4.5, y + cellSize * 1.5),
      Offset(x + cellSize * 1.5, y + cellSize * 4.5),
      Offset(x + cellSize * 4.5, y + cellSize * 4.5),
    ];

    final circlePaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final circleBorderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var pos in positions) {
      canvas.drawCircle(pos, cellSize * 0.6, circlePaint);
      canvas.drawCircle(pos, cellSize * 0.6, circleBorderPaint);
    }
  }

  void _drawStartPosition(Canvas canvas, double x, double y, Color color) {
    // Draw triangle/arrow pointing to path
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(x, y - cellSize * 0.3);
    path.lineTo(x - cellSize * 0.25, y + cellSize * 0.2);
    path.lineTo(x + cellSize * 0.25, y + cellSize * 0.2);
    path.close();

    canvas.drawPath(path, paint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Helper class for grid positions
class _GridPos {
  final int row;
  final int col;
  const _GridPos(this.row, this.col);
}
