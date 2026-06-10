import 'package:flutter/material.dart';
import '../state/session.dart';
import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    // Default smoke/test user for convenient onboarding
    _emailController.text = 'smoketest@dartstream.test';
    _passwordController.text = 'smoke123';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    if (_isSignUp) {
      widget.session.signUp(email, password);
    } else {
      widget.session.signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final loading = session.status == SessionStatus.signingIn;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: const Color(0xFF151824),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Logo
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.blur_on,
                          color: Color(0xFF6366F1),
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'FocusStream',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'DartStream SaaS SaaS Dashboard',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                    const SizedBox(height: 32),

                    // Inputs
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        hintText: 'Email address',
                        prefixIcon: Icon(Icons.email, size: 20, color: Colors.grey),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        hintText: 'Password',
                        prefixIcon: Icon(Icons.lock, size: 20, color: Colors.grey),
                      ),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    if (loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      FilledButton(
                        onPressed: _submit,
                        child: Text(_isSignUp ? 'Create Workspace' : 'Sign In to Workspace'),
                      ),

                    const SizedBox(height: 16),

                    // Auth Switcher
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSignUp = !_isSignUp;
                        });
                      },
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign In'
                            : 'Need a new workspace? Sign Up',
                        style: const TextStyle(color: Color(0xFF6366F1)),
                      ),
                    ),

                    // Error Box
                    if (session.status == SessionStatus.error && session.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B1519),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5484D)),
                        ),
                        child: Text(
                          session.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFF8B8F),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],

                    // API Key Status Warning
                    if (!AppConfig.hasFirebaseApiKey) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3D2A00),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Warning: No FIREBASE_API_KEY detected in Environment. '
                          'Auth calls will use standard fallback credentials.',
                          style: TextStyle(
                            color: Color(0xFFFFC857),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
