// ✅ NEW: Model to track daily challenge completion and rewards
class DailyChallengeCompletion {
  final String userId;
  final String challengeType; // 'watch', 'subscribe', 'play', 'win'
  final int reward; // coins earned
  final DateTime completedAt; // when challenge was completed
  final DateTime resetAt; // when challenge resets (midnight next day)

  DailyChallengeCompletion({
    required this.userId,
    required this.challengeType,
    required this.reward,
    required this.completedAt,
    required this.resetAt,
  });

  // Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'challengeType': challengeType,
      'reward': reward,
      'completedAt': completedAt.millisecondsSinceEpoch,
      'resetAt': resetAt.millisecondsSinceEpoch,
    };
  }

  // Create from Firestore document
  factory DailyChallengeCompletion.fromMap(Map<String, dynamic> map) {
    return DailyChallengeCompletion(
      userId: map['userId'] as String,
      challengeType: map['challengeType'] as String,
      reward: map['reward'] as int,
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        map['completedAt'] as int,
      ),
      resetAt: DateTime.fromMillisecondsSinceEpoch(map['resetAt'] as int),
    );
  }

  /// Check if challenge can be claimed again
  /// Returns true if reset time has passed (new day)
  bool canClaimAgain() {
    return DateTime.now().isAfter(resetAt);
  }
}
