import 'package:flutter/material.dart';

import '../services/demo_auth_store.dart';
import '../theme/app_theme.dart';

class DemoAuthScreen extends StatefulWidget {
  const DemoAuthScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
  });

  final Future<DemoAccount?> Function(String identifier, String password)
  onSignIn;
  final Future<void> Function(String username, String email, String password)
  onSignUp;

  @override
  State<DemoAuthScreen> createState() => _DemoAuthScreenState();
}

class _DemoAuthScreenState extends State<DemoAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isSignUp = false;
  bool _showPassword = false;
  bool _isSubmitting = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _identifier.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              color: AppTheme.panel,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.sports_esports_rounded,
                        color: AppTheme.blue,
                        size: 42,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'GAMEVAULT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          letterSpacing: 2.5,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSignUp ? 'Create your account' : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.secondaryText,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: _validateUsername,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: _validateEmail,
                        ),
                      ] else
                        TextFormField(
                          controller: _identifier,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email or username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your email or username'
                              : null,
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        textInputAction: _isSignUp
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: _isSignUp
                            ? _validatePassword
                            : (value) => value == null || value.isEmpty
                                  ? 'Enter your password'
                                  : null,
                      ),
                      if (_isSignUp) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: !_showPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Confirm your password';
                            }
                            if (value != _password.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.blue),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isSubmitting ? null : _toggleMode,
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Sign In'
                              : "Don't have an account? Sign Up",
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Demo authentication only. Accounts are stored in this browser and are not secure production credentials.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Enter a username';
    if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(username)) {
      return 'Use 3–20 letters, numbers, or underscores';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter an email address';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 8 ||
        !RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Use at least 8 characters, including a letter and a number';
    }
    return null;
  }

  void _toggleMode() {
    final email = _email.text.trim();
    _formKey.currentState?.reset();
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
      _message = null;
      if (!_isSignUp && email.isNotEmpty) {
        _identifier.text = email;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
      _message = null;
    });
    try {
      if (_isSignUp) {
        await widget.onSignUp(
          _username.text.trim(),
          _email.text.trim(),
          _password.text,
        );
        if (!mounted) return;
        final email = _email.text.trim();
        _formKey.currentState?.reset();
        setState(() {
          _isSignUp = false;
          _identifier.text = email;
          _message = 'Account created. Sign in with your new account.';
        });
      } else {
        final account = await widget.onSignIn(
          _identifier.text.trim(),
          _password.text,
        );
        if (account == null) {
          setState(() => _error = 'Invalid email/username or password.');
        } else {
          _password.clear();
        }
      }
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not complete the request: $error');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
