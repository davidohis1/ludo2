// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int totalCoins;
  final int depositCoins;
  final int winningCoins;
  final int rating;
  final int lives;
  final int weeklyWinnings;
  final int totalMatches;
  final int wins;
  final int losses;
  final DateTime createdAt;
  final DateTime lastLogin;
  final bool? isPremium;
  final int? premiumExpiresAt;
  final DateTime? lastFreeLifesClaim;

  UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.totalCoins,
    required this.depositCoins,
    required this.winningCoins,
    required this.rating,
    required this.lives,
    this.weeklyWinnings = 0,
    this.totalMatches = 0,
    this.wins = 0,
    this.losses = 0,
    required this.createdAt,
    required this.lastLogin,
    this.isPremium = false,
    this.premiumExpiresAt,
    this.lastFreeLifesClaim,
  });

  factory UserModel.fromFirebaseUser({
    required String uid,
    required String email,
    required String displayName,
    String? photoUrl,
  }) {
    return UserModel(
      id: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      totalCoins: 100,
      depositCoins: 100,
      winningCoins: 0,
      rating: 100,
      lives: 5,
      weeklyWinnings: 0,
      totalMatches: 0,
      wins: 0,
      losses: 0,
      createdAt: DateTime.now(),
      lastLogin: DateTime.now(),
      lastFreeLifesClaim: null,
      isPremium: false,
      premiumExpiresAt: null,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'totalCoins': totalCoins,
      'depositCoins': depositCoins,
      'winningCoins': winningCoins,
      'rating': rating,
      'lives': lives,
      'weeklyWinnings': weeklyWinnings,
      'totalMatches': totalMatches,
      'wins': wins,
      'losses': losses,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastLogin': lastLogin.millisecondsSinceEpoch,
      'lastFreeLifesClaim': lastFreeLifesClaim?.millisecondsSinceEpoch,
      'isPremium': isPremium,
      'premiumExpiresAt': premiumExpiresAt,
    };
  }

  // ✅ FIXED: Proper null safety with fallbacks
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String? ?? '',  // ✅ Safe fallback
      email: map['email'] as String? ?? '',  // ✅ Safe fallback
      displayName: map['displayName'] as String? ?? 'Unknown Player',  // ✅ Safe fallback
      photoUrl: map['photoUrl'] as String?,
      totalCoins: map['totalCoins'] as int? ?? 0,
      depositCoins: map['depositCoins'] as int? ?? 0,
      winningCoins: map['winningCoins'] as int? ?? 0,
      rating: map['rating'] as int? ?? 100,
      lives: map['lives'] as int? ?? 5,
      totalMatches: map['totalMatches'] as int? ?? 0,
      weeklyWinnings: map['weeklyWinnings'] as int? ?? 0,
      wins: map['wins'] as int? ?? 0,
      losses: map['losses'] as int? ?? 0,
      createdAt: _parseTimestamp(map['createdAt']) ?? DateTime.now(),
      lastLogin: _parseTimestamp(map['lastLogin']) ?? DateTime.now(),
      lastFreeLifesClaim: _parseTimestamp(map['lastFreeLifesClaim']),
      isPremium: map['isPremium'] as bool? ?? false,
      premiumExpiresAt: map['premiumExpiresAt'] as int?,
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Unknown Player',
      photoUrl: map['photoUrl'] as String?,
      totalCoins: map['totalCoins'] as int? ?? 0,
      depositCoins: map['depositCoins'] as int? ?? 0,
      winningCoins: map['winningCoins'] as int? ?? 0,
      rating: map['rating'] as int? ?? 100,
      lives: map['lives'] as int? ?? 5,
      totalMatches: map['totalMatches'] as int? ?? 0,
      weeklyWinnings: map['weeklyWinnings'] as int? ?? 0,
      wins: map['wins'] as int? ?? 0,
      losses: map['losses'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
      lastLogin: DateTime.fromMillisecondsSinceEpoch(map['lastLogin'] as int? ?? 0),
      lastFreeLifesClaim: map['lastFreeLifesClaim'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastFreeLifesClaim'] as int)
          : null,
      isPremium: map['isPremium'] as bool? ?? false,
      premiumExpiresAt: map['premiumExpiresAt'] as int?,
    );
  }

  factory UserModel.fromFirestore(Map<String, dynamic> data, String docId) {
    return UserModel(
      id: docId,  // ✅ Use docId from Firestore, it's always available
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Unknown Player',
      photoUrl: data['photoUrl'] as String?,
      totalCoins: data['totalCoins'] as int? ?? 0,
      depositCoins: data['depositCoins'] as int? ?? 0,
      winningCoins: data['winningCoins'] as int? ?? 0,
      rating: data['rating'] as int? ?? 100,
      lives: data['lives'] as int? ?? 5,
      totalMatches: data['totalMatches'] as int? ?? 0,
      weeklyWinnings: data['weeklyWinnings'] as int? ?? 0,
      wins: data['wins'] as int? ?? 0,
      losses: data['losses'] as int? ?? 0,
      createdAt: _parseTimestamp(data['createdAt']) ?? DateTime.now(),
      lastLogin: _parseTimestamp(data['lastLogin']) ?? DateTime.now(),
      lastFreeLifesClaim: _parseTimestamp(data['lastFreeLifesClaim']),
      isPremium: data['isPremium'] as bool? ?? false,
      premiumExpiresAt: data['premiumExpiresAt'] as int?,
    );
  }

  static DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;

    if (timestamp is DateTime) return timestamp;

    // ✅ Better Firestore Timestamp detection
    if (timestamp.runtimeType.toString().contains('Timestamp')) {
      try {
        return timestamp.toDate() as DateTime;
      } catch (e) {
        print('⚠️ Error converting Firestore Timestamp: $e');
        return null;
      }
    }

    if (timestamp is int) {
      // ✅ Handle both milliseconds and seconds
      if (timestamp > 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      }
    }

    return null;
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    int? totalCoins,
    int? depositCoins,
    int? winningCoins,
    int? rating,
    int? lives,
    int? weeklyWinnings,
    int? totalMatches,
    int? wins,
    int? losses,
    DateTime? createdAt,
    DateTime? lastLogin,
    DateTime? lastFreeLifesClaim,
    bool? isPremium,
    int? premiumExpiresAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      totalCoins: totalCoins ?? this.totalCoins,
      depositCoins: depositCoins ?? this.depositCoins,
      winningCoins: winningCoins ?? this.winningCoins,
      rating: rating ?? this.rating,
      lives: lives ?? this.lives,
      weeklyWinnings: weeklyWinnings ?? this.weeklyWinnings,
      totalMatches: totalMatches ?? this.totalMatches,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      lastFreeLifesClaim: lastFreeLifesClaim ?? this.lastFreeLifesClaim,
      isPremium: isPremium ?? this.isPremium,
      premiumExpiresAt: premiumExpiresAt ?? this.premiumExpiresAt,
    );
  }

  double get winRate {
    if (totalMatches == 0) return 0.0;
    return (wins / totalMatches) * 100;
  }

  bool get canClaimDailyLives {
    if (lastFreeLifesClaim == null) return true;

    final now = DateTime.now();
    final lastClaim = lastFreeLifesClaim!;

    return now.day != lastClaim.day ||
        now.month != lastClaim.month ||
        now.year != lastClaim.year;
  }

  bool get needsLives {
    return lives <= 0;
  }

  @Deprecated('Use depositCoins or winningCoins instead')
  int get coins => totalCoins;

  int get withdrawableBalance => winningCoins;

  String toJson() => json.encode(toMap());
}