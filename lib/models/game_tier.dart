import 'package:flutter/material.dart';

enum GameTier {
  bronze,
  silver,
  gold,
}

class TierConfig {
  final GameTier tier;
  final String name;
  final int entryFee;
  final int prizePool;
  final Color color;
  final IconData icon;

  const TierConfig({
    required this.tier,
    required this.name,
    required this.entryFee,
    required this.prizePool,
    required this.color,
    required this.icon,
  });

  static const List<TierConfig> tiers = [
    TierConfig(
      tier: GameTier.bronze,
      name: 'Bronze',
      entryFee: 200,
      prizePool: 600,
      color: Color(0xFF8D6E63),
      icon: Icons.brightness_1,
    ),
    TierConfig(
      tier: GameTier.silver,
      name: 'Silver',
      entryFee: 500,
      prizePool: 1500,
      color: Color(0xFF9E9E9E),
      icon: Icons.brightness_1,
    ),
    TierConfig(
      tier: GameTier.gold,
      name: 'Gold',
      entryFee: 1000,
      prizePool: 3000,
      color: Color(0xFFFFD700),
      icon: Icons.brightness_1,
    ),
  ];

  static TierConfig getConfig(GameTier tier) {
    return tiers.firstWhere((t) => t.tier == tier);
  }
  
  // ✅ ADD THESE TWO METHODS
  static GameTier getTierFromString(String tierName) {
    switch (tierName.toLowerCase()) {
      case 'bronze':
        return GameTier.bronze;
      case 'silver':
        return GameTier.silver;
      case 'gold':
        return GameTier.gold;
      default:
        return GameTier.bronze;
    }
  }
  
  static String tierToString(GameTier tier) {
    return tier.name.toLowerCase();
  }
}
