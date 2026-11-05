import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'auth_gate.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final TextEditingController _emailController =
      TextEditingController();
  final TextEditingController _passwordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isResettingPassword = false;

  bool get _isBusy => _isLoading || _isResettingPassword;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final String email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Enter your email address';
    }

    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address';
    }

    return null;
  }

  Future<void> _login() async {
    if (_isBusy) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.login(
        email: email,
        password: password,
      );

      final User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-auth-session',
          message: 'Login completed without an active user session.',
        );
      }

      debugPrint('Login succeeded. UID: ${user.uid}');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Open a fresh AuthGate and remove old authentication routes.
      // AuthGate reads the profile and chooses the role dashboard.
      Navigator.of(context, rootNavigator: true)
          .pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AuthGate(),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Firebase login error: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: '${_getAuthErrorMessage(error.code)} (${error.code})',
        backgroundColor: Colors.red.shade700,
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected login error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: 'Unable to finish login. Please try again.',
        backgroundColor: Colors.red.shade700,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_isBusy) {
      return;
    }

    final String email = _emailController.text.trim();

    if (_validateEmail(email) != null) {
      _showMessage(
        message: 'Enter a valid email address first.',
        backgroundColor: Colors.orange.shade800,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isResettingPassword = true;
    });

    try {
      await _authService.sendPasswordResetEmail(email);

      if (!mounted) {
        return;
      }

      _showMessage(
        message:
            'If an account exists for this email, '
            'you should receive password reset instructions.',
        backgroundColor: Colors.green.shade700,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Password reset error: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: '${_getAuthErrorMessage(error.code)} (${error.code})',
        backgroundColor: Colors.red.shade700,
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected password reset error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: 'Unable to send password reset instructions.',
        backgroundColor: Colors.red.shade700,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResettingPassword = false;
        });
      }
    }
  }

  void _showMessage({
    required String message,
    required Color backgroundColor,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'wrong-password':
      case 'user-not-found':
        return 'Invalid email or password.';

      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Try again later.';

      case 'network-request-failed':
        return 'Unable to connect. Check your Internet connection.';

      case 'operation-not-allowed':
        return 'Email/password authentication is disabled in Firebase.';

      case 'api-key-not-valid':
      case 'invalid-api-key':
        return 'Firebase API configuration is invalid.';

      case 'app-not-authorized':
        return 'This app is not authorized in Firebase.';

      case 'weak-password':
        return 'The password does not meet the required policy.';

      case 'email-already-in-use':
        return 'This email is already registered.';

      case 'requires-recent-login':
        return 'Please log in again before continuing.';

      case 'missing-auth-session':
        return 'No active login session was created. Please try again.';

      default:
        return 'Unable to complete authentication. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/foodbridge_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue to FoodBridge.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 36),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isBusy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_isBusy,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [
                    AutofillHints.password,
                  ],
                  onFieldSubmitted: (_) {
                    if (!_isBusy) {
                      _login();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: _isBusy
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your password';
                    }

                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isBusy ? null : _resetPassword,
                    child: Text(
                      _isResettingPassword
                          ? 'Sending instructions...'
                          : 'Forgot password?',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isBusy ? null : _login,
                    child: _isLoading
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Login'),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _isBusy
                        ? null
                        : () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const RegisterScreen(),
                              ),
                            );
                          },
                    child: const Text('Create a new account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}