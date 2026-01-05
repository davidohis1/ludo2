import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ludotitian/main.dart';
import '/constants/colors.dart';
import '/cubits/auth/auth_cubit.dart';
import '/cubits/user/user_cubit.dart';
import '/utils/toast_utils.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), centerTitle: true),
      body: BlocBuilder<UserCubit, UserState>(
        builder: (context, userState) {
          final user = userState is UserLoaded ? userState.currentUser : null;

          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Profile Picture
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: AppColors.primaryPink,
                      backgroundImage: user.photoUrl != null
                          ? NetworkImage(user.photoUrl!)
                          : null,
                      child: user.photoUrl == null
                          ? Text(
                              user.displayName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          context.navigateToEditProfile();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryRed,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: AppColors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Name
                Text(
                  user.displayName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                // ID
                Text(
                  // We can safely use user.id! because user is checked for null above.
                  'ID: ${user.id.substring(0, 8)}...',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 32),

                // Stats Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(user.totalMatches.toString(), 'Matches'),
                    _buildStatItem(
                      user.wins.toString(),
                      'Wins',
                      color: AppColors.primaryRed,
                    ),
                    _buildStatItem(user.losses.toString(), 'Losses'),
                  ],
                ),

                const SizedBox(height: 32),

                // ✅ NEW: Premium Status Card
                _buildPremiumCard(context, user),

                const SizedBox(height: 32),

                // Menu Items
                _buildMenuItem(
                  context,
                  'Change Profile Picture',
                  Icons.image,
                  () {
                    context.navigateToEditProfile();
                  },
                ),

                const SizedBox(height: 12),

                // Sound Toggle
                _buildSwitchItem('Sound', Icons.volume_up, true, (value) {
                  // Handle sound toggle
                }),

                const SizedBox(height: 12),

                // Music Toggle
                _buildSwitchItem('Music', Icons.music_note, false, (value) {
                  // Handle music toggle
                }),

                const SizedBox(height: 32),

                // Logout Button
                _buildMenuItem(context, 'Logout', Icons.logout, () async {
                  await context.read<AuthCubit>().signOut();
                  if (context.mounted) {
                    context.navigateToSignIn();
                  }
                }, color: AppColors.primaryRed),

                const SizedBox(height: 12),

                // Help & Support
                _buildMenuItem(
                  context,
                  'Help & Support',
                  Icons.help_outline,
                  () {
                    // Handle help & support
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String value, String label, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ✅ NEW: Premium Status Card
  Widget _buildPremiumCard(BuildContext context, dynamic user) {
    final bool isPremium = user.isPremium ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isPremium
            ? const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  AppColors.lightGrey,
                  AppColors.lightGrey.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? const Color(0xFFFFD700) : AppColors.lightGrey)
                .withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isPremium ? Icons.star : Icons.star_outline,
            size: 40,
            color: isPremium ? Colors.white : AppColors.textSecondary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremium ? '⭐ Premium Member' : '✨ Upgrade to Premium',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isPremium ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isPremium
                      ? 'You have exclusive benefits!'
                      : 'Get special perks and rewards',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPremium ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!isPremium)
            GestureDetector(
              onTap: () {
                _openStoreForPremium(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Buy Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ✅ NEW: Open store page for premium purchase
  void _openStoreForPremium(BuildContext context) {
    // Navigate to store/premium page
    // For now, show a dialog or navigate to a store screen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🌟 Go Premium'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Premium Membership Benefits:'),
            const SizedBox(height: 12),
            _buildBenefitItem('No ads'),
            _buildBenefitItem('Extra daily challenges'),
            _buildBenefitItem('Bonus coins reward'),
            _buildBenefitItem('Priority matchmaking'),
            _buildBenefitItem('Custom avatar frame'),
            const SizedBox(height: 16),
            const Text(
              '₦499/month or ₦4,990/year',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryRed,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Integrate with payment provider (Paystack, Flutterwave, etc.)
              ToastUtils.showInfo(context, 'Premium purchase coming soon!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
            ),
            child: const Text(
              'Buy Premium',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ NEW: Helper to display benefit items
  Widget _buildBenefitItem(String benefit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Text(benefit),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
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
            Icon(icon, color: color ?? AppColors.textPrimary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: color ?? AppColors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: color ?? AppColors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem(
    String title,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
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
          Icon(icon, color: AppColors.textPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primaryRed,
          ),
        ],
      ),
    );
  }
}
