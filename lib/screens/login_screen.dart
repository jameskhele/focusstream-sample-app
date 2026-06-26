import 'dart:math';
import 'package:flutter/material.dart';
import '../state/session.dart';
import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true; // password watch state
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
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
      backgroundColor: const Color(0xFF070913),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;

          if (isWide) {
            return Row(
              children: [
                // Left Panel: Grand Cyber/SaaS Branding Banner
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0C0E20), Color(0xFF05060A)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Custom Painter Animated Cyber Matrix Grid
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: LoginBannerPainter(time: _animationController.value),
                              child: Container(),
                            );
                          },
                        ),
                        // Overlay Content
                        Padding(
                          padding: const EdgeInsets.all(48.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F5FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF00F5FF).withOpacity(0.4)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield_outlined, color: Color(0xFF00F5FF), size: 14),
                                    SizedBox(width: 6),
                                    Text(
                                      'SECURE END-TO-END GATEWAY',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF00F5FF),
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'FocusStream Workspace',
                                style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                  shadows: [
                                    Shadow(color: Color(0xFF00F5FF), blurRadius: 15),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Powered by DartStream Client SDK. Monitor feature flags, database persistent telemetry, and synchronizing workspace sessions on the fly.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF94A3B8),
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Right Panel: Form
                Container(
                  width: 440,
                  color: const Color(0xFF090B15),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(40),
                      child: _buildForm(context, loading, session),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Mobile Centered Layout
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    color: const Color(0xFF090B15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _buildForm(context, loading, session),
                    ),
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, bool loading, Session session) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Brand Logo
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.blur_on,
              color: Color(0xFF00F5FF),
              size: 40,
            ),
            const SizedBox(width: 12),
            Text(
              'FocusStream',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'DARTSTREAM LIVE WORKSPACE PORTAL',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF94A3B8),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 36),

        // Email field
        TextField(
          controller: _emailController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Email address',
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.email, size: 18, color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF0F1122),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E293B)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00F5FF)),
            ),
          ),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 18),

        // Password field with Password Watch (Visibility toggle)
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.lock, size: 18, color: Colors.grey),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            filled: true,
            fillColor: const Color(0xFF0F1122),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E293B)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00F5FF)),
            ),
          ),
          autofillHints: const [AutofillHints.password],
        ),
        const SizedBox(height: 28),

        // Actions
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(color: Color(0xFF00F5FF)),
            ),
          )
        else
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            child: Text(
              _isSignUp ? 'CREATE ACCOUNT & WORKSPACE' : 'SIGN IN TO WORKSPACE',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
            ),
          ),

        const SizedBox(height: 20),

        // Auth Switcher text button
        TextButton(
          onPressed: () {
            setState(() {
              _isSignUp = !_isSignUp;
            });
          },
          child: Text(
            _isSignUp
                ? 'Already have a secure workspace? Sign In'
                : 'Need a new secure workspace? Sign Up',
            style: const TextStyle(color: Color(0xFF00F5FF), fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),

        // Error Alerts
        if (session.status == SessionStatus.error && session.errorMessage != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2C0F12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEF4444)),
            ),
            child: Text(
              session.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFCA5A5),
                fontSize: 12.5,
              ),
            ),
          ),
        ],

        // API Key missing warning fallback
        if (!AppConfig.hasFirebaseApiKey) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2E2209),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD97706)),
            ),
            child: const Text(
              'Warning: No FIREBASE_API_KEY detected in env. Using standard fallback credentials.',
              style: TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 11.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

// Background painter for the grand login panel
class LoginBannerPainter extends CustomPainter {
  final double time;
  LoginBannerPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw glowing grid
    final gridPaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.04)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // 2. Draw moving sine wave data lines
    final wavePaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.12)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (double x = 0; x < size.width; x++) {
      final y = size.height * 0.5 + sin((x / 50.0) + (time * 2.0 * pi)) * 40.0;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, wavePaint);

    final wave2Paint = Paint()
      ..color = const Color(0xFFEC4899).withOpacity(0.08)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path2 = Path();
    for (double x = 0; x < size.width; x++) {
      final y = size.height * 0.4 + cos((x / 60.0) + (time * 2.0 * pi)) * 30.0;
      if (x == 0) {
        path2.moveTo(x, y);
      } else {
        path2.lineTo(x, y);
      }
    }
    canvas.drawPath(path2, wave2Paint);

    // 3. Draw scanning light bars
    final scannerY = (time * size.height) % size.height;
    final scannerPaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.08)
      ..strokeWidth = 3.0;
    canvas.drawLine(Offset(0, scannerY), Offset(size.width, scannerY), scannerPaint);
  }

  @override
  bool shouldRepaint(covariant LoginBannerPainter oldDelegate) => oldDelegate.time != time;
}
