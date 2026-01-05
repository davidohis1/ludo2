class AppConstants {
  // App Info
  static const String appName = 'LuduTitan';
  
  // Initial Values
  static const int initialCoins = 100;
  static const int initialRating = 100;
  
  // Game Constants
  static const int maxPlayers = 4;
  static const int tokensPerPlayer = 4;
  static const int boardSize = 15;
  static const int homePositions = 6;
  static const int winningTokens = 4;
  
  // Rating Changes
  static const int winRatingIncrease = 10;
  static const int loseRatingDecrease = -10;
  
  // Game Tiers
  static const Map<String, int> tierEntryFees = {
    'bronze': 100,
    'silver': 500,
    'gold': 1000,
  };
  
  static const Map<String, int> tierPrizePools = {
    'bronze': 500,
    'silver': 2500,
    'gold': 5000,
  };
  
  static const Map<String, int> tierPlayerCounts = {
    'bronze': 25,
    'silver': 15,
    'gold': 5,
  };
  
  // Timer
  static const int turnDuration = 30; // seconds
  static const int matchmakingTimeout = 120; // seconds
  
  // Firestore Collections
  static const String usersCollection = 'users';
  static const String gamesCollection = 'games';
  static const String matchmakingCollection = 'matchmaking';
  static const String leaderboardCollection = 'leaderboard';
  
  // Routes
  static const String splashRoute = '/';
  static const String loginRoute = '/sign_in';
  static const String homeRoute = '/home';
  static const String profileRoute = '/profile';
  static const String editProfileRoute = '/edit-profile';
  static const String walletRoute = '/wallet';
  static const String leaderboardRoute = '/leaderboard';
  static const String storeRoute = '/store';
  static const String selectTierRoute = '/select-tier';
  static const String gameplayRoute = '/gameplay';
  static const String dailyChallengesRoute = '/daily-challenges';
}