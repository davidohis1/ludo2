// ============================================================
// FILE: lib/screens/lobby_screen.dart (FIXED VERSION)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import 'game/game_screen.dart';
import '../models/game_tier.dart';
import '/utils/toast_utils.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final DatabaseReference _gameRef = FirebaseDatabase.instance.ref();
  final TextEditingController _gameIdController = TextEditingController();
  bool isLoading = false;
  List<Map<String, dynamic>> availableGames = [];
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _testFirebaseConnection();
    _loadAvailableGames();
  }

  Future<void> _testFirebaseConnection() async {
    try {
      final testRef = _gameRef.child('connection_test');
      await testRef.set({
        'timestamp': ServerValue.timestamp,
        'status': 'connected',
      });
      print('✅ Firebase connection successful');
      setState(() {
        errorMessage = null;
      });
    } catch (e) {
      print('❌ Firebase connection failed: $e');
      setState(() {
        errorMessage = 'Firebase connection failed. Check your configuration.';
      });
    }
  }

  void _loadAvailableGames() {
    try {
      _gameRef.child('games').onValue.listen((event) {
        if (event.snapshot.exists) {
          final games = <Map<String, dynamic>>[];
          final gamesMap = Map<String, dynamic>.from(
            event.snapshot.value as Map,
          );

          gamesMap.forEach((gameId, gameData) {
            final game = Map<String, dynamic>.from(gameData);
            game['gameId'] = gameId;

            final playerCount = game['playerCount'] ?? 0;
            final status = game['status'] ?? 'waiting';

            if (status != 'finished' && playerCount < 4) {
              games.add(game);
            }
          });

          setState(() {
            availableGames = games;
          });
        }
      });
    } catch (e) {
      print('Error loading games: $e');
    }
  }

  Future<void> _createGame() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      String gameId =
          'GAME${Random().nextInt(999999).toString().padLeft(6, '0')}';
      String playerId = 'player_${Random().nextInt(999999)}';

      print('Creating game with ID: $gameId');

      // Get tier config for Bronze (default tier for testing)
      final tierConfig = TierConfig.tiers[0]; // Bronze tier

      await _gameRef.child('games/$gameId').set({
        'gameId': gameId,
        'status': 'waiting',
        'currentTurn': 0,
        'lastDiceValue': 6,
        'createdAt': ServerValue.timestamp,
        'playerCount': 1,
        'tier': tierConfig.name.toLowerCase(), // Add tier info
        'entryFee': tierConfig.entryFee,
        'prizePool': tierConfig.prizePool,
        'players': {
          '0': {
            'playerId': playerId,
            'name': 'Player1',
            'position': 0,
            'joinedAt': ServerValue.timestamp,
          },
        },
        'tokenPositions': {
          '0': [-1, -1, -1, -1],
          '1': [-1, -1, -1, -1],
          '2': [-1, -1, -1, -1],
          '3': [-1, -1, -1, -1],
        },
      });

      print('✅ Game created successfully');

      setState(() {
        isLoading = false;
      });

      if (mounted) {
        _showGameIdDialog(gameId, playerId, 0, tierConfig);
      }
    } catch (e) {
      print('❌ Error creating game: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to create game: $e';
      });

      if (mounted) {
        _showErrorDialog('Failed to create game: $e');
      }
    }
  }

  Future<void> _joinGame(String gameId) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      print('Attempting to join game: $gameId');

      final snapshot = await _gameRef.child('games/$gameId').get();

      if (!snapshot.exists) {
        throw 'Game not found!';
      }

      final gameData = Map<String, dynamic>.from(snapshot.value as Map);
      final playerCount = gameData['playerCount'] ?? 0;

      if (playerCount >= 4) {
        throw 'Game is full!';
      }

      // Get tier config from game data
      final tierName = gameData['tier'] ?? 'bronze';
      final tier = TierConfig.getTierFromString(tierName);
      final tierConfig = TierConfig.getConfig(tier);

      String playerId = 'player_${Random().nextInt(999999)}';
      int playerPosition = playerCount;

      print('Joining as Player${playerPosition + 1}');

      await _gameRef.child('games/$gameId').update({
        'playerCount': playerPosition + 1,
        'players/$playerPosition': {
          'playerId': playerId,
          'name': 'Player${playerPosition + 1}',
          'position': playerPosition,
          'joinedAt': ServerValue.timestamp,
        },
      });

      if (playerPosition >= 1) {
        await _gameRef.child('games/$gameId').update({'status': 'playing'});
      }

      print('✅ Successfully joined game');

      setState(() {
        isLoading = false;
      });

      if (mounted) {
        _navigateToGame(gameId, playerId, playerPosition, tierConfig);
      }
    } catch (e) {
      print('❌ Error joining game: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to join game: $e';
      });

      if (mounted) {
        _showErrorDialog('$e');
      }
    }
  }

  void _showGameIdDialog(
    String gameId,
    String playerId,
    int position,
    TierConfig tierConfig,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🎮 Game Created!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this Game ID with friends:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      gameId,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.blue),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: gameId));
                      ToastUtils.showInfo(
                        context,
                        'Game ID copied to clipboard!',
                      );
                    },
                    tooltip: 'Copy Game ID',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Waiting for other players...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToGame(gameId, playerId, position, tierConfig);
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Enter Game'),
          ),
        ],
      ),
    );
  }

  void _showJoinGameDialog() {
    _gameIdController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎯 Join Game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _gameIdController,
              decoration: const InputDecoration(
                labelText: 'Enter Game ID',
                border: OutlineInputBorder(),
                hintText: 'GAME123456',
                prefixIcon: Icon(Icons.gamepad),
              ),
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            const Text(
              'Enter the 6-digit game code shared by your friend',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (_gameIdController.text.isNotEmpty) {
                _joinGame(_gameIdController.text.trim().toUpperCase());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Join Game'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 10),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // FIXED: Now includes tierConfig parameter
  void _navigateToGame(
    String gameId,
    String playerId,
    int position,
    TierConfig tierConfig,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          gameId: gameId,
          // playerId: playerId,
          // playerPosition: position,
          // tierConfig: tierConfig,  // ✅ ADD THIS LINE
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      appBar: AppBar(
        title: const Text(
          '🎲 Ludo Titan Lobby',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red,
        elevation: 0,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Loading...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),

                  ElevatedButton(
                    onPressed: isLoading ? null : _createGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle, size: 30),
                        SizedBox(width: 10),
                        Text(
                          'CREATE NEW GAME',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: isLoading ? null : _showJoinGameDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.login, size: 30),
                        SizedBox(width: 10),
                        Text(
                          'JOIN GAME WITH ID',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Divider(thickness: 2),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Icon(Icons.list_alt, size: 24),
                      const SizedBox(width: 10),
                      const Text(
                        'Available Games:',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${availableGames.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  availableGames.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.games_outlined,
                                size: 60,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 15),
                              Text(
                                'No games available',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Create one to start playing!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: availableGames.length,
                          itemBuilder: (context, index) {
                            final game = availableGames[index];
                            final playerCount = game['playerCount'] ?? 0;
                            final status = game['status'] ?? 'waiting';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(15),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.orange,
                                  radius: 25,
                                  child: Text(
                                    '$playerCount/4',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  game['gameId'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: status == 'waiting'
                                              ? Colors.orange.shade100
                                              : Colors.green.shade100,
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: status == 'waiting'
                                                ? Colors.orange.shade800
                                                : Colors.green.shade800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.people,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$playerCount/4 Players',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () => _joinGame(game['gameId']),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Join'),
                                ),
                              ),
                            );
                          },
                        ),

                  const SizedBox(height: 30),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.science, color: Colors.blue),
                            SizedBox(width: 10),
                            Text(
                              'Testing Multiplayer (Web)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        _buildInstructionStep('1', 'Create game in this tab'),
                        _buildInstructionStep('2', 'Copy the Game ID'),
                        _buildInstructionStep(
                          '3',
                          'Open new tab: Right-click tab > Duplicate',
                        ),
                        _buildInstructionStep(
                          '4',
                          'Join with same Game ID in new tabs',
                        ),
                        _buildInstructionStep('5', 'Play and test! 🎮'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _gameIdController.dispose();
    super.dispose();
  }
}
