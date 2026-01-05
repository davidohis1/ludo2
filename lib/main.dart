import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ludotitian/screens/daily_challenges_screen.dart';
import 'package:ludotitian/screens/edit_profile_screen.dart';
import 'package:ludotitian/screens/game/select_tier_screen.dart';
import 'package:toastification/toastification.dart';

// Firebase
import 'firebase_options.dart';

// Cubits
import 'cubits/auth/auth_cubit.dart';
import 'cubits/user/user_cubit.dart';
import 'cubits/game/game_cubit.dart';

// Models
import 'models/game_tier.dart';

// Screens
import 'screens/theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/main_screen.dart';
import 'screens/game/game_screen.dart';

Future<void> main() async {
  // Ensure Flutter widgets are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const LudoTitanApp());
}

class LudoTitanApp extends StatelessWidget {
  const LudoTitanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // 1. Auth Cubit - Must be first (highest priority)
        BlocProvider(
          create: (_) {
            print('✅ [CUBIT CREATION] AuthCubit created');
            return AuthCubit();
          },
        ),

        // 2. User Cubit - Depends on Auth Cubit
        BlocProvider(
          create: (context) {
            print('✅ [CUBIT CREATION] UserCubit created');
            return UserCubit();
          },
        ),

        // 3. Game Cubit - Depends on Auth Cubit
        BlocProvider(
          create: (context) {
            print('✅ [CUBIT CREATION] GameCubit created');
            return GameCubit();
          },
        ),
      ],
      child: MaterialApp(
        title: 'LudoTitan',
        builder: (context, child) {
          return ToastificationWrapper(child: child!);
        },
        debugShowCheckedModeBanner: false,
        theme: kAppTheme,

        home: const AuthWrapper(),
        onUnknownRoute: (RouteSettings settings) {
          return MaterialPageRoute(builder: (context) => const AuthWrapper());
        },

        // Define named routes for navigation
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/sign_in': (context) => const SignInScreen(),
          '/sign_up': (context) => const SignUpScreen(),
          '/main': (context) => const MainScreen(),
          '/edit': (context) => const EditProfileScreen(),
          '/select_tier': (context) => const SelectTierScreen(),
          '/daily_challenges': (context) => const DailyChallengesScreen(),
        },
      ),
    );
  }
}

// ==================== AUTH WRAPPER ====================
// Handles routing based on authentication state

class AuthWrapper extends StatefulWidget {
  final Widget? child;
  const AuthWrapper({super.key, this.child});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Start initialization only once
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    // Wait a bit for auth state to be determined
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show splash while initializing
    if (!_initialized) {
      return const SplashScreen();
    }

    print('🏗️  [AUTH WRAPPER] build called');
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, authState) {
        print('🔐 [AUTH WRAPPER] Auth state changed: $authState');

        if (authState is AuthAuthenticated) {
          print('   → Starting user stream for ${authState.userId}');
          context.read<UserCubit>().startUserStream(authState.userId);
          // Load user data

          // ✅ START LEADERBOARD STREAM
          context.read<UserCubit>().startLeaderboardStream();
          // context.read<GameCubit>().initialize();
        } else if (authState is AuthUnauthenticated) {
          print('   → Stopping user stream');
          context.read<UserCubit>().clearUser();
          context.read<GameCubit>().clear();
        }
      },
      child: BlocBuilder<AuthCubit, AuthState>(
        buildWhen: (previous, current) {
          // Only rebuild when state actually changes meaningfully
          return previous.runtimeType != current.runtimeType;
        },
        builder: (context, authState) {
          print('🔐 [AUTH WRAPPER] Auth state: $authState');

          if (authState is AuthInitial) {
            print('📱 [AUTH WRAPPER] Showing splash screen (uninitialized)');
            return const SplashScreen();
          } else if (authState is AuthLoading) {
            print('⏳ [AUTH WRAPPER] Showing loading screen');
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Signing you in...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            );
          } else if (authState is AuthAuthenticated) {
            print('✅ [AUTH WRAPPER] User authenticated - showing MainScreen');
            return const MainScreen();
          } else if (authState is AuthError) {
            print('❌ [AUTH WRAPPER] Auth error - showing SignInScreen');
            return const SignInScreen();
          } else {
            // AuthUnauthenticated
            print('🔓 [AUTH WRAPPER] Not authenticated - showing SignInScreen');
            return const SignInScreen();
          }
        },
      ),
    );
  }
}

// ==================== NAVIGATION HELPERS ====================
// Extension methods for easy navigation with Bloc context

extension NavigationExtensions on BuildContext {
  // Navigate to game screen with proper parameters
  Future<void> navigateToGame({
    required String gameId,
    required String playerId,
    required int playerPosition,
    required TierConfig tierConfig,
  }) {
    return Navigator.pushNamed(
      this,
      '/game',
      arguments: {
        'gameId': gameId,
        'playerId': playerId,
        'playerPosition': playerPosition,
        'tierConfig': tierConfig,
      },
    );
  }

  // Navigate to tier selection
  Future<void> navigateToSelectTier() {
    return Navigator.pushNamed(this, '/select_tier');
  }

  // Navigate to main screen (clear stack)
  Future<void> navigateToMain() {
    return Navigator.pushNamedAndRemoveUntil(this, '/main', (route) => false);
  }

  Future<void> navigateToChallenges() {
    return Navigator.pushNamed(this, '/daily_challenges');
  }

  ///Navigate to edit profile
  Future<void> navigateToEditProfile() {
    return Navigator.pushNamed(this, '/edit');
  }

  // Navigate to sign in (clear stack)
  Future<void> navigateToSignIn() {
    return Navigator.pushNamedAndRemoveUntil(
      this,
      '/sign_in',
      (route) => false,
    );
  }
}
