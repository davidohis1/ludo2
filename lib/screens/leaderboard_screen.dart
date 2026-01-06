import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/constants/colors.dart';
import '/cubits/user/user_cubit.dart';
import '/models/user_model.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isWeekly = true;
  Timer? _countdownTimer;

  // Countdown state
  int _daysRemaining = 0;
  int _hoursRemaining = 0;
  int _minutesRemaining = 0;
  int _secondsRemaining = 0;

  // Leaderboard data
  List<Map<String, dynamic>> _leaderboardData = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startTimers();
    _loadLeaderboardData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startTimers() {
    _updateCountdown();
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCountdown();
      }
    });
  }

  // Load all users and calculate their winning coins
  Future<void> _loadLeaderboardData() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      
      // Get all users from Firestore
      final usersSnapshot = await firestore.collection('users').get();
      
      final leaderboardData = <Map<String, dynamic>>[];
      
      for (var doc in usersSnapshot.docs) {
        try {
          final userData = doc.data();
          
          // Create a UserModel - handle missing winningCoins field
          final user = UserModel(
            id: doc.id,
            displayName: userData['displayName'] ?? 'Unknown',
            email: userData['email'] ?? '',
            photoUrl: userData['photoUrl'],
            rating: userData['rating'] ?? 1000,
            totalCoins: userData['totalCoins'] ?? 0,
            depositCoins: userData['depositCoins'] ?? 0,
            winningCoins: userData['winningCoins'] ?? 0,
            lives: userData['lives'] ?? 3,
            lastLogin: (userData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            createdAt: (userData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          );
          
          leaderboardData.add({
            'user': user,
            'score': user.winningCoins, // Use winningCoins for ranking
          });
        } catch (e) {
          print('Error processing user ${doc.id}: $e');
          // Skip this user if there's an error
        }
      }
      
      // Sort by winning coins (highest first)
      leaderboardData.sort((a, b) => 
        (b['score'] as int).compareTo(a['score'] as int)
      );
      
      if (mounted) {
        setState(() {
          _leaderboardData = leaderboardData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading leaderboard: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Simple: Get Monday 00:00
  DateTime _getStartOfWeek(DateTime date) {
    int daysSinceMonday = date.weekday - DateTime.monday;
    if (daysSinceMonday < 0) daysSinceMonday += 7;
    return DateTime(date.year, date.month, date.day - daysSinceMonday, 0, 0, 0);
  }

  void _updateCountdown() {
    final now = DateTime.now();
    
    DateTime nextMonday;
    if (now.weekday == DateTime.monday) {
      final midnightToday = DateTime(now.year, now.month, now.day);
      if (now.isAfter(midnightToday)) {
        nextMonday = midnightToday.add(const Duration(days: 7));
      } else {
        nextMonday = midnightToday;
      }
    } else {
      int daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
      nextMonday = DateTime(now.year, now.month, now.day + daysUntilMonday);
    }
    
    final difference = nextMonday.difference(now);

    setState(() {
      _daysRemaining = difference.inDays;
      _hoursRemaining = difference.inHours.remainder(24);
      _minutesRemaining = difference.inMinutes.remainder(60);
      _secondsRemaining = difference.inSeconds.remainder(60);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF2C1810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C1810),
        title: const Text(
          'Leaderboard',
          style: TextStyle(color: AppColors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _isWeekly = !_isWeekly;
                });
              },
              child: Text(
                _isWeekly ? 'Weekly' : 'All Time',
                style: const TextStyle(
                  color: AppColors.primaryRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<UserCubit, UserState>(
        builder: (context, userState) {
          if (userState is! UserLoaded) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryRed),
            );
          }

          final currentUser = userState.currentUser;

          if (_isLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: AppColors.primaryRed),
                  SizedBox(height: 16),
                  Text(
                    'Loading leaderboard...',
                    style: TextStyle(color: AppColors.white),
                  ),
                ],
              ),
            );
          }

          if (_leaderboardData.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.leaderboard, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No leaderboard data yet',
                    style: TextStyle(color: AppColors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadLeaderboardData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                    ),
                  ),
                ],
              ),
            );
          }

          // Find current user's position
          int currentUserRank = _leaderboardData.indexWhere(
            (entry) => (entry['user'] as UserModel).id == currentUser.id,
          );

          return RefreshIndicator(
            color: AppColors.primaryRed,
            onRefresh: () async {
              await _loadLeaderboardData();
            },
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Countdown Timer
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF3D2819),
                          const Color(0xFF3D2819).withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryRed.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Weekly Reset In',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isWeekly 
                            ? 'Ranked by total coins won from games'
                            : 'Ranked by all-time winning coins',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _TimeBox(
                              value: _daysRemaining.toString().padLeft(2, '0'),
                              label: 'Days',
                            ),
                            const SizedBox(width: 12),
                            _TimeBox(
                              value: _hoursRemaining.toString().padLeft(2, '0'),
                              label: 'Hours',
                            ),
                            const SizedBox(width: 12),
                            _TimeBox(
                              value: _minutesRemaining.toString().padLeft(2, '0'),
                              label: 'Min',
                            ),
                            const SizedBox(width: 12),
                            _TimeBox(
                              value: _secondsRemaining.toString().padLeft(2, '0'),
                              label: 'Sec',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Top 3 Podium
                  if (_leaderboardData.length >= 3) ...[
                    SizedBox(
                      height: 280,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 2nd Place
                          _buildPodiumItem(
                            _leaderboardData[1]['user'] as UserModel,
                            2,
                            AppColors.grey,
                            140,
                            score: _leaderboardData[1]['score'] as int,
                          ),
                          const SizedBox(width: 16),
                          // 1st Place
                          _buildPodiumItem(
                            _leaderboardData[0]['user'] as UserModel,
                            1,
                            const Color(0xFFFFD700),
                            180,
                            score: _leaderboardData[0]['score'] as int,
                          ),
                          const SizedBox(width: 16),
                          // 3rd Place
                          _buildPodiumItem(
                            _leaderboardData[2]['user'] as UserModel,
                            3,
                            const Color(0xFFCD7F32),
                            120,
                            score: _leaderboardData[2]['score'] as int,
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Leaderboard List
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                    itemCount: _leaderboardData.length > 3
                        ? _leaderboardData.length - 3
                        : 0,
                    itemBuilder: (context, index) {
                      final actualIndex = index + 3;
                      final user = _leaderboardData[actualIndex]['user'] as UserModel;
                      final score = _leaderboardData[actualIndex]['score'] as int;
                      final isCurrentUser = user.id == currentUserId;

                      return _buildLeaderboardItem(
                        rank: actualIndex + 1,
                        user: user,
                        score: score,
                        isCurrentUser: isCurrentUser,
                      );
                    },
                  ),

                  // Current User Position
                  Container(
                    margin: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryRed.withOpacity(0.3),
                          AppColors.primaryRed.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryRed,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isWeekly ? 'Your Weekly Rank' : 'Your Overall Rank',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildLeaderboardItem(
                          rank: currentUserRank == -1 
                              ? _leaderboardData.length + 1 
                              : currentUserRank + 1,
                          user: currentUser,
                          score: currentUser.winningCoins,
                          isCurrentUser: true,
                          showBorder: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPodiumItem(
    UserModel user,
    int rank,
    Color medalColor,
    double height, {
    required int score,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: medalColor, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: rank == 1 ? 40 : 30,
                backgroundColor: AppColors.primaryPink,
                backgroundImage:
                    user.photoUrl != null && user.photoUrl!.isNotEmpty
                    ? NetworkImage(user.photoUrl!)
                    : null,
                child: user.photoUrl == null || user.photoUrl!.isEmpty
                    ? Text(
                        user.displayName[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: rank == 1 ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.white,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: medalColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.emoji_events,
                  color: AppColors.white,
                  size: rank == 1 ? 20 : 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: 90,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                medalColor.withOpacity(0.4),
                medalColor.withOpacity(0.2),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: medalColor, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.displayName.length > 10
                    ? '${user.displayName.substring(0, 10)}...'
                    : user.displayName,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.monetization_on, 
                    size: 16, 
                    color: medalColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$score',
                    style: TextStyle(
                      color: medalColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Winning Coins',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardItem({
    required int rank,
    required UserModel user,
    required int score,
    required bool isCurrentUser,
    bool showBorder = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppColors.primaryRed.withOpacity(0.2)
            : const Color(0xFF3D2819),
        borderRadius: BorderRadius.circular(12),
        border: showBorder && isCurrentUser
            ? Border.all(color: AppColors.primaryRed, width: 2)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? AppColors.primaryRed
                  : AppColors.primaryRed.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primaryPink,
            backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty
                ? NetworkImage(user.photoUrl!)
                : null,
            child: user.photoUrl == null || user.photoUrl!.isEmpty
                ? Text(
                    isCurrentUser ? 'You' : user.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrentUser ? 'You' : user.displayName,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.star, size: 12, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${user.rating}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.monetization_on,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$score',
                    style: const TextStyle(
                      color: AppColors.primaryRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Winning Coins',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String value;
  final String label;

  const _TimeBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryRed,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryRed.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
