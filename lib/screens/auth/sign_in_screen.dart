import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/cubits/auth/auth_cubit.dart';
import '/cubits/user/user_cubit.dart';
import '/screens/theme/app_theme.dart';
import '/utils/toast_utils.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
    print('Error: $message');
    ToastUtils.showError(context, message);
  }

  Future<void> _signInWithEmail() async {
    if (_emailController.text.trim().isEmpty || 
        _passwordController.text.trim().isEmpty) {
      _showError('Please enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await context.read<AuthCubit>().signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // Navigation happens in MultiBlocListener below
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await context.read<AuthCubit>().signInWithGoogle();
      // Navigation happens in MultiBlocListener below
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _signInWithFacebook() async {
    _showError(
      'Facebook Sign-in integration requires native setup (outside of this demo).',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      // ✅ FIXED: Listen to BOTH AuthCubit AND UserCubit
      body: MultiBlocListener(
        listeners: [
          BlocListener<AuthCubit, AuthState>(
            listener: (context, authState) {
              print('🔔 SignIn: Auth state = ${authState.runtimeType}');
              
              if (authState is AuthAuthenticated) {
                print('✅ SignIn: User authenticated, initializing UserCubit...');
                
                // ✅ Initialize UserCubit with auth data
                context.read<UserCubit>().emit(
                  UserLoaded(currentUser: authState.currentUser),
                );
                
                // ✅ Start user stream for real-time updates
                context.read<UserCubit>().startUserStream(authState.userId);
                
                // ✅ Wait a tiny bit to ensure UserCubit state is set
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    print('✅ SignIn: Navigating to main screen...');
                    Navigator.of(context).pushReplacementNamed('/main');
                  }
                });
              } else if (authState is AuthError) {
                _showError(authState.message);
              } else if (authState is AuthLoading) {
                setState(() {
                  _isLoading = true;
                });
              }
            },
          ),
          
          // ✅ Also listen to UserCubit for debugging
          BlocListener<UserCubit, UserState>(
            listener: (context, userState) {
              print('👤 SignIn: User state = ${userState.runtimeType}');
              if (userState is UserLoaded) {
                print('   User loaded: ${userState.currentUser.displayName}');
                print('   Coins: ${userState.currentUser.totalCoins}');
              }
            },
          ),
        ],
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    Center(
                      child: Text(
                        'LudoTitan',
                        style: kHeadingStyle.copyWith(
                          color: kBlackColor.withOpacity(0.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                    Text(
                      'Get Started',
                      style: kHeadingStyle.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Login or Sign Up to play.',
                      style: kBodyTextStyle,
                    ),
                    const SizedBox(height: 40),

                    buildSocialButton(
                      text: 'Continue with Google',
                      color: kCardColor,
                      textColor: kBlackColor,
                      icon: Icons.g_mobiledata,
                      onTap: _signInWithGoogle,
                    ),
                    buildSocialButton(
                      text: 'Continue with Apple',
                      color: kBlackColor,
                      textColor: kWhiteColor,
                      icon: Icons.apple,
                      onTap: () => _showError(
                        'Apple Sign-in is not implemented in this demo.',
                      ),
                    ),
                    buildSocialButton(
                      text: 'Continue with Facebook',
                      color: const Color(0xFF1877F2),
                      textColor: kWhiteColor,
                      icon: Icons.facebook,
                      onTap: _signInWithFacebook,
                    ),

                    const SizedBox(height: 20),
                    const Center(child: Text('OR', style: kBodyTextStyle)),
                    const SizedBox(height: 20),

                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: 'Email'),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Password'),
                    ),
                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            _showError('Password reset feature not implemented.'),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: _isLoading ? null : _signInWithEmail,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: kWhiteColor)
                          : const Text('Sign In'),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account?",
                          style: kBodyTextStyle,
                        ),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pushNamed(context, '/sign_up'),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: kPrimaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget buildSocialButton({
  required String text,
  required Color color,
  required Color textColor,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8.0),
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        minimumSize: const Size(double.infinity, 56),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    ),
  );
}