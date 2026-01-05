import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/cubits/user/user_cubit.dart';
import '/cubits/auth/auth_cubit.dart';
import '/screens/theme/app_theme.dart';
import '/screens/home_screen.dart';
import '/screens/leaderboard_screen.dart';
import '/screens/wallet_screen.dart';
import '/screens/profile_screen.dart';
import '/screens/store_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const LeaderboardScreen(),
    const WalletScreen(),
    const ProfileScreen(),
    const StoreScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ FIXED: Wait for user data before showing content
    return BlocBuilder<UserCubit, UserState>(
      builder: (context, userState) {
        print('🏠 MainScreen: UserState = ${userState.runtimeType}');

        // ✅ Show loading screen while waiting for data
        if (userState is UserInitial || userState is UserLoading) {
          print('⏳ MainScreen: Loading user data...');
          return Scaffold(
            backgroundColor: kBackgroundColor,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: kPrimaryColor),
                  const SizedBox(height: 20),
                  Text(
                    'Loading your data...',
                    style: kBodyTextStyle.copyWith(color: kPrimaryColor),
                  ),
                ],
              ),
            ),
          );
        }

        // ✅ Show error screen if something went wrong
        if (userState is UserError) {
          print('❌ MainScreen: Error - ${userState.message}');
          return Scaffold(
            backgroundColor: kBackgroundColor,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Failed to load data',
                      style: kHeadingStyle.copyWith(fontSize: 24),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      userState.message,
                      style: kBodyTextStyle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Try to reload data
                        final authState = context.read<AuthCubit>().state;
                        if (authState is AuthAuthenticated) {
                          context.read<UserCubit>().loadUserData(authState.userId);
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        context.read<AuthCubit>().signOut();
                      },
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ✅ Data is loaded - show the main screen
        if (userState is UserLoaded) {
          print('✅ MainScreen: Data loaded successfully');
          print('   User: ${userState.currentUser.displayName}');
          print('   Coins: ${userState.currentUser.totalCoins}');
          print('   Lives: ${userState.currentUser.lives}');

          return Scaffold(
            body: _pages[_selectedIndex],
            
            // Bottom Navigation Bar
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: kCardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                items: const <BottomNavigationBarItem>[
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.emoji_events_outlined),
                    activeIcon: Icon(Icons.emoji_events),
                    label: 'Leaderboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.wallet_outlined),
                    activeIcon: Icon(Icons.wallet),
                    label: 'Wallet',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.store_outlined),
                    activeIcon: Icon(Icons.store),
                    label: 'Store',
                  ),
                ],
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
              ),
            ),
          );
        }

        // ✅ Fallback (should never reach here)
        print('⚠️ MainScreen: Unexpected state');
        return Scaffold(
          backgroundColor: kBackgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber, size: 60, color: Colors.orange),
                const SizedBox(height: 20),
                Text(
                  'Unexpected error',
                  style: kBodyTextStyle,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    context.read<AuthCubit>().signOut();
                  },
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}