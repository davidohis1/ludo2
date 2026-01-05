// ============================================================
// FILE: lib/screens/game/waiting_room_screen.dart (CORRECTED)
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../../models/game_tier.dart';
import '../../services/user_service.dart';
import 'game_screen.dart';

class WaitingRoomScreen extends StatefulWidget {
  final String gameId;
  final String playerId;
  final int playerPosition;
  final TierConfig tierConfig;

  const WaitingRoomScreen({
    super.key, // Use Dart 3 super parameter syntax
    required this.gameId,
    required this.playerId,
    required this.playerPosition, 
    required this.tierConfig,
  });

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final UserService _userService = UserService();
  
  StreamSubscription? _matchmakingSubscription;
  List<Map<String, dynamic>> players = [];
  String status = 'waiting';

  // Flag to prevent multiple navigation or state updates after disposal
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _listenToMatchmaking();
  }

  @override
  void dispose() {
    _isDisposed = true; // Set flag before cancelling
    _matchmakingSubscription?.cancel();
    super.dispose();
  }

  void _listenToMatchmaking() {
    final gamePath = 'matchmaking/${widget.tierConfig.tier.name.toLowerCase()}/${widget.gameId}';
    
    _matchmakingSubscription = _dbRef
        .child(gamePath)
        .onValue
        .listen((event) async {
      
      if (_isDisposed) return; // Crucial check before async logic continues
      if (!event.snapshot.exists) {
        // Handle case where game is deleted/removed
        _showGameNotFoundDialog();
        return;
      }

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final newStatus = data['status'] ?? 'waiting';

      // --- 1. Load player data ---
      final loadedPlayers = await _fetchAndMergePlayerData(data['players']);

      if (_isDisposed) return; // Check again before setState

      setState(() {
        status = newStatus;
        players = loadedPlayers;
      });

      // --- 2. Check if game started ---
      if (status == 'started' && mounted) {
        _navigateToGameScreen();
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchAndMergePlayerData(dynamic playersData) async {
    if (playersData == null) return [];
    
    final playersMap = Map<String, dynamic>.from(playersData);
    final loadedPlayers = <Map<String, dynamic>>[];

    // Use Future.wait to fetch user data concurrently for better performance
    final futures = playersMap.entries.map((entry) async {
      final playerData = Map<String, dynamic>.from(entry.value);
      final userId = playerData['userId'];
      final userData = await _userService.getUserById(userId);

      if (userData != null) {
        return {
          'position': playerData['position'],
          'userId': userId,
          // Assuming userData object has displayName and rating fields
          'displayName': userData.displayName, 
          'rating': userData.rating,
        };
      }
      return null;
    }).toList();

    // Await all user data fetches
    final results = await Future.wait(futures);
    
    // Filter out null results and cast
    return results.whereType<Map<String, dynamic>>().toList();
  }

  void _navigateToGameScreen() {
    // Only navigate if the widget is active
    if (!mounted || _isDisposed) return;
    
    // Cancel listener to stop receiving updates after navigation
    _matchmakingSubscription?.cancel(); 
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          gameId: widget.gameId,
          // playerId: widget.playerId,
          // playerPosition: widget.playerPosition,
          // tierConfig: widget.tierConfig,
        ),
      ),
    );
  }

  Future<bool> _handleLeaveRoom() async {
    // 1. Remove the player from the matchmaking node
    final playerPath = 'matchmaking/${widget.tierConfig.tier.name.toLowerCase()}/${widget.gameId}/players/${widget.playerPosition}';
    
    try {
      // Set value to null to delete the node
      await _dbRef.child(playerPath).set(null); 
      print('Player removed from matchmaking.');
      
      // OPTIONAL: If the last player leaves, delete the game node entirely.
      // This is usually handled by Cloud Functions, but can be done client-side:
      if (players.length <= 1) {
        await _dbRef.child('matchmaking/${widget.tierConfig.tier.name.toLowerCase()}/${widget.gameId}').set(null);
        print('Game node deleted as it was empty.');
      }

    } catch (e) {
      print('Error leaving room: $e');
      // Still allow pop if cleanup fails
    }
    
    return true; // Allows Navigator.pop
  }
  
  void _showGameNotFoundDialog() {
    if (!mounted || _isDisposed) return;
    
    // Stop listening immediately
    _matchmakingSubscription?.cancel(); 
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game Ended'),
        content: const Text('This game session was deleted or ended by the host.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Go to Lobby'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleLeaveRoom, // ✅ Use the new handler
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.tierConfig.name} Tier'),
          backgroundColor: widget.tierConfig.color,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              // Trigger the WillPopScope logic (cleanup)
              if (await _handleLeaveRoom()) { 
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Waiting status
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_empty, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text(
                      'Waiting for Players',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${players.length}/4 Players',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: widget.tierConfig.color,
                      ),
                    ),
                    if (players.length < 4) const LinearProgressIndicator(),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Players list header
              const Text(
                'Players in Lobby',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: ListView.builder(
                  itemCount: 4,
                  itemBuilder: (context, index) {
                    if (index < players.length) {
                      final player = players[index];
                      // Sort by position before accessing index
                      players.sort((a, b) => a['position'].compareTo(b['position']));

                      return _buildPlayerCard(
                        player['displayName'],
                        player['rating'],
                        _getPlayerColor(index),
                        isWaiting: false,
                        isSelf: player['userId'] == widget.playerId,
                      );
                    } else {
                      return _buildPlayerCard(
                        'Waiting...',
                        0,
                        _getPlayerColor(index),
                        isWaiting: true,
                      );
                    }
                  },
                ),
              ),

              // Loading indicator while starting
              if (players.length >= 4 && status != 'started')
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Starting game...'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(String name, int rating, Color color, {required bool isWaiting, bool isSelf = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelf ? color.withOpacity(0.1) : Colors.white, // Highlight self
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isWaiting ? Colors.grey : color,
          child: isWaiting
              ? const Icon(Icons.person_outline, color: Colors.white)
              : Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
        ),
        title: Text(
          isSelf ? '$name (You)' : name,
          style: TextStyle(
            fontWeight: isWaiting ? FontWeight.normal : FontWeight.bold,
            color: isWaiting ? Colors.grey : Colors.black,
          ),
        ),
        trailing: isWaiting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text('$rating'),
                ],
              ),
      ),
    );
  }

  Color _getPlayerColor(int index) {
    const colors = [
      Colors.red,
      Colors.blue,
      Colors.yellow,
      Colors.green,
    ];
    // Ensure colors cycle correctly based on player position (0-3)
    return colors[index % colors.length];
  }
}