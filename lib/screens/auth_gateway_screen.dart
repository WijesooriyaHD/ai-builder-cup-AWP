import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/legal_links.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'package:lottie/lottie.dart';

class AuthGatewayScreen extends StatefulWidget {
  const AuthGatewayScreen({super.key});

  @override
  State<AuthGatewayScreen> createState() => _AuthGatewayScreenState();
}

class _AuthGatewayScreenState extends State<AuthGatewayScreen> {
  final PageController _pageController = PageController(viewportFraction: 1.0);
  int _currentPage = 0;

  final List<_CarouselItem> _items = [
  _CarouselItem(
    title: 'Less\nOverthinking',
    subtitle: 'Focus on what matters most today.',
    color: const Color(0xFFFFF3BF),
    icon: Icons.psychology_rounded,
    lottieAsset: 'assets/images/thinking-relief.json',
  ),
  _CarouselItem(
    title: 'Know Your\nEnergy',
    subtitle: 'Quick check-ins help us understand you.',
    color: const Color(0xFFFFD8D8),
    icon: Icons.favorite_rounded,
    lottieAsset: 'assets/images/energy-checkin.json',
  ),
  _CarouselItem(
    title: 'Get Your\nDaily Plan',
    subtitle: 'Personalized wellness guidance for today.',
    color: const Color(0xFFD0EBFF),
    icon: Icons.auto_awesome_rounded,
    lottieAsset: 'assets/images/daily-plan.json',
  ),
  _CarouselItem(
    title: 'Build Your\nWellness Rhythm',
    subtitle: 'Small steps that fit your real life.',
    color: const Color(0xFFE5DBFF),
    icon: Icons.self_improvement_rounded,
    lottieAsset: 'assets/images/wellness-rhythm.json',
  ),
  ];

  void _showAuthModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AuthModal(),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final activeColor = _items[_currentPage].color;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        // Soft ambient background that gently tints toward the active card color
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              activeColor.withOpacity(0.35),
              theme.scaffoldBackgroundColor,
              theme.scaffoldBackgroundColor,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Carousel
              SizedBox(
                height: 550,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        double value = 1.0;
                         if (_pageController.position.haveDimensions) {
                           value = _pageController.page! - index;
                           value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                         } else {
                           // Initial state before layout
                           value = index == _currentPage ? 1.0 : 0.7;
                         }
                         
                         final double curve = Curves.easeOut.transform(value);
                         
                        return Center(
                          child: SizedBox(
                            height: curve * 550, // Scale height
                            width: curve * 350,   // Scale width
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0), // Reduced horizontal padding
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Placeholder Card
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _items[index].color.withOpacity(0.45),
                                      _items[index].color.withOpacity(0.15),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.35),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _items[index].color.withOpacity(0.35),
                                      blurRadius: 30,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: _items[index].lottieAsset != null
                                    ? Lottie.asset(
                                        _items[index].lottieAsset!,
                                        fit: BoxFit.contain,
                                      )
                                    : Icon(
                                        _items[index].icon,
                                        size: 100,
                                        color: _items[index].color,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Title
                            Text(
                              _items[index].title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                                color: theme.textTheme.displayLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Subtitle
                            Text(
                              _items[index].subtitle,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.dmSans(
                                fontSize: 16,
                                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              
              // Indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_items.length, (index) {
                  final bool isActive = _currentPage == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: isActive ? 28 : 8,
                    decoration: BoxDecoration(
                      color: isActive
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 12),

              // Step label
              Text(
                'Step ${_currentPage + 1} of ${_items.length}',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                ),
              ),

              const SizedBox(height: 36),

                // Auth Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: _SocialButton(
                  text: _currentPage == _items.length - 1 ? 'Continue with Account' : 'Next',
                  icon: _currentPage == _items.length - 1 ? Icons.person_outline : Icons.arrow_forward,
                  color: _currentPage == _items.length - 1 ? theme.colorScheme.primary : Colors.black,
                  textColor: Colors.white,
                  onPressed: () {
                    if (_currentPage == _items.length - 1) {
                      _showAuthModal(context);
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
              
              // Footer Terms
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text.rich(
                  TextSpan(
                    text: 'By tapping "Continue" you acknowledge that you have read and agree to the AI Wellness Pal ',
                    children: [
                      TextSpan(
                        text: 'Terms of Use',
                        style: const TextStyle(decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => LegalLinks.open(LegalLinks.termsOfUse),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => LegalLinks.open(LegalLinks.privacyPolicy),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
  );
}
}

class _CarouselItem {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final String? lottieAsset;

  _CarouselItem({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    this.lottieAsset,
  });
}

class _SocialButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _SocialButton({
    required this.text,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 22),
          ],
        ),
      ),
    );
  }
}

class _AuthModal extends StatefulWidget {
  const _AuthModal();

  @override
  State<_AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<_AuthModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _loginMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Clear message when switching tabs manually
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.animation?.value != _tabController.index) {
        setState(() {}); // Rebuild to switch visible widget
        if (_tabController.indexIsChanging) {
          _loginMessage = null;
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        // height: Removed fixed height for flexibility
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min, // Wrap content height
          children: [
            const SizedBox(height: 12),
            // Drag Handle
            Container(
              height: 5,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Text(
              'Welcome to AI Wellness Pal',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.displayLarge?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Log in or create an account to continue',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(30),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                padding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                onTap: (index) {
                  setState(() {}); // Ensure instant update on tap
                },
                tabs: const [
                  Tab(
                    text: 'Log In',
                    icon: Icon(Icons.login_rounded),
                    iconMargin: EdgeInsets.only(bottom: 4),
                  ),
                  Tab(
                    text: 'Sign Up',
                    icon: Icon(Icons.person_add_rounded),
                    iconMargin: EdgeInsets.only(bottom: 4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Form Content - Flexible Height
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutQuart,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _tabController.index == 0
                    ? _LoginCard(key: const ValueKey('login'), infoMessage: _loginMessage)
                    : _SignupCard(
                        key: const ValueKey('signup'),
                        onSwitchToLogin: () {
                          setState(() {
                             _loginMessage = "Account created! Verify in email to login.";
                             _tabController.animateTo(0);
                          });
                        }),
              ),
            ),
            const SizedBox(height: 24), // Bottom padding
          ],
        ),
      ),
    ),
  );
}
}

class _LoginCard extends StatefulWidget {
  final String? infoMessage;

  const _LoginCard({super.key, this.infoMessage});

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = await AuthService().signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Check if the user's Firestore document exists.
      // If the account was previously deleted, the Firebase Auth user may
      // still exist but the Firestore data is gone.
      final user = credential.user;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!doc.exists) {
          // Account data was deleted — sign out and show error
          await AuthService().signOut();
          if (mounted) {
            setState(() => _errorMessage =
                'Account not found. Please sign up to create a new account.');
          }
          return;
        }
      }

      // Close modal immediately after successful sign-in so the
      // AuthWrapper StreamBuilder can show the authenticated view
      // without the modal sitting on top.
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      
      // Sync metadata to public.profiles table (non-blocking)
      StorageService().syncProfile();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await AuthService().signInWithGoogle();
      if (userCredential == null) {
        // User cancelled the Google sign-in flow
        return;
      }

      // Close modal — AuthWrapper handles routing
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Sync metadata (non-blocking)
      StorageService().syncProfile();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await AuthService().signInWithApple();
      if (userCredential == null) {
        // User cancelled the Apple sign-in flow
        return;
      }

      // Close modal — AuthWrapper handles routing
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Sync metadata (non-blocking)
      StorageService().syncProfile();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Apple sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            if (widget.infoMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  widget.infoMessage!,
                  style: GoogleFonts.dmSans(color: Colors.green, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.dmSans(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            _buildTextField(
              controller: _emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: true,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Log In'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: GoogleFonts.dmSans(color: Colors.grey)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            if (Platform.isIOS) ...[
              _AppleSignInButton(onPressed: _isLoading ? null : _signInWithApple),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.dmSans(color: theme.textTheme.bodyLarge?.color),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: (value) => value != null && value.isNotEmpty ? null : 'Required',
    );
  }
}

class _SignupCard extends StatefulWidget {
  final VoidCallback onSwitchToLogin;

  const _SignupCard({super.key, required this.onSwitchToLogin});

  @override
  State<_SignupCard> createState() => _SignupCardState();
}

class _SignupCardState extends State<_SignupCard> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _errorMessage = "Passwords do not match");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      // Sync metadata to public.profiles table if user is available
      await StorageService().syncProfile();

      // Close modal — user is now signed in and AuthWrapper will
      // route them to OnboardingScreen.
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await AuthService().signInWithGoogle();
      if (userCredential == null) {
        // User cancelled the Google sign-in flow
        return;
      }

      // Sync metadata
      await StorageService().syncProfile();

      // Close modal — AuthWrapper handles routing
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Google sign-up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpWithApple() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await AuthService().signInWithApple();
      if (userCredential == null) {
        // User cancelled the Apple sign-in flow
        return;
      }

      // Sync metadata
      await StorageService().syncProfile();

      // Close modal — AuthWrapper handles routing
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Apple sign-up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.dmSans(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            _buildTextField(
              controller: _emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: true,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _confirmController,
              label: 'Confirm Password',
              icon: Icons.lock_outline,
              obscureText: true,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signup,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Sign Up'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: GoogleFonts.dmSans(color: Colors.grey)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            if (Platform.isIOS) ...[
              _AppleSignInButton(onPressed: _isLoading ? null : _signUpWithApple),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _signUpWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.dmSans(color: theme.textTheme.bodyLarge?.color),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: (value) => value != null && value.isNotEmpty ? null : 'Required',
    );
  }
}

/// Sign in with Apple button following Apple's Human Interface Guidelines
/// (black in light mode, white in dark mode, Apple logo + standard title).
class _AppleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _AppleSignInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? Colors.white : Colors.black;
    final foreground = isDark ? Colors.black : Colors.white;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.apple, size: 22, color: foreground),
        label: Text(
          'Continue with Apple',
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
