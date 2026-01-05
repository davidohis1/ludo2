import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ludotitian/screens/game/game_screen.dart';
import '/constants/colors.dart';
import '/constants/app_constants.dart';
import '/cubits/user/user_cubit.dart';
import '/cubits/game/game_cubit.dart';
import '/cubits/auth/auth_cubit.dart';
import '/models/user_model.dart';
import '/models/game_model.dart';
import '/utils/toast_utils.dart';

class SelectTierScreen extends StatefulWidget {
  const SelectTierScreen({super.key});

  @override
  State<SelectTierScreen> createState() => _SelectTierScreenState();
}

class _SelectTierScreenState extends State<SelectTierScreen> {
  String? _selectedTier;

  @override
  void initState() {
    super.initState();
    _selectedTier = 'bronze';
  }

  // ==================== GAME CREATION ====================

  Future<void> _createGame(
    BuildContext context,
    String tier,
    UserModel user,
  ) async {
    try {
      print('🎮 Creating game room...');

      final authState = context.read<AuthCubit>().state;
      if (authState is! AuthAuthenticated) {
        throw Exception('Not authenticated');
      }

      await context.read<GameCubit>().createGame(
        hostId: user.id,
        hostName: user.displayName,
        hostPhoto: user.photoUrl ?? '',
        tier: tier,
        maxPlayers: AppConstants.maxPlayers,
        turnDuration: AppConstants.turnDuration,
      );

      print('✅ Game room created');
    } catch (e) {
      print('❌ Error creating game: $e');
      if (mounted) {
        ToastUtils.showError(context, 'Failed to create game: $e');
      }
    }
  }

  // ==================== MATCHMAKING OPTIONS ====================

  void _showMatchmakingOptionsModal(
    BuildContext context,
    String tier,
    UserModel user,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'Choose Game Mode',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tier.toUpperCase(),
              style: TextStyle(
                fontSize: 16,
                color: _getTierColor(tier),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),

            // Create Game Option
            _buildOptionCard(
              icon: Icons.add_circle_outline,
              title: 'Create Game',
              description: 'Host a game and wait for players to join',
              color: AppColors.primaryRed,
              onTap: () {
                Navigator.pop(context);
                _createGame(context, tier, user);
              },
            ),
            const SizedBox(height: 16),

            // Join Game Option
            _buildOptionCard(
              icon: Icons.people_outline,
              title: 'Join Game',
              description: 'Browse and join available games',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                _showAvailableGames(context, tier);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  // ==================== AVAILABLE GAMES ====================

  void _showAvailableGames(BuildContext context, String tier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Available Games',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            tier.toUpperCase(),
                            style: TextStyle(
                              fontSize: 14,
                              color: _getTierColor(tier),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(),

              // Games list
              Expanded(
                child: StreamBuilder<List<GameModel>>(
                  stream: context.read<GameCubit>().getAvailableGames(tier),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final games = snapshot.data ?? [];

                    if (games.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.games_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No games available',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Be the first to create one!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: games.length,
                      itemBuilder: (context, index) {
                        final game = games[index];
                        print(game.id);
                        print(game.playerPhotos);
                        print(game.playerIds);
                        print(game.playerNames);

                        if (game.playerIds.isEmpty ||
                            game.playerPhotos.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _buildGameCard(context, game);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, GameModel game) {
    final playerCount = game.playerIds.length;
    const maxPlayers = 4; // You can get this from game if stored

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _joinGame(context, game.id),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Host avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _getTierColor(game.tier),
                    backgroundImage:
                        game.playerPhotos[game.playerIds.first] != null &&
                            game.playerPhotos[game.playerIds.first]!.isNotEmpty
                        ? NetworkImage(game.playerPhotos[game.playerIds.first]!)
                        : null,
                    child:
                        game.playerPhotos[game.playerIds.first] == null ||
                            game.playerPhotos[game.playerIds.first]!.isEmpty
                        ? Text(
                            (game.playerNames[game.playerIds.first] ?? 'P')[0]
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
                          game.playerNames[game.playerIds.first] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Host',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Player count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people,
                          size: 16,
                          color: AppColors.primaryRed,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$playerCount/$maxPlayers',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Game details
              Row(
                children: [
                  _buildGameDetail(
                    Icons.monetization_on,
                    '${game.entryFee} Coins',
                    Colors.orange,
                  ),
                  const SizedBox(width: 16),
                  _buildGameDetail(
                    Icons.emoji_events,
                    '${game.prizePool} Prize',
                    Colors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Players preview
              if (game.playerIds.length > 1)
                Wrap(
                  spacing: -8,
                  children: game.playerIds.skip(1).take(3).map((playerId) {
                    return CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                          game.playerPhotos[playerId] != null &&
                              game.playerPhotos[playerId]!.isNotEmpty
                          ? NetworkImage(game.playerPhotos[playerId]!)
                          : null,
                      child:
                          game.playerPhotos[playerId] == null ||
                              game.playerPhotos[playerId]!.isEmpty
                          ? Text(
                              (game.playerNames[playerId] ?? 'P')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameDetail(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Future<void> _joinGame(BuildContext context, String gameId) async {
    try {
      Navigator.pop(context); // Close modal

      final authState = context.read<AuthCubit>().state;
      if (authState is! AuthAuthenticated) {
        throw Exception('Not authenticated');
      }

      await context.read<GameCubit>().joinExistingGame(
        gameId: gameId,
        userId: authState.userId,
      );

      print('✅ Joined game successfully');
    } catch (e) {
      print('❌ Error joining game: $e');
      if (mounted) {
        ToastUtils.showError(context, 'Failed to join game: $e');
      }
    }
  }

  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return AppColors.grey;
      case 'gold':
        return const Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }

  // ==================== GAME LOBBY VIEW ====================

  Widget _buildGameLobbyView(
    BuildContext context,
    UserModel user,
    GameModel game,
  ) {
    final isHost = game.playerIds.first == user.id;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people, size: 64, color: AppColors.primaryRed),
              const SizedBox(height: 16),
              const Text(
                'Game Lobby',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                game.tier.toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  color: _getTierColor(game.tier),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // Players list
              Text(
                'Players (${game.playerIds.length}/4)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              ...game.playerIds.map((playerId) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            game.playerPhotos[playerId] != null &&
                                game.playerPhotos[playerId]!.isNotEmpty
                            ? NetworkImage(game.playerPhotos[playerId]!)
                            : null,
                        child:
                            game.playerPhotos[playerId] == null ||
                                game.playerPhotos[playerId]!.isEmpty
                            ? Text(game.playerNames[playerId]![0].toUpperCase())
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          game.playerNames[playerId] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (playerId == game.playerIds.first)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'HOST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),

              // Host controls
              if (isHost) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _startGameAsHost(context, game.id),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Game'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Leave/Cancel button
              TextButton.icon(
                onPressed: () =>
                    _leaveGameLobby(context, user.id, game.id, isHost),
                icon: const Icon(Icons.exit_to_app, color: AppColors.error),
                label: Text(
                  isHost ? 'Cancel Game' : 'Leave Lobby',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startGameAsHost(BuildContext context, String gameId) async {
    try {
      await context.read<GameCubit>().startGameAsHost(gameId);

      print('✅ Game started by host');
    } catch (e) {
      print('❌ Error starting game: $e');
      if (mounted) {
        ToastUtils.showError(context, 'Failed to start game: $e');
      }
    }
  }

  Future<void> _leaveGameLobby(
    BuildContext context,
    String userId,
    String gameId,
    bool isHost,
  ) async {
    try {
      await context.read<GameCubit>().leaveGameLobby(gameId, userId, isHost);
      print('✅ Left game lobby');
    } catch (e) {
      print('❌ Error leaving lobby: $e');
    }
  }

  // ==================== BUILD METHOD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Tier'), centerTitle: true),
      body: BlocBuilder<UserCubit, UserState>(
        builder: (context, userState) {
          return BlocConsumer<GameCubit, GameState>(
            listener: (context, gameState) {
              if (gameState is GameLoaded &&
                  gameState.game.status == GameStatus.inProgress) {
                print('🎮 Game started - navigate to game screen');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GameScreen(gameId: gameState.game.id),
                  ),
                );
              }
            },
            builder: (context, gameState) {
              final user = userState is UserLoaded
                  ? userState.currentUser
                  : null;

              if (user == null) {
                return const Center(child: CircularProgressIndicator());
              }

              // Show game lobby if in waiting state
              if (gameState is GameLoaded &&
                  gameState.game.status == GameStatus.waiting) {
                return _buildGameLobbyView(context, user, gameState.game);
              }

              final selectedTier = _selectedTier ?? 'bronze';

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUserInfoCard(user),
                    const SizedBox(height: 24),
                    _buildTierCard(
                      context,
                      tier: 'bronze',
                      title: 'Bronze',
                      entryFee: AppConstants.tierEntryFees['bronze']!,
                      prizePool: AppConstants.tierPrizePools['bronze']!,
                      players: AppConstants.maxPlayers,
                      color: const Color(0xFFCD7F32),
                      userCoins: user.totalCoins,
                      userLives: user.lives,
                      isSelected: selectedTier == 'bronze',
                      onTap: () => setState(() => _selectedTier = 'bronze'),
                    ),
                    const SizedBox(height: 16),
                    _buildTierCard(
                      context,
                      tier: 'silver',
                      title: 'Silver',
                      entryFee: AppConstants.tierEntryFees['silver']!,
                      prizePool: AppConstants.tierPrizePools['silver']!,
                      players: AppConstants.maxPlayers,
                      color: AppColors.grey,
                      userCoins: user.totalCoins,
                      userLives: user.lives,
                      isSelected: selectedTier == 'silver',
                      onTap: () => setState(() => _selectedTier = 'silver'),
                    ),
                    const SizedBox(height: 16),
                    _buildTierCard(
                      context,
                      tier: 'gold',
                      title: 'Gold',
                      entryFee: AppConstants.tierEntryFees['gold']!,
                      prizePool: AppConstants.tierPrizePools['gold']!,
                      players: AppConstants.maxPlayers,
                      color: const Color(0xFFFFD700),
                      userCoins: user.totalCoins,
                      userLives: user.lives,
                      isSelected: selectedTier == 'gold',
                      onTap: () => setState(() => _selectedTier = 'gold'),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            user.totalCoins >= AppConstants.tierEntryFees[selectedTier]! // REMOVED: user.lives > 0 &&
                                ? () => _showMatchmakingOptionsModal(
                                    context,
                                    selectedTier,
                                    user,
                                  )
                                : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          user.totalCoins >= AppConstants.tierEntryFees[selectedTier]! // CHANGED: Removed life check
                              ? 'Play Game'
                              : 'Insufficient Coins', // CHANGED: Removed "No Lives Available"
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Keep your existing _buildUserInfoCard and _buildTierCard methods
  Widget _buildUserInfoCard(UserModel user) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: AppColors.black.withOpacity(0.1),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty
              ? NetworkImage(user.photoUrl!)
              : null,
          child: user.photoUrl == null || user.photoUrl!.isEmpty
              ? Text(
                  user.displayName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  // OPTIONAL: Keep lives display but remove from gameplay logic
                  // Icon(Icons.favorite, color: Colors.red[400], size: 16),
                  // const SizedBox(width: 3),
                  // Text(
                  //   '${user.lives} Lives',
                  //   style: const TextStyle(
                  //     fontSize: 14,
                  //     fontWeight: FontWeight.w600,
                  //   ),
                  // ),
                  // const SizedBox(width: 8),
                  const Icon(
                    Icons.monetization_on,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${user.totalCoins} Coins',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.star, size: 16, color: AppColors.warning),
                  const SizedBox(width: 3),
                  Text(
                    '${user.rating}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildTierCard(
    BuildContext context, {
    required String tier,
    required String title,
    required int entryFee,
    required int prizePool,
    required int players,
    required Color color,
    required int userCoins,
    required int userLives,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final canAfford = userCoins >= entryFee; // REMOVED: && userLives > 0

    return GestureDetector(
      onTap: canAfford ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppColors.primaryRed, width: 3)
              : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.emoji_events, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Entry: $entryFee Coins', // REMOVED: + 1 Life
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primaryRed,
                    size: 28,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Prize Pool',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$prizePool Coins',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Players',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$players Players',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (!canAfford) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Text(
                      'Insufficient Coins', // CHANGED: Removed life check message
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
