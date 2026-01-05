// // gameplay_screen.dart
// import 'dart:async';
// import 'dart:math' as math;

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import '/constants/app_constants.dart';
// import '/constants/colors.dart';
// import '/providers/game_provider.dart';

// /// Self-contained, realtime GameplayScreen that listens directly to
// /// Firestore document `games/{gameId}` to ensure all players see the same state.
// /// NOTE: This is still a client-driven prototype; for production use a server-side
// /// authoritative logic for dice RNG and move validation (Cloud Functions).
// class GameplayScreen extends StatefulWidget {
//   final String gameId;
//   final String tier;

//   const GameplayScreen({
//     super.key,
//     required this.gameId,
//     required this.tier,
//   });

//   @override
//   State<GameplayScreen> createState() => _GameplayScreenState();
// }

// /// Minimal, local models to keep UI independent of your external GameModel.
// /// The code expects the `games/{gameId}` doc to contain certain fields described below.
// class LocalToken {
//   final int tokenId;
//   final int position; // -1 means base, >=0 mainboard positions, 100+ means home/finished
//   final bool isHome; // inside base area
//   final bool isFinished;

//   LocalToken({
//     required this.tokenId,
//     required this.position,
//     required this.isHome,
//     required this.isFinished,
//   });

//   factory LocalToken.fromMap(Map<String, dynamic> m) {
//     return LocalToken(
//       tokenId: (m['tokenId'] as num).toInt(),
//       position: (m['position'] as num).toInt(),
//       isHome: m['isHome'] as bool? ?? false,
//       isFinished: m['isFinished'] as bool? ?? false,
//     );
//   }

//   Map<String, dynamic> toMap() => {
//         'tokenId': tokenId,
//         'position': position,
//         'isHome': isHome,
//         'isFinished': isFinished,
//       };
// }

// enum LocalGameStatus { waiting, inProgress, completed }

// class LocalGame {
//   final LocalGameStatus status;
//   final String currentPlayerId;
//   final int lastDiceRoll;
//   final List<String> playerIds;
//   final Map<String, String> playerNames;
//   final Map<String, String> playerPhotos;
//   final Map<String, String> playerColors; // playerId -> 'red'/'green'/...
//   final Map<String, List<LocalToken>> tokenPositions;
//   final int prizePool;
//   final int entryFee;
//   final String? winnerId;
//   final Timestamp? endTime; // global end time (7 minutes after start)
//   final Timestamp? turnEndTime; // per-turn deadline (10 sec)
//   final int createdAt; // millis

//   LocalGame({
//     required this.status,
//     required this.currentPlayerId,
//     required this.lastDiceRoll,
//     required this.playerIds,
//     required this.playerNames,
//     required this.playerPhotos,
//     required this.playerColors,
//     required this.tokenPositions,
//     required this.prizePool,
//     required this.entryFee,
//     required this.winnerId,
//     required this.endTime,
//     required this.turnEndTime,
//     required this.createdAt,
//   });

//   factory LocalGame.fromSnapshot(DocumentSnapshot snap) {
//     final data = snap.data() as Map<String, dynamic>? ?? {};

//     LocalGameStatus toStatus(String? s) {
//       switch (s) {
//         case 'inProgress':
//           return LocalGameStatus.inProgress;
//         case 'completed':
//           return LocalGameStatus.completed;
//         default:
//           return LocalGameStatus.waiting;
//       }
//     }

//     final Map<String, dynamic> playersMap =
//         (data['playerNames'] as Map<String, dynamic>?) ?? {};
//     final playerIds = (data['playerIds'] as List<dynamic>?)
//             ?.map((e) => e.toString())
//             .toList() ??
//         [];

//     final playerNames = <String, String>{};
//     playersMap.forEach((k, v) => playerNames[k] = v.toString());

//     final playerPhotosMap =
//         (data['playerPhotos'] as Map<String, dynamic>?) ?? <String, dynamic>{};
//     final playerPhotos = <String, String>{};
//     playerPhotosMap.forEach((k, v) => playerPhotos[k] = v?.toString() ?? '');

//     // colors mapping stored on doc as map: { playerId: 'red' }
//     final colorsMap =
//         (data['playerColors'] as Map<String, dynamic>?) ?? <String, dynamic>{};
//     final playerColors = <String, String>{};
//     colorsMap.forEach((k, v) => playerColors[k] = v?.toString() ?? '');

//     // tokenPositions stored as nested map: { playerId: [ {tokenId, position, isHome, isFinished}, ... ] }
//     final tokensRaw =
//         (data['tokenPositions'] as Map<String, dynamic>?) ?? <String, dynamic>{};
//     final tokenPositions = <String, List<LocalToken>>{};
//     tokensRaw.forEach((playerId, listRaw) {
//       try {
//         final list = (listRaw as List<dynamic>)
//             .map((e) => LocalToken.fromMap(Map<String, dynamic>.from(e)))
//             .toList();
//         tokenPositions[playerId] = list;
//       } catch (_) {
//         tokenPositions[playerId] = [];
//       }
//     });

//     return LocalGame(
//       status: toStatus(data['status'] as String?),
//       currentPlayerId: data['currentPlayerId'] as String? ?? '',
//       lastDiceRoll: (data['lastDiceRoll'] as num?)?.toInt() ?? 0,
//       playerIds: playerIds,
//       playerNames: playerNames,
//       playerPhotos: playerPhotos,
//       playerColors: playerColors,
//       tokenPositions: tokenPositions,
//       prizePool: (data['prizePool'] as num?)?.toInt() ?? 0,
//       entryFee: (data['entryFee'] as num?)?.toInt() ?? 0,
//       winnerId: data['winnerId'] as String?,
//       endTime: data['endTime'] as Timestamp?,
//       turnEndTime: data['turnEndTime'] as Timestamp?,
//       createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
//     );
//   }
// }

// class _GameplayScreenState extends State<GameplayScreen>
//     with TickerProviderStateMixin {
//   late AnimationController _diceController;
//   late Animation<double> _diceAnimation;
//   final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

//   // Safe spots on the board
//   final List<int> _safeSpots = [1, 9, 14, 22, 27, 35, 40, 48];

//   // Firestore
//   final _gamesRef = FirebaseFirestore.instance.collection('games');

//   // Local state from firestore snapshot
//   LocalGame? _liveGame;
//   StreamSubscription<DocumentSnapshot>? _gameSub;

//   // timers
//   Timer? _uiTimer; // ticks once per second for countdowns

//   // animation control for dice enabling
//   bool _isRolling = false;

//   @override
//   void initState() {
//     super.initState();

//     _diceController = AnimationController(
//       duration: const Duration(milliseconds: 400),
//       vsync: this,
//     );
//     _diceAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
//       CurvedAnimation(parent: _diceController, curve: Curves.easeInOut),
//     );

//     // start provider load (existing code)
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       final gameProvider = Provider.of<GameProvider>(context, listen: false);
//       try {
//         gameProvider.loadGame(widget.gameId);
//       } catch (_) {}
//       // also start our own snapshot listener for realtime correctness
//       _startListeningFirestore();
//     });

//     _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
//       // force UI refresh every second so countdowns tick in sync
//       if (mounted) setState(() {});
//     });
//   }

//   @override
//   void dispose() {
//     _diceController.dispose();
//     _gameSub?.cancel();
//     _uiTimer?.cancel();
//     super.dispose();
//   }

//   void _startListeningFirestore() {
//     _gameSub = _gamesRef.doc(widget.gameId).snapshots().listen((snap) {
//       if (!snap.exists) return;
//       setState(() {
//         _liveGame = LocalGame.fromSnapshot(snap);
//       });

//       // If 4 players present and playerColors not assigned, assign them
//       if (_liveGame != null &&
//           _liveGame!.playerIds.length >= 2 && // at least two
//           (_liveGame!.playerColors.isEmpty ||
//               _liveGame!.playerColors.length != _liveGame!.playerIds.length)) {
//         _ensurePlayerColorsAssigned(snap);
//       }

//       // if global game is just started and no endTime, set endTime to now+7min
//       if (_liveGame != null && _liveGame!.status == LocalGameStatus.inProgress && _liveGame!.endTime == null) {
//         _setGlobalEndTime();
//       }

//       // If no turnEndTime set, establish one
//       if (_liveGame != null && _liveGame!.status == LocalGameStatus.inProgress && _liveGame!.turnEndTime == null) {
//         _setTurnEndTime();
//       }

//       // If turn expired (server time vs turnEndTime) handle turn auto-advance (best-effort client-driven)
//       _maybeAutoAdvanceExpiredTurn();
//     });
//   }

//   /// Assign colors based on player order (red, green, yellow, blue).
//   Future<void> _ensurePlayerColorsAssigned(DocumentSnapshot snap) async {
//     final data = snap.data() as Map<String, dynamic>? ?? {};
//     final playerIds = (data['playerIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
//     if (playerIds.isEmpty) return;

//     final colors = ['red', 'green', 'yellow', 'blue'];
//     final map = <String, String>{};
//     for (int i = 0; i < playerIds.length; i++) {
//       map[playerIds[i]] = colors[i % colors.length];
//     }

//     try {
//       await _gamesRef.doc(widget.gameId).set({
//         'playerColors': map,
//       }, SetOptions(merge: true));
//     } catch (e) {
//       debugPrint('Error assigning colors: $e');
//     }
//   }

//   /// Set global end time to now + 7 minutes if missing.
//   Future<void> _setGlobalEndTime() async {
//     try {
//       final doc = _gamesRef.doc(widget.gameId);
//       await doc.set({
//         'endTime': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(minutes: 7))),
//       }, SetOptions(merge: true));
//     } catch (e) {
//       debugPrint('Error setting global end time: $e');
//     }
//   }

//   /// Set per-turn end time to now + 10 seconds if missing.
//   Future<void> _setTurnEndTime() async {
//     try {
//       final doc = _gamesRef.doc(widget.gameId);
//       await doc.set({
//         'turnEndTime': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(seconds: 10))),
//       }, SetOptions(merge: true));
//     } catch (e) {
//       debugPrint('Error setting turn end time: $e');
//     }
//   }

//   /// If turn expired, attempt to auto-advance the turn (client-side fallback).
//   Future<void> _maybeAutoAdvanceExpiredTurn() async {
//     final g = _liveGame;
//     if (g == null) return;
//     final now = Timestamp.fromDate(DateTime.now().toUtc());

//     if (g.turnEndTime != null && g.turnEndTime!.compareTo(now) <= 0) {
//       // attempt to advance turn using transaction
//       try {
//         await FirebaseFirestore.instance.runTransaction((tx) async {
//           final docRef = _gamesRef.doc(widget.gameId);
//           final snap = await tx.get(docRef);
//           if (!snap.exists) return;
//           final data = snap.data() as Map<String, dynamic>? ?? {};
//           final currentPlayerId = (data['currentPlayerId'] as String?) ?? '';
//           final turnEndTime = data['turnEndTime'] as Timestamp?;
//           if (turnEndTime != null && turnEndTime.compareTo(now) <= 0) {
//             // compute next player
//             final playerIds = (data['playerIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
//             if (playerIds.isEmpty) return;
//             int idx = playerIds.indexOf(currentPlayerId);
//             final nextIdx = playerIds.isEmpty ? 0 : ((idx + 1) % playerIds.length);
//             final nextPlayer = playerIds[nextIdx];

//             tx.update(docRef, {
//               'currentPlayerId': nextPlayer,
//               'lastDiceRoll': 0,
//               'turnEndTime': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(seconds: 10)))
//             });
//           }
//         });
//       } catch (e) {
//         debugPrint('Auto-advance turn error: $e');
//       }
//     }
//   }

//   /// Utility: convert 'red'/'green' -> Color
//   Color _colorFromString(String color) {
//     switch (color) {
//       case 'red':
//         return const Color(0xFFFF0000);
//       case 'green':
//         return const Color(0xFF00AA00);
//       case 'yellow':
//         return const Color(0xFFFFDD00);
//       case 'blue':
//         return const Color(0xFF00BBDD);
//       default:
//         return Colors.grey;
//     }
//   }

//   /// Click handler for rolling the dice.
//   /// Uses Firestore transaction to set `lastDiceRoll` and, if not 6, advance turn.
//   /// NOTE: Client-side RNG here — move to Cloud Function for production fairness.
//   Future<void> _rollDice() async {
//     if (_isRolling) return;
//     final g = _liveGame;
//     if (g == null) return;

//     if (g.currentPlayerId != _currentUserId) return;
//     if (g.lastDiceRoll > 0) return; // already rolled

//     setState(() => _isRolling = true);
//     _diceController.forward(from: 0);

//     try {
//       await FirebaseFirestore.instance.runTransaction((tx) async {
//         final docRef = _gamesRef.doc(widget.gameId);
//         final snap = await tx.get(docRef);
//         if (!snap.exists) return;
//         final data = snap.data() as Map<String, dynamic>? ?? {};

//         final currentPlayerId = (data['currentPlayerId'] as String?) ?? '';
//         final lastDiceRoll = (data['lastDiceRoll'] as num?)?.toInt() ?? 0;
//         if (currentPlayerId != _currentUserId || lastDiceRoll > 0) return;

//         // pseudo-random dice roll (client). For secure production, call a Cloud Function.
//         final rng = math.Random();
//         final roll = rng.nextInt(6) + 1; // 1..6

//         final updates = <String, dynamic>{
//           'lastDiceRoll': roll,
//           // refresh turn end time to give player time to move after rolling
//           'turnEndTime': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(seconds: 10))),
//         };

//         // If roll != 6, schedule advance of turn to next player AFTER they attempt to move
//         if (roll != 6) {
//           // next player is computed if playerIds exists
//           final playerIds = (data['playerIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
//           if (playerIds.isNotEmpty) {
//             final idx = playerIds.indexOf(currentPlayerId);
//             final nextIdx = playerIds.isEmpty ? 0 : ((idx + 1) % playerIds.length);
//             final nextPlayer = playerIds[nextIdx];

//             updates['currentPlayerId'] = nextPlayer;
//             updates['turnEndTime'] = Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(seconds: 10)));
//             updates['lastDiceRoll'] = roll; // still write roll
//             // we clear lastDiceRoll for next player by client when they roll
//           }
//         } else {
//           // rolled a 6 -> keep current player (they get another turn). turnEndTime renewed.
//           updates['turnEndTime'] = Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(seconds: 10)));
//           updates['lastDiceRoll'] = roll;
//         }

//         tx.update(docRef, updates);
//       });
//     } catch (e) {
//       debugPrint('Roll dice transaction error: $e');
//     } finally {
//       setState(() => _isRolling = false);
//     }
//   }

//   /// Move a token after a roll. The move validation assumes token positions stored and
//   /// will update positions, captures, finishes, scoring etc. This is a simplified example.
//   Future<void> _moveToken({required String playerId, required int tokenId}) async {
//     final g = _liveGame;
//     if (g == null) return;

//     try {
//       await FirebaseFirestore.instance.runTransaction((tx) async {
//         final docRef = _gamesRef.doc(widget.gameId);
//         final snap = await tx.get(docRef);
//         if (!snap.exists) return;
//         final data = snap.data() as Map<String, dynamic>? ?? {};

//         final currentPlayerId = (data['currentPlayerId'] as String?) ?? '';
//         final lastDiceRoll = (data['lastDiceRoll'] as num?)?.toInt() ?? 0;
//         if (currentPlayerId != _currentUserId) return;
//         if (lastDiceRoll <= 0) return;

//         // parse tokenPositions
//         final tokensRaw = (data['tokenPositions'] as Map<String, dynamic>?) ?? <String, dynamic>{};
//         final myTokensRaw = (tokensRaw[playerId] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
//         final myTokens = myTokensRaw.map((m) => LocalToken.fromMap(m)).toList();

//         final tokenIndex = myTokens.indexWhere((t) => t.tokenId == tokenId);
//         if (tokenIndex == -1) return;

//         var token = myTokens[tokenIndex];

//         final int dice = lastDiceRoll;

//         // Determine new position according to simple mainboard rules:
//         int newPosition = token.position;
//         bool fromBase = (token.position < 0); // -1 indicates base
//         if (fromBase) {
//           // can only leave base on rolling 6
//           if (dice != 6) return;
//           // set to player's start position (we assume mapping: red=0, green=13, yellow=26, blue=39)
//           final playerColorMap = (data['playerColors'] as Map<String, dynamic>?) ?? {};
//           final colorStr = (playerColorMap[playerId] ?? '').toString();
//           int startPos = 0;
//           switch (colorStr) {
//             case 'red':
//               startPos = 0;
//               break;
//             case 'green':
//               startPos = 13;
//               break;
//             case 'yellow':
//               startPos = 26;
//               break;
//             case 'blue':
//               startPos = 39;
//               break;
//             default:
//               startPos = 0;
//           }
//           newPosition = startPos;
//           token = LocalToken(tokenId: token.tokenId, position: newPosition, isHome: false, isFinished: false);
//         } else {
//           // advance along board
//           newPosition = (token.position + dice) % 52;
//           // NOTE: finishing & home stretch logic are not fully implemented here.
//           // For a production game, you need to implement per-player home stretch calculation.
//           // We'll mark token as finished if it loops to some sentinel > 100 (simplified)
//           if (token.position >= 100) {
//             // already finished
//             return;
//           }
//           token = LocalToken(tokenId: token.tokenId, position: newPosition, isHome: false, isFinished: false);
//         }

//         // Check captures: if any opponent token exists at newPosition and it's not a safe spot, send them to base
//         final updatedTokensByPlayer = <String, List<Map<String, dynamic>>>{};
//         // copy existing tokens into mutable structure
//         tokensRaw.forEach((pid, listRaw) {
//           final list = (listRaw as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList();
//           updatedTokensByPlayer[pid] = list;
//         });

//         // update my token entry
//         final myList = updatedTokensByPlayer[playerId] ?? [];
//         // replace token entry:
//         final idx = myList.indexWhere((m) => (m['tokenId'] as num).toInt() == token.tokenId);
//         if (idx != -1) {
//           myList[idx] = token.toMap();
//         } else {
//           myList.add(token.toMap());
//         }
//         updatedTokensByPlayer[playerId] = myList;

//         // capture logic
//         if (!_safeSpots.contains(newPosition)) {
//           for (final pid in updatedTokensByPlayer.keys) {
//             if (pid == playerId) continue;
//             final list = updatedTokensByPlayer[pid]!;
//             for (int i = 0; i < list.length; i++) {
//               final tPos = (list[i]['position'] as num).toInt();
//               final tFinished = (list[i]['isFinished'] as bool?) ?? false;
//               if (!tFinished && tPos == newPosition) {
//                 // send opponent token to base (-1)
//                 list[i]['position'] = -1;
//                 list[i]['isHome'] = true;
//                 // profit: you could increase capture count here
//               }
//             }
//             updatedTokensByPlayer[pid] = list;
//           }
//         }

//         // Determine if token finished (very simplified: if position equals some player's home finish)
//         // PRODUCTION: implement proper home-stretch, exact dice required, etc.
//         // For demo: if token has looped beyond starting position twice (not implemented),
//         // we'll not mark finished here.

//         // Prepare updates: write tokenPositions back and reset lastDiceRoll.
//         final updates = <String, dynamic>{
//           'tokenPositions': updatedTokensByPlayer,
//           'lastDiceRoll': 0, // consumed by move
//           'turnEndTime': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(seconds: 10)))
//         };

//         // If dice wasn't 6, advance to next player
//         if (dice != 6) {
//           final playerIds = (data['playerIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
//           if (playerIds.isNotEmpty) {
//             final idx = playerIds.indexOf(currentPlayerId);
//             final nextIdx = playerIds.isEmpty ? 0 : ((idx + 1) % playerIds.length);
//             updates['currentPlayerId'] = playerIds[nextIdx];
//           }
//         } else {
//           // keep same player (bonus turn)
//           updates['currentPlayerId'] = currentPlayerId;
//         }

//         tx.update(docRef, updates);
//       });
//     } catch (e) {
//       debugPrint('moveToken transaction error: $e');
//     }
//   }

//   // Helper: compute remaining seconds to a timestamp
//   int _remainingSeconds(Timestamp? t) {
//     if (t == null) return 0;
//     final now = DateTime.now().toUtc();
//     final end = t.toDate().toUtc();
//     final diff = end.difference(now);
//     return diff.isNegative ? 0 : diff.inSeconds;
//   }

//   // UI BUILD
//   @override
//   Widget build(BuildContext context) {
//     // Keep calling provider as earlier to maintain other app flows

//     return WillPopScope(
//       onWillPop: () async {
//         final r = await _showExitDialog(context);
//         return r ?? false;
//       },
//       child: Scaffold(
//         backgroundColor: const Color(0xFFF5F5DC),
//         body: _liveGame == null
//             ? const Center(child: CircularProgressIndicator())
//             : _buildFromLocalGame(_liveGame!, gameProvider),
//       ),
//     );
//   }

//   Widget _buildFromLocalGame(LocalGame game, GameProvider gameProvider) {
//     // derive some useful things
//     final isMyTurn = game.currentPlayerId == _currentUserId;
//     final myColorStr = game.playerColors[_currentUserId] ?? 'red';
//     final myColor = _colorFromString(myColorStr);

//     final minutesLeft = _remainingSeconds(game.endTime) ~/ 60;
//     final secondsLeft = _remainingSeconds(game.endTime) % 60;
//     final turnSecondsLeft = _remainingSeconds(game.turnEndTime);

//     // Build UI similarly to your original layout but using LocalGame
//     return SafeArea(
//       child: Column(
//         children: [
//           // Global Timer
//           Container(
//             padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 const Icon(Icons.timer, color: Colors.black87, size: 20),
//                 const SizedBox(width: 8),
//                 Text(
//                   '${minutesLeft.toString().padLeft(2, '0')}:${secondsLeft.toString().padLeft(2, '0')}',
//                   style: const TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.black87,
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Text('(Turn: ${turnSecondsLeft}s)'),
//               ],
//             ),
//           ),

//           // Top players row (first two opponents)
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16),
//             child: _buildTopPlayersLocal(game),
//           ),

//           const SizedBox(height: 10),

//           // Board
//           Expanded(
//             child: Center(
//               child: AspectRatio(
//                 aspectRatio: 1,
//                 child: _buildGameBoardLocal(game),
//               ),
//             ),
//           ),

//           const SizedBox(height: 10),

//           // Bottom players (Me and next clockwise)
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16),
//             child: _buildBottomPlayersLocal(game),
//           ),

//           // Dice area
//           Container(
//             padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
//             decoration: BoxDecoration(
//               color: Colors.white,
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.1),
//                   blurRadius: 10,
//                   offset: const Offset(0, -5),
//                 ),
//               ],
//             ),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceAround,
//               children: [
//                 // Indicator
//                 AnimatedContainer(
//                   duration: const Duration(milliseconds: 300),
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                   decoration: BoxDecoration(
//                     color: isMyTurn ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Row(
//                     children: [
//                       Icon(isMyTurn ? Icons.play_arrow : Icons.hourglass_empty,
//                           color: isMyTurn ? Colors.green : Colors.grey),
//                       const SizedBox(width: 6),
//                       Text(isMyTurn ? 'Your Turn' : 'Waiting'),
//                     ],
//                   ),
//                 ),

//                 // Dice
//                 AnimatedBuilder(
//                   animation: _diceAnimation,
//                   builder: (context, child) {
//                     return Transform.rotate(
//                       angle: _diceAnimation.value,
//                       child: GestureDetector(
//                         onTap: () {
//                           if (isMyTurn && (_liveGame?.lastDiceRoll ?? 0) == 0) {
//                             _rollDice();
//                           }
//                         },
//                         child: AnimatedContainer(
//                           duration: const Duration(milliseconds: 200),
//                           width: 70,
//                           height: 70,
//                           decoration: BoxDecoration(
//                             color: isMyTurn && (_liveGame?.lastDiceRoll ?? 0) == 0 ? myColor : Colors.grey,
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Center(
//                             child: (_liveGame?.lastDiceRoll ?? 0) > 0
//                                 ? Text('${_liveGame!.lastDiceRoll}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold))
//                                 : const Icon(Icons.casino, color: Colors.white, size: 32),
//                           ),
//                         ),
//                       ),
//                     );
//                   },
//                 ),

//                 // Rules
//                 GestureDetector(
//                   onTap: () => _showRulesDialog(context),
//                   child: Container(
//                     padding: const EdgeInsets.all(8),
//                     decoration: BoxDecoration(
//                       color: Colors.blue.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: const Icon(Icons.info_outline, color: Colors.blue),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           const SizedBox(height: 12),
//         ],
//       ),
//     );
//   }

//   Widget _buildTopPlayersLocal(LocalGame game) {
//     final myIndex = game.playerIds.indexOf(_currentUserId);
//     final topIndices = <int>[];

//     for (int i = 0; i < game.playerIds.length; i++) {
//       if (i != myIndex && topIndices.length < 2) topIndices.add(i);
//     }

//     while (topIndices.length < 2) topIndices.add(-1);

//     return Row(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: topIndices.map((i) {
//         if (i == -1 || i >= game.playerIds.length) return _buildEmptyPlayerSlot();
//         return _buildPlayerInfoLocal(game, i, isActive: game.currentPlayerId == game.playerIds[i]);
//       }).toList(),
//     );
//   }

//   Widget _buildBottomPlayersLocal(LocalGame game) {
//     final myIndex = game.playerIds.indexOf(_currentUserId);
//     if (myIndex == -1) {
//       return Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [ _buildEmptyPlayerSlot(), _buildEmptyPlayerSlot() ],
//       );
//     }

//     final opponentIndex = game.playerIds.length > 1 ? (myIndex + 1) % game.playerIds.length : -1;

//     return Row(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: [
//         _buildPlayerInfoLocal(game, myIndex, isActive: game.currentPlayerId == _currentUserId),
//         opponentIndex == -1 ? _buildEmptyPlayerSlot() : _buildPlayerInfoLocal(game, opponentIndex, isActive: game.currentPlayerId == game.playerIds[opponentIndex]),
//       ],
//     );
//   }

//   Widget _buildEmptyPlayerSlot() {
//     return Container(
//       padding: const EdgeInsets.all(8),
//       child: Row(
//         children: [
//           CircleAvatar(radius: 20, backgroundColor: Colors.grey.shade300, child: const Icon(Icons.person_outline, color: Colors.grey)),
//           const SizedBox(width: 8),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text('Waiting...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade600)),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildPlayerInfoLocal(LocalGame game, int playerIndex, {required bool isActive}) {
//     final playerId = game.playerIds[playerIndex];
//     final playerName = game.playerNames[playerId] ?? 'Player';
//     final playerPhoto = game.playerPhotos[playerId] ?? '';
//     final colorStr = game.playerColors[playerId] ?? 'red';
//     final color = _colorFromString(colorStr);

//     final tokens = game.tokenPositions[playerId] ?? [];
//     final tokensHome = tokens.where((t) => t.isFinished).length;
//     final tokensAlive = tokens.where((t) => !t.isHome && !t.isFinished).length;
//     final isMe = playerId == _currentUserId;

//     return Container(
//       padding: const EdgeInsets.all(8),
//       decoration: BoxDecoration(
//         color: isActive ? color.withOpacity(0.2) : Colors.transparent,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isActive ? color : Colors.transparent,
//           width: isMe ? 3 : 2,
//         ),
//       ),
//       child: Row(
//         children: [
//           Stack(
//             children: [
//               CircleAvatar(
//                 radius: 20,
//                 backgroundColor: color,
//                 backgroundImage: playerPhoto.isNotEmpty ? NetworkImage(playerPhoto) : null,
//                 child: playerPhoto.isEmpty ? Text(playerName.isNotEmpty ? playerName[0].toUpperCase() : 'P', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)) : null,
//               ),
//               if (tokensHome > 0)
//                 Positioned(
//                   right: 0,
//                   bottom: 0,
//                   child: Container(
//                     padding: const EdgeInsets.all(2),
//                     decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
//                     child: Text('$tokensHome', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
//                   ),
//                 ),
//               if (isMe)
//                 Positioned(
//                   left: 0,
//                   top: 0,
//                   child: Container(
//                     padding: const EdgeInsets.all(2),
//                     decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
//                     child: const Icon(Icons.person, color: Colors.white, size: 10),
//                   ),
//                 ),
//             ],
//           ),
//           const SizedBox(width: 8),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text(isMe ? 'You' : (playerName.length > 8 ? '${playerName.substring(0, 8)}...' : playerName),
//                 style: TextStyle(fontWeight: isMe ? FontWeight.w900 : FontWeight.bold, fontSize: 14, color: isMe ? Colors.blue : Colors.black)),
//               Row(
//                 children: [
//                   const Icon(Icons.sports_esports, size: 12, color: Colors.blue),
//                   Text(' $tokensAlive', style: const TextStyle(fontSize: 11)),
//                   const SizedBox(width: 8),
//                   const Icon(Icons.home, size: 12, color: Colors.green),
//                   Text(' $tokensHome', style: const TextStyle(fontSize: 11)),
//                 ],
//               )
//             ],
//           )
//         ],
//       ),
//     );
//   }

//   // Board and pieces (adapted from your original code)
//   Widget _buildGameBoardLocal(LocalGame game) {
//     return LayoutBuilder(builder: (context, constraints) {
//       final size = constraints.maxWidth;
//       final cellSize = size / 15;

//       return Stack(
//         children: [
//           Container(width: size, height: size, color: Colors.white, child: _buildBoardGridLocal(cellSize, game)),
//           ..._buildPiecesLocal(game, cellSize),
//         ],
//       );
//     });
//   }

//   Widget _buildBoardGridLocal(double cellSize, LocalGame game) {
//     return Stack(
//       children: [
//         // home areas (top-left red, top-right green, bottom-right yellow, bottom-left blue)
//         Positioned(left: 0, top: 0, child: _buildHomeArea(cellSize * 6, 'red', game)),
//         Positioned(right: 0, top: 0, child: _buildHomeArea(cellSize * 6, 'green', game)),
//         Positioned(right: 0, bottom: 0, child: _buildHomeArea(cellSize * 6, 'yellow', game)),
//         Positioned(left: 0, bottom: 0, child: _buildHomeArea(cellSize * 6, 'blue', game)),

//         // paths
//         _buildBoardPaths(cellSize),
//         // center
//         Positioned(left: cellSize * 6, top: cellSize * 6, child: _buildCenterArea(cellSize * 3))
//       ],
//     );
//   }

//   Widget _buildHomeArea(double size, String colorStr, LocalGame game) {
//     final color = _colorFromString(colorStr);

//     // find player occupying this color
//     String? playerId;
//     game.playerColors.forEach((pid, col) {
//       if (col == colorStr) playerId = pid;
//     });

//     return Container(
//       width: size,
//       height: size,
//       decoration: BoxDecoration(color: color.withOpacity(0.3), border: Border.all(color: Colors.black, width: 2)),
//       child: Center(
//         child: Container(
//           width: size * 0.65,
//           height: size * 0.65,
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(12),
//             border: Border.all(color: color, width: 2),
//           ),
//           child: playerId != null ? _buildHomePiecesLocal(game, playerId!, color) : const SizedBox.shrink(),
//         ),
//       ),
//     );
//   }

//   Widget _buildHomePiecesLocal(LocalGame game, String playerId, Color color) {
//     final tokens = game.tokenPositions[playerId] ?? [];
//     final homeTokens = tokens.where((t) => t.isHome).toList();

//     return GridView.count(
//       crossAxisCount: 2,
//       padding: const EdgeInsets.all(8),
//       mainAxisSpacing: 8,
//       crossAxisSpacing: 8,
//       children: List.generate(4, (index) {
//         final hasPiece = index < homeTokens.length;
//         final canMove = hasPiece && game.currentPlayerId == playerId && (game.lastDiceRoll == 6);

//         return GestureDetector(
//           onTap: canMove ? () => _moveToken(playerId: playerId, tokenId: homeTokens[index].tokenId) : null,
//           child: AnimatedContainer(
//             duration: const Duration(milliseconds: 200),
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               color: hasPiece ? color : Colors.transparent,
//               border: Border.all(color: canMove ? Colors.yellowAccent : color.withOpacity(0.3), width: canMove ? 3 : 2),
//               boxShadow: canMove ? [BoxShadow(color: Colors.yellowAccent.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)] : null,
//             ),
//             child: hasPiece ? Center(child: Text('${homeTokens[index].tokenId + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))) : null,
//           ),
//         );
//       }),
//     );
//   }

//   Widget _buildCell(double size, bool isSafe, dynamic color, bool isStart) {
//     final cellColor = color is String ? _colorFromString(color) : color as Color;
//     return Container(
//       width: size,
//       height: size,
//       decoration: BoxDecoration(
//         color: color == Colors.white ? Colors.white : cellColor.withOpacity(0.2),
//         border: Border.all(color: Colors.grey.shade300, width: 0.5),
//       ),
//       child: isSafe || isStart
//           ? Icon(isSafe ? Icons.shield : Icons.flag, color: isStart ? cellColor : Colors.amber, size: size * 0.5)
//           : null,
//     );
//   }

//   Widget _buildBoardPaths(double cellSize) {
//     // simplified grid mapping converted from your original
//     final List<Widget> widgets = [];

//     // left vertical path
//     for (int i = 0; i < 6; i++) {
//       final position = i;
//       final isSafe = _safeSpots.contains(position);
//       widgets.add(Positioned(left: cellSize * 6, top: cellSize * i, child: _buildCell(cellSize, isSafe, 'red', position == 1)));
//     }
//     for (int i = 0; i < 6; i++) {
//       final position = 48 + i;
//       final isSafe = _safeSpots.contains(position);
//       widgets.add(Positioned(left: cellSize * 6, top: cellSize * (9 + i), child: _buildCell(cellSize, isSafe, 'blue', i == 4)));
//     }

//     // right vertical
//     for (int i = 0; i < 6; i++) {
//       widgets.add(Positioned(left: cellSize * 8, top: cellSize * i, child: _buildCell(cellSize, false, Colors.white, false)));
//     }
//     for (int i = 0; i < 6; i++) {
//       widgets.add(Positioned(left: cellSize * 8, top: cellSize * (9 + i), child: _buildCell(cellSize, false, Colors.white, false)));
//     }

//     // top horizontal
//     for (int i = 0; i < 6; i++) {
//       widgets.add(Positioned(left: cellSize * i, top: cellSize * 6, child: _buildCell(cellSize, false, Colors.white, false)));
//     }
//     for (int i = 0; i < 6; i++) {
//       final position = 27 + i;
//       final isSafe = _safeSpots.contains(position);
//       widgets.add(Positioned(left: cellSize * (9 + i), top: cellSize * 6, child: _buildCell(cellSize, isSafe, 'green', i == 4)));
//     }

//     // bottom horizontal
//     for (int i = 0; i < 6; i++) {
//       final position = 9 + i;
//       final isSafe = _safeSpots.contains(position);
//       widgets.add(Positioned(left: cellSize * i, top: cellSize * 8, child: _buildCell(cellSize, isSafe, 'blue', i == 1)));
//     }
//     for (int i = 0; i < 6; i++) {
//       widgets.add(Positioned(left: cellSize * (9 + i), top: cellSize * 8, child: _buildCell(cellSize, false, Colors.white, false)));
//     }

//     // home stretches
//     for (int i = 0; i < 5; i++) {
//       widgets.add(Positioned(left: cellSize * 7, top: cellSize * (1 + i), child: _buildCell(cellSize, false, 'red', false)));
//     }
//     for (int i = 0; i < 5; i++) {
//       widgets.add(Positioned(left: cellSize * (9 + i), top: cellSize * 7, child: _buildCell(cellSize, false, 'green', false)));
//     }
//     for (int i = 0; i < 5; i++) {
//       widgets.add(Positioned(left: cellSize * 7, top: cellSize * (9 + i), child: _buildCell(cellSize, false, 'yellow', false)));
//     }
//     for (int i = 0; i < 5; i++) {
//       widgets.add(Positioned(left: cellSize * (1 + i), top: cellSize * 7, child: _buildCell(cellSize, false, 'blue', false)));
//     }

//     return Stack(children: widgets);
//   }

//   Widget _buildCenterArea(double size) {
//     return Container(
//       width: size,
//       height: size,
//       child: CustomPaint(
//         painter: TrianglePainter(),
//         child: Center(
//           child: Container(
//             width: size * 0.35,
//             height: size * 0.35,
//             decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
//               BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
//             ]),
//             child: const Icon(Icons.emoji_events, color: Colors.amber, size: 24),
//           ),
//         ),
//       ),
//     );
//   }

//   List<Widget> _buildPiecesLocal(LocalGame game, double cellSize) {
//     final List<Widget> pieceWidgets = [];
//     for (final playerId in game.playerIds) {
//       final tokens = game.tokenPositions[playerId] ?? [];
//       final colorStr = game.playerColors[playerId] ?? 'red';
//       final color = _colorFromString(colorStr);

//       for (final token in tokens) {
//         if (token.isHome || token.isFinished) continue;
//         final pos = _getPiecePosition(token.position, colorStr, cellSize);
//         final isMyToken = playerId == _currentUserId;
//         final canMove = isMyToken && game.currentPlayerId == _currentUserId && (game.lastDiceRoll > 0) && !token.isFinished;

//         pieceWidgets.add(Positioned(
//           left: pos.dx + cellSize * 0.15,
//           top: pos.dy + cellSize * 0.15,
//           child: GestureDetector(
//             onTap: canMove ? () => _moveToken(playerId: playerId, tokenId: token.tokenId) : null,
//             child: AnimatedContainer(
//               duration: const Duration(milliseconds: 300),
//               width: cellSize * 0.7,
//               height: cellSize * 0.7,
//               decoration: BoxDecoration(
//                 color: color,
//                 shape: BoxShape.circle,
//                 border: Border.all(color: canMove ? Colors.yellowAccent : Colors.white, width: canMove ? 3 : 2),
//                 boxShadow: [BoxShadow(color: canMove ? Colors.yellowAccent.withOpacity(0.6) : Colors.black.withOpacity(0.3), blurRadius: canMove ? 8 : 4, offset: const Offset(0, 2))],
//               ),
//               child: Center(child: Text('${token.tokenId + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
//             ),
//           ),
//         ));
//       }
//     }
//     return pieceWidgets;
//   }

//   Offset _getPiecePosition(int position, String color, double cellSize) {
//     if (position >= 0 && position < 52) return _getMainBoardPosition(position, cellSize);
//     // base positions: return corners arbitrarily
//     if (position < 0) {
//       // on base -> place off-board in corners depending on color
//       switch (color) {
//         case 'red':
//           return Offset(0, 0);
//         case 'green':
//           return Offset(cellSize * 14, 0);
//         case 'yellow':
//           return Offset(cellSize * 14, cellSize * 14);
//         case 'blue':
//           return Offset(0, cellSize * 14);
//         default:
//           return Offset(0, 0);
//       }
//     }
//     // finished / home: place in center area (approx)
//     return Offset(cellSize * 6.5, cellSize * 6.5);
//   }

//   Offset _getMainBoardPosition(int position, double cellSize) {
//     // mapping copied and slightly adjusted from your original function
//     final positions = [
//       Offset(cellSize * 6, cellSize * 14),
//       Offset(cellSize * 6, cellSize * 13),
//       Offset(cellSize * 6, cellSize * 12),
//       Offset(cellSize * 6, cellSize * 11),
//       Offset(cellSize * 6, cellSize * 10),
//       Offset(cellSize * 6, cellSize * 9),
//       Offset(cellSize * 5, cellSize * 8),
//       Offset(cellSize * 4, cellSize * 8),
//       Offset(cellSize * 3, cellSize * 8),
//       Offset(cellSize * 2, cellSize * 8),
//       Offset(cellSize * 1, cellSize * 8),
//       Offset(cellSize * 0, cellSize * 8),
//       Offset(cellSize * 0, cellSize * 6),
//       Offset(cellSize * 1, cellSize * 6),
//       Offset(cellSize * 2, cellSize * 6),
//       Offset(cellSize * 3, cellSize * 6),
//       Offset(cellSize * 4, cellSize * 6),
//       Offset(cellSize * 5, cellSize * 6),
//       Offset(cellSize * 6, cellSize * 5),
//       Offset(cellSize * 6, cellSize * 4),
//       Offset(cellSize * 6, cellSize * 3),
//       Offset(cellSize * 6, cellSize * 2),
//       Offset(cellSize * 6, cellSize * 1),
//       Offset(cellSize * 6, cellSize * 0),
//       Offset(cellSize * 8, cellSize * 0),
//       Offset(cellSize * 8, cellSize * 1),
//       Offset(cellSize * 8, cellSize * 2),
//       Offset(cellSize * 8, cellSize * 3),
//       Offset(cellSize * 8, cellSize * 4),
//       Offset(cellSize * 8, cellSize * 5),
//       Offset(cellSize * 9, cellSize * 6),
//       Offset(cellSize * 10, cellSize * 6),
//       Offset(cellSize * 11, cellSize * 6),
//       Offset(cellSize * 12, cellSize * 6),
//       Offset(cellSize * 13, cellSize * 6),
//       Offset(cellSize * 14, cellSize * 6),
//       Offset(cellSize * 14, cellSize * 8),
//       Offset(cellSize * 13, cellSize * 8),
//       Offset(cellSize * 12, cellSize * 8),
//       Offset(cellSize * 11, cellSize * 8),
//       Offset(cellSize * 10, cellSize * 8),
//       Offset(cellSize * 9, cellSize * 8),
//       Offset(cellSize * 8, cellSize * 9),
//       Offset(cellSize * 8, cellSize * 10),
//       Offset(cellSize * 8, cellSize * 11),
//       Offset(cellSize * 8, cellSize * 12),
//       Offset(cellSize * 8, cellSize * 13),
//       Offset(cellSize * 8, cellSize * 14),
//       Offset(cellSize * 6, cellSize * 14),
//       Offset(cellSize * 6, cellSize * 13),
//       Offset(cellSize * 6, cellSize * 12),
//       Offset(cellSize * 6, cellSize * 11),
//     ];
//     return positions[position % 52];
//   }

//   Future<bool?> _showExitDialog(BuildContext context) {
//     return showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Exit Game?'),
//         content: const Text('Are you sure you want to exit? You will lose your entry fee and this will count as a loss.'),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
//           TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Exit Game')),
//         ],
//       ),
//     );
//   }

//   // Rules dialog (same as original)
//   void _showRulesDialog(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Row(children: [ Icon(Icons.info, color: Colors.blue), SizedBox(width: 8), Text('LudoTitan Rules') ]),
//         content: SingleChildScrollView(
//           child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
//             _buildRuleItem('🎯', 'Roll 6 to release a token from base'),
//             _buildRuleItem('🎲', 'Rolling 6 gives you another turn'),
//             _buildRuleItem('⚔️', 'Land on opponent to capture them'),
//             _buildRuleItem('🛡️', 'Safe spots (shields) protect your tokens'),
//             _buildRuleItem('🏆', 'First to get all 4 tokens home wins'),
//             _buildRuleItem('⭐', '+1 point for each capture'),
//             _buildRuleItem('🎁', '+2 points per token reaching home'),
//           ]),
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it!')),
//         ],
//       ),
//     );
//   }

//   Widget _buildRuleItem(String emoji, String text) {
//     return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(emoji, style: const TextStyle(fontSize: 20)), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 14))) ]));
//   }
// }

// class TrianglePainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()..style = PaintingStyle.fill;
//     paint.color = const Color(0xFFFF0000);
//     canvas.drawPath(Path()..moveTo(size.width / 2, 0)..lineTo(0, size.height / 2)..lineTo(size.width / 2, size.height / 2)..close(), paint);

//     paint.color = const Color(0xFF00AA00);
//     canvas.drawPath(Path()..moveTo(size.width, size.height / 2)..lineTo(size.width / 2, 0)..lineTo(size.width / 2, size.height / 2)..close(), paint);

//     paint.color = const Color(0xFFFFDD00);
//     canvas.drawPath(Path()..moveTo(size.width / 2, size.height)..lineTo(size.width, size.height / 2)..lineTo(size.width / 2, size.height / 2)..close(), paint);

//     paint.color = const Color(0xFF00BBDD);
//     canvas.drawPath(Path()..moveTo(0, size.height / 2)..lineTo(size.width / 2, size.height)..lineTo(size.width / 2, size.height / 2)..close(), paint);
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }
