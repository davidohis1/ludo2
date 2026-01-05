import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '/constants/colors.dart';
import '/cubits/user/user_cubit.dart';
import '/cubits/auth/auth_cubit.dart';
import '/services/database_service.dart';
import '/utils/toast_utils.dart';

class DailyChallengesScreen extends StatefulWidget {
  const DailyChallengesScreen({super.key});

  @override
  State<DailyChallengesScreen> createState() => _DailyChallengesScreenState();
}

class _DailyChallengesScreenState extends State<DailyChallengesScreen> {
  Timer? _countdownTimer;
  int _hoursRemaining = 0;
  int _minutesRemaining = 0;
  int _secondsRemaining = 0;

  bool _watchAdCompleted = false;
  bool _subscribeCompleted = false;
  bool _playMatchCompleted = false;

  // Ad simulation
  int _adProgress = 0;
  Timer? _adTimer;

  @override
  void initState() {
    super.initState();
    _startCountdownTimer();
    _loadChallengeProgress();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _adTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _updateTimeRemaining();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTimeRemaining();
    });
  }

  void _updateTimeRemaining() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final difference = midnight.difference(now);

    setState(() {
      _hoursRemaining = difference.inHours;
      _minutesRemaining = difference.inMinutes.remainder(60);
      _secondsRemaining = difference.inSeconds.remainder(60);
    });
  }

  void _loadChallengeProgress() {
    // Load saved progress from shared preferences or user data
    // For now, we'll check from user stats
    final userState = context.read<UserCubit>().state;
    if (userState is UserLoaded) {
      final user = userState.currentUser;

      setState(() {
        // Check if user has won a game today
        // You can add lastWinDate to UserModel to track this
        _playMatchCompleted = user.totalMatches > 0;
      });
    }
  }

  int get _completedCount {
    int count = 0;
    if (_watchAdCompleted) count++;
    if (_subscribeCompleted) count++;
    if (_playMatchCompleted) count++;

    // Check win challenge from user stats
    final userState = context.read<UserCubit>().state;
    if (userState is UserLoaded && userState.currentUser.wins > 0) {
      count++;
    }

    return count;
  }

  List<Map<String, Object>> get _challenges {
    final userState = context.read<UserCubit>().state;
    final hasWin = userState is UserLoaded && userState.currentUser.wins > 0;

    return [
      {
        'title': 'Watch & Earn',
        'description': 'Watch a 30-second ad to get coins',
        'reward': 30,
        'icon': Icons.play_circle_outline,
        'color': const Color(0xFF4ECDC4),
        'completed': _watchAdCompleted,
        'type': 'watch',
      },
      {
        'title': 'Join Our Community',
        'description': 'Subscribe to our YouTube channel',
        'reward': 50,
        'icon': Icons.subscriptions,
        'color': const Color(0xFFFF6B6B),
        'completed': _subscribeCompleted,
        'type': 'subscribe',
      },
      {
        'title': 'Play a Match',
        'description': 'Complete one online game',
        'reward': 0,
        'rewardText': '1 Free Life',
        'icon': Icons.gamepad,
        'color': const Color(0xFF95E1D3),
        'completed': _playMatchCompleted,
        'type': 'play',
      },
      {
        'title': 'Win a Game',
        'description': 'Win an online Ludo match',
        'reward': 100,
        'icon': Icons.emoji_events,
        'color': const Color(0xFFF38181),
        'completed': hasWin,
        'type': 'win',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final totalChallenges = _challenges.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Challenges'), centerTitle: true),
      body: BlocBuilder<UserCubit, UserState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Timer
              _buildTimerCard(),
              const SizedBox(height: 24),

              // Progress
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_completedCount/$totalChallenges Completed',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Total Rewards: ${_calculateTotalRewards()} coins',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _completedCount / totalChallenges,
                  minHeight: 8,
                  backgroundColor: AppColors.lightGrey,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primaryRed,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Challenges List
              ..._challenges.map((challenge) {
                return _buildChallengeCard(challenge);
              }),

              // Complete All Bonus
              if (_completedCount == totalChallenges) _buildBonusCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryRed, AppColors.primaryRed.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryRed.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Challenges Reset In',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTimeBox(
                _hoursRemaining.toString().padLeft(2, '0'),
                'Hours',
              ),
              const SizedBox(width: 8),
              const Text(
                ':',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              _buildTimeBox(
                _minutesRemaining.toString().padLeft(2, '0'),
                'Minutes',
              ),
              const SizedBox(width: 8),
              const Text(
                ':',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              _buildTimeBox(
                _secondsRemaining.toString().padLeft(2, '0'),
                'Seconds',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBox(String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryRed,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeCard(Map<String, Object> challenge) {
    final bool isCompleted = challenge['completed'] as bool;
    final Color color = challenge['color'] as Color;
    final int reward = challenge['reward'] as int;
    final String type = challenge['type'] as String;
    final String title = challenge['title'] as String;
    final String description = challenge['description'] as String;
    final IconData icon = challenge['icon'] as IconData;

    final String rewardText =
        (challenge['rewardText'] as String?) ?? '$reward Coins';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: isCompleted ? Border.all(color: Colors.green, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon Section
          Container(
            width: 80,
            height: 120,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green.withOpacity(0.2)
                  : color.withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(
                      Icons.check_circle,
                      size: 40,
                      color: Colors.green,
                    )
                  : Icon(icon, size: 40, color: color),
            ),
          ),

          // Content Section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Reward
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              size: 14,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rewardText,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Action Button
                      InkWell(
                        onTap: isCompleted
                            ? null
                            : () {
                                _handleChallenge(type, reward);
                              },
                        borderRadius: BorderRadius.circular(8),
                        child: Material(
                          color: isCompleted
                              ? Colors.green
                              : AppColors.primaryRed,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Text(
                              isCompleted
                                  ? 'Completed ✓'
                                  : _getButtonText(type),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration, size: 48, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 All Challenges Complete!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You earned ${_calculateTotalRewards()} coins today!',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getButtonText(String type) {
    switch (type) {
      case 'watch':
        return 'Watch Ad';
      case 'subscribe':
        return 'Subscribe';
      case 'play':
        return 'Play Now';
      case 'win':
        return 'Play';
      default:
        return 'Start';
    }
  }

  int _calculateTotalRewards() {
    int total = 0;
    for (var challenge in _challenges) {
      if (challenge['completed'] as bool) {
        total += challenge['reward'] as int;
      }
    }
    return total;
  }

  Future<void> _handleChallenge(String type, int reward) async {
    switch (type) {
      case 'watch':
        await _watchAd(reward);
        break;
      case 'subscribe':
        await _openYouTubeChannel();
        break;
      case 'play':
      case 'win':
        _navigateToGame();
        break;
    }
  }

  // ==================== WATCH AD ====================

  Future<void> _watchAd(int reward) async {
    setState(() {
      _adProgress = 0;
    });

    // Show ad dialog
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildAdDialog(reward),
    );
  }

  Widget _buildAdDialog(int reward) {
    // Simulate 30-second ad
    const adDuration = 30;

    _adTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_adProgress >= adDuration) {
        timer.cancel();
        _completeAdWatch(reward);
      } else {
        setState(() {
          _adProgress++;
        });
      }
    });

    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Watch Ad to Earn Coins'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ad video placeholder (simulated)
              ADWidget(adDuration: adDuration, adProgress: _adProgress),
              const SizedBox(height: 16),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _adProgress / adDuration,
                  minHeight: 8,
                  backgroundColor: AppColors.lightGrey,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primaryRed,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Please watch the full ad to receive $reward coins',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  void _completeAdWatch(int reward) {
    _adTimer?.cancel();
    Navigator.pop(context);

    // ✅ NEW: Claim reward with database service to prevent double-claiming
    _claimChallengeReward('watch', reward);
  }

  // ==================== CLAIM CHALLENGE REWARD ====================

  /// ✅ NEW: Claim daily challenge reward with anti-cheat protection
  Future<void> _claimChallengeReward(String challengeType, int reward) async {
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is! AuthAuthenticated) {
        if (mounted) {
          ToastUtils.showError(context, '❌ User not authenticated');
        }
        return;
      }

      final userId = authState.currentUser.id;
      final databaseService = DatabaseService();

      // Try to claim the reward
      final success = await databaseService.claimDailyChallengeReward(
        userId: userId,
        challengeType: challengeType,
        reward: reward,
      );

      if (success) {
        setState(() {
          if (challengeType == 'watch') _watchAdCompleted = true;
          if (challengeType == 'subscribe') _subscribeCompleted = true;
          if (challengeType == 'play') _playMatchCompleted = true;
        });

        // Show success message
        if (mounted) {
          ToastUtils.showSuccess(context, '🎉 You earned $reward coins!');

          // Refresh user data to show updated coins
          context.read<UserCubit>().refreshUserData();
        }
      } else {
        // Challenge already claimed today
        if (mounted) {
          ToastUtils.showInfo(
            context,
            '⏰ Challenge already claimed today. Try again tomorrow!',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context, '❌ Error claiming reward: $e');
      }
    }
  }

  // ==================== OPEN YOUTUBE ====================

  Future<void> _openYouTubeChannel() async {
    // Replace with your actual YouTube channel URL
    const youtubeChannelUrl = 'https://www.youtube.com/';

    try {
      final uri = Uri.parse(youtubeChannelUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // ✅ NEW: Claim reward with database service
        _claimChallengeReward('subscribe', 50);
      } else {
        throw 'Could not open YouTube';
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context, 'Failed to open YouTube: $e');
      }
    }
  }

  // ==================== NAVIGATE TO GAME ====================

  void _navigateToGame() {
    Navigator.pushNamed(context, '/select_tier');
  }
}

class ADWidget extends StatefulWidget {
  const ADWidget({super.key, required this.adDuration, required int adProgress})
    : _adProgress = adProgress;

  final int adDuration;
  final int _adProgress;

  @override
  State<ADWidget> createState() => _ADWidgetState();
}

class _ADWidgetState extends State<ADWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 600,
      height: 500,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ad Playing...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          // Skip countdown
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${widget.adDuration - widget._adProgress}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
