import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  final TextEditingController _nameController =
      TextEditingController();
  final TextEditingController _emailController =
      TextEditingController();
  final TextEditingController _phoneController =
      TextEditingController();
  final TextEditingController _organizationController =
      TextEditingController();
  final TextEditingController _passwordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String _selectedRole = 'donor';

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  // Retain a newly created account so a failed profile write can
  // be retried without trying to create the Auth account again.
  User? _pendingUser;
  bool _profileSaved = false;

  bool get _canEdit => !_isLoading && _pendingUser == null;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _organizationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isLoading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    // Capture inputs before asynchronous work starts.
    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String phone = _phoneController.text.trim();
    final String password = _passwordController.text;
    final String role = _selectedRole.trim().toLowerCase();
    final String organizationName =
        role == 'ngo' ? _organizationController.text.trim() : '';

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = _pendingUser;

      if (user == null) {
        final UserCredential credential = await _authService.register(
          email: email,
          password: password,
        );

        user = credential.user;

        if (user == null) {
          throw FirebaseAuthException(
            code: 'registration-failed',
            message: 'Firebase did not return a user account.',
          );
        }

        _pendingUser = user;

        debugPrint('Registration account created. UID: ${user.uid}');
      }

      if (!_profileSaved) {
        final User? currentUser = FirebaseAuth.instance.currentUser;

        if (currentUser == null || currentUser.uid != user.uid) {
          throw FirebaseAuthException(
            code: 'registration-session-lost',
            message: 'The registration session is no longer active.',
          );
        }

        await _firestoreService.createUserProfile(
          uid: user.uid,
          email: user.email ?? email,
          role: role,
          name: name,
          phone: phone,
          organizationName: organizationName,
        );

        _profileSaved = true;

        debugPrint(
          'Registration profile saved. UID: ${user.uid}, role: $role',
        );
      }

      // Save the profile before ending the registration session.
      await FirebaseAuth.instance.signOut();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Registration successful. Please log in.',
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );

      Navigator.of(context, rootNavigator: true).popUntil(
        (route) => route.isFirst,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Registration authentication error: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: _profileSaved
            ? 'Your account and profile were saved, but sign-out failed. '
                'Tap Finish registration to retry. (${error.code})'
            : _getErrorMessage(error.code),
        backgroundColor: Colors.red.shade700,
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Registration Firestore error: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: _pendingUser != null
            ? 'Your login account was created, but the profile could '
                'not be saved. Tap Retry profile save. (${error.code})'
            : 'Registration failed. (${error.code})',
        backgroundColor: Colors.orange.shade800,
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected registration error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        message: _profileSaved
            ? 'Your account and profile were saved. '
                'Tap Finish registration to retry the final step.'
            : _pendingUser != null
                ? 'Your login account exists, but registration is incomplete. '
                    'Tap Retry profile save.'
                : 'Unable to complete registration. Please try again.',
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
          duration: const Duration(seconds: 6),
        ),
      );
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email already has an account. '
            'Log in instead. If its profile is missing, '
            'the existing profile needs recovery.';

      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'weak-password':
        return 'The password does not meet the Firebase password policy.';

      case 'network-request-failed':
        return 'Unable to connect. Check your Internet connection.';

      case 'operation-not-allowed':
        return 'Email/password authentication is disabled in Firebase.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'registration-session-lost':
        return 'The registration session ended before the profile was saved. '
            'Log in to the existing account and check its profile.';

      case 'registration-failed':
        return 'Firebase could not finish creating the account.';

      default:
        return 'Unable to complete registration. ($code)';
    }
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your $label';
    }

    return null;
  }

  String get _buttonLabel {
    if (_profileSaved) {
      return 'Finish registration';
    }

    if (_pendingUser != null) {
      return 'Retry profile save';
    }

    return 'Create account';
  }

  @override
  Widget build(BuildContext context) {
    final bool isNgo = _selectedRole == 'ngo';

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create account'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join FoodBridge',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create an account to rescue and redistribute surplus food.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 28),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'donor',
                        child: Text('Donor'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'ngo',
                        child: Text('NGO'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'volunteer',
                        child: Text('Volunteer'),
                      ),
                    ],
                    onChanged: _canEdit
                        ? (value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _selectedRole = value;
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    enabled: _canEdit,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) =>
                        _requiredValidator(value, 'full name'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    enabled: _canEdit,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final String email = value?.trim() ?? '';

                      if (email.isEmpty) {
                        return 'Enter your email address';
                      }

                      if (!email.contains('@') || !email.contains('.')) {
                        return 'Enter a valid email address';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    enabled: _canEdit,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (value) =>
                        _requiredValidator(value, 'phone number'),
                  ),
                  if (isNgo) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _organizationController,
                      enabled: _canEdit,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'NGO or organization name',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      validator: (value) =>
                          _requiredValidator(value, 'organization name'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    enabled: _canEdit,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: _canEdit
                            ? () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              }
                            : null,
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter a password';
                      }

                      if (value.length < 6) {
                        return 'Password must contain at least 6 characters';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    enabled: _canEdit,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    onFieldSubmitted: (_) {
                      if (!_isLoading) {
                        _register();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirmPassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: _canEdit
                            ? () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              }
                            : null,
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Confirm your password';
                      }

                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }

                      return null;
                    },
                  ),
                  if (_pendingUser != null && !_isLoading) ...[
                    const SizedBox(height: 16),
                    Text(
                      _profileSaved
                          ? 'Your account and profile are saved. '
                              'Finish registration to return to login.'
                          : 'Your login account already exists. '
                              'Retry saving its profile without creating '
                              'another account.',
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      child: _isLoading
                          ? const SizedBox(
                              height: 23,
                              width: 23,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(_buttonLabel),
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