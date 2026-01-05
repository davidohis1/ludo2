import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // ✅ Added for Color

enum GameStatus { waiting, inProgress, completed, cancelled }

// ✅ FIX: Added Color property to PlayerColor enum
enum PlayerColor {
  red(Color(0xFFF44336)), // Standard Red
  blue(Color(0xFF2196F3)), // Standard Blue
  yellow(Color(0xFFFFEB3B)), // Standard Yellow
  green(Color(0xFF4CAF50)); // Standard Green

  // Define the final property to store the color
  final Color color;

  // Add a const constructor to initialize the property
  const PlayerColor(this.color);
}

class GameModel {
  final String id;
  final String tier;
  final int entryFee;
  final int prizePool;
  final List<String> playerIds;
  // Firestore stores index, Dart model uses the enum value
  final Map<String, PlayerColor> playerColors;
  final Map<String, String> playerNames;
  final Map<String, String> playerPhotos;
  final Map<String, int> playerCoins;
  final GameStatus status;
  final String? winnerId;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int currentTurn;
  final Map<String, List<TokenPosition>> tokenPositions;
  final int lastDiceRoll;
  final String currentPlayerId;
  final Map<String, int> playerScores;
  final DateTime? expectedEndTime;

  GameModel({
    required this.id,
    required this.tier,
    required this.entryFee,
    required this.prizePool,
    required this.playerIds,
    required this.playerColors,
    required this.playerNames,
    required this.playerPhotos,
    required this.playerCoins,
    required this.status,
    this.winnerId,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.currentTurn = 0,
    required this.tokenPositions,
    this.lastDiceRoll = 0,
    required this.currentPlayerId,
    this.playerScores = const {},
    this.expectedEndTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tier': tier,
      'entryFee': entryFee,
      'prizePool': prizePool,
      'playerIds': playerIds,
      // Store enum index in Firestore
      'playerColors': playerColors.map((k, v) => MapEntry(k, v.index)),
      'playerNames': playerNames,
      'playerPhotos': playerPhotos,
      'playerCoins': playerCoins,
      'status': status.index,
      'winnerId': winnerId,
      // Use Firestore Timestamp for dates
      'createdAt': Timestamp.fromDate(createdAt),
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      'currentTurn': currentTurn,
      'tokenPositions': tokenPositions.map(
        (playerId, tokens) =>
            MapEntry(playerId, tokens.map((t) => t.toMap()).toList()),
      ),
      'lastDiceRoll': lastDiceRoll,
      'currentPlayerId': currentPlayerId,
      'playerScores': playerScores,
      'expectedEndTime': expectedEndTime != null
          ? Timestamp.fromDate(expectedEndTime!)
          : null,
    };
  }

  factory GameModel.fromMap(Map<String, dynamic> map) {
    return GameModel(
      id: map['id'] ?? '',
      tier: map['tier'] ?? '',
      entryFee: map['entryFee'] ?? 0,
      prizePool: map['prizePool'] ?? 0,
      playerIds: List<String>.from(map['playerIds'] ?? []),
      // Retrieve enum value from stored index
      playerColors: (map['playerColors'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, PlayerColor.values[v as int]),
      ),
      playerNames: Map<String, String>.from(map['playerNames'] ?? {}),
      playerPhotos: Map<String, String>.from(map['playerPhotos'] ?? {}),
      playerCoins: Map<String, int>.from(map['playerCoins'] ?? {}),
      status: GameStatus.values[map['status'] ?? 0],
      winnerId: map['winnerId'],
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      startedAt: map['startedAt'] != null
          ? (map['startedAt'] as Timestamp).toDate()
          : null,
      completedAt: map['completedAt'] != null
          ? (map['completedAt'] as Timestamp).toDate()
          : null,
      currentTurn: map['currentTurn'] ?? 0,
      tokenPositions: (map['tokenPositions'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          k,
          (v as List).map((t) => TokenPosition.fromMap(t)).toList(),
        ),
      ),
      lastDiceRoll: map['lastDiceRoll'] ?? 0,
      currentPlayerId: map['currentPlayerId'] ?? '',
      playerScores: Map<String, int>.from(map['playerScores'] ?? {}),
      expectedEndTime: map['expectedEndTime'] != null
          ? (map['expectedEndTime'] as Timestamp).toDate()
          : null,
    );
  }

  // ... (copyWith method remains unchanged)
  GameModel copyWith({
    String? id,
    String? tier,
    int? entryFee,
    int? prizePool,
    List<String>? playerIds,
    Map<String, PlayerColor>? playerColors,
    Map<String, String>? playerNames,
    Map<String, String>? playerPhotos,
    Map<String, int>? playerCoins,
    GameStatus? status,
    String? winnerId,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? currentTurn,
    Map<String, List<TokenPosition>>? tokenPositions,
    int? lastDiceRoll,
    String? currentPlayerId,
    Map<String, int>? playerScores,
    DateTime? expectedEndTime,
  }) {
    return GameModel(
      id: id ?? this.id,
      tier: tier ?? this.tier,
      entryFee: entryFee ?? this.entryFee,
      prizePool: prizePool ?? this.prizePool,
      playerIds: playerIds ?? this.playerIds,
      playerColors: playerColors ?? this.playerColors,
      playerNames: playerNames ?? this.playerNames,
      playerPhotos: playerPhotos ?? this.playerPhotos,
      playerCoins: playerCoins ?? this.playerCoins,
      status: status ?? this.status,
      winnerId: winnerId ?? this.winnerId,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      currentTurn: currentTurn ?? this.currentTurn,
      tokenPositions: tokenPositions ?? this.tokenPositions,
      lastDiceRoll: lastDiceRoll ?? this.lastDiceRoll,
      currentPlayerId: currentPlayerId ?? this.currentPlayerId,
      playerScores: playerScores ?? this.playerScores,
      expectedEndTime: expectedEndTime ?? this.expectedEndTime,
    );
  }
}

class TokenPosition {
  final int tokenId;
  final int position;
  final bool isHome;
  final bool isFinished;

  TokenPosition({
    required this.tokenId,
    required this.position,
    this.isHome = true,
    this.isFinished = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'tokenId': tokenId,
      'position': position,
      'isHome': isHome,
      'isFinished': isFinished,
    };
  }

  factory TokenPosition.fromMap(Map<String, dynamic> map) {
    return TokenPosition(
      tokenId: map['tokenId'] ?? 0,
      position: map['position'] ?? 0,
      isHome: map['isHome'] ?? true,
      isFinished: map['isFinished'] ?? false,
    );
  }

  TokenPosition copyWith({
    int? tokenId,
    int? position,
    bool? isHome,
    bool? isFinished,
  }) {
    return TokenPosition(
      tokenId: tokenId ?? this.tokenId,
      position: position ?? this.position,
      isHome: isHome ?? this.isHome,
      isFinished: isFinished ?? this.isFinished,
    );
  }
}
