import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';
import '../ui/overlays.dart';

enum _AuthMode { signIn, signUp }

/// Sign in / create account. Accounts are stored only on this device: there
/// is no server, so the password is validated for format but not stored.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _showPassword = false;
  bool _busy = false;

  bool get _isSignUp => _mode == _AuthMode.signUp;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (!_isSignUp) return null;
    if ((value ?? '').trim().isEmpty) return 'Enter your name';
    return null;
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your email';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    return ok ? null : 'Enter a valid email address';
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Enter your password';
    if (text.length < 6) return 'Use at least 6 characters';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final store = AppScope.read(context);
    setState(() => _busy = true);
    try {
      if (_isSignUp) {
        await store.signUp(name: _name.text, email: _email.text);
      } else {
        await store.signIn(email: _email.text);
      }
    } finally {
      // The screen is replaced once the profile is signed in, so it may be
      // gone by now.
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() {
    setState(() {
      _mode = _isSignUp ? _AuthMode.signIn : _AuthMode.signUp;
    });
  }

  Future<void> _forgotPassword() async {
    await showNovaDialog<void>(
      context,
      builder: (ctx) => NovaDialogCard(
        icon: Icons.lock_reset_rounded,
        title: 'Password reset',
        message: 'Nova keeps your account only on this device, so there is '
            'no password to recover. Sign in with the same email, or create '
            'a new account.',
        actions: [
          NeuButton(
            label: 'Got it',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Nova',
      header: false,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.xxxl,
          NovaLayout.pagePad,
          NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: NovaSpace.xxxl),
                FadeIn(
                  child: GlassSurface(
                    radius: NovaRadius.xl,
                    padding: const EdgeInsets.all(NovaSpace.xxl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedSwitcher(
                            duration: motionDuration(context, NovaDurations.base),
                            child: Column(
                              key: ValueKey<_AuthMode>(_mode),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isSignUp ? 'Create account' : 'Welcome back',
                                  style: NovaType.title.copyWith(fontSize: 22),
                                ),
                                const SizedBox(height: NovaSpace.xs),
                                Text(
                                  _isSignUp
                                      ? 'Set up your workspace in a few seconds.'
                                      : 'Sign in to pick up where you left off.',
                                  style: NovaType.bodyDim,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: NovaSpace.xxl),
                          // A new key per mode rebuilds the fields so errors
                          // from the other mode do not linger.
                          KeyedSubtree(
                            key: ValueKey<String>('fields-${_mode.name}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_isSignUp) ...[
                                  NeuField(
                                    controller: _name,
                                    label: 'Name',
                                    hint: 'Your name',
                                    icon: Icons.person_outline_rounded,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization: TextCapitalization.words,
                                    autofillHints: const [AutofillHints.name],
                                    validator: _validateName,
                                  ),
                                  const SizedBox(height: NovaSpace.lg),
                                ],
                                NeuField(
                                  controller: _email,
                                  label: 'Email',
                                  hint: 'you@example.com',
                                  icon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  validator: _validateEmail,
                                ),
                                const SizedBox(height: NovaSpace.lg),
                                NeuField(
                                  controller: _password,
                                  label: 'Password',
                                  hint: 'At least 6 characters',
                                  icon: Icons.lock_outline_rounded,
                                  obscureText: !_showPassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  validator: _validatePassword,
                                  onSubmitted: (_) => _submit(),
                                  suffix: Pressable(
                                    semanticLabel:
                                        _showPassword ? 'Hide password' : 'Show password',
                                    onTap: () =>
                                        setState(() => _showPassword = !_showPassword),
                                    child: SizedBox(
                                      width: NovaLayout.minTap,
                                      height: NovaLayout.minTap,
                                      child: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                        color: NovaColors.textDim,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_isSignUp)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Pressable(
                                semanticLabel: 'Forgot password',
                                onTap: _forgotPassword,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Forgot password?',
                                    style: NovaType.label
                                        .copyWith(color: NovaColors.accent2),
                                  ),
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: NovaSpace.sm),
                          const SizedBox(height: NovaSpace.sm),
                          NeuButton(
                            label: _isSignUp ? 'Create account' : 'Sign in',
                            icon: _isSignUp
                                ? Icons.arrow_forward_rounded
                                : Icons.login_rounded,
                            loading: _busy,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: NovaSpace.xl),
                Center(
                  child: Pressable(
                    semanticLabel: _isSignUp
                        ? 'Switch to sign in'
                        : 'Switch to create account',
                    onTap: _switchMode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text.rich(
                        TextSpan(
                          style: NovaType.bodyDim,
                          children: [
                            TextSpan(
                              text: _isSignUp
                                  ? 'Already have an account? '
                                  : 'New to Nova? ',
                            ),
                            TextSpan(
                              text: _isSignUp ? 'Sign in' : 'Create an account',
                              style: NovaType.bodyStrong
                                  .copyWith(color: NovaColors.accent2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: NovaSpace.sm),
                Text(
                  'Your data stays on this device.',
                  textAlign: TextAlign.center,
                  style: NovaType.caption.copyWith(color: NovaColors.textFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NeuRaised(
          radius: NovaRadius.xl,
          child: SizedBox(
            width: 84,
            height: 84,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [NovaColors.accent2, NovaColors.accent],
              ).createShader(rect),
              child: const Icon(Icons.bolt_rounded, size: 44, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: NovaSpace.lg),
        Text('Nova', style: NovaType.title.copyWith(fontSize: 28)),
        const SizedBox(height: NovaSpace.xs),
        Text('Tasks and focus, in one calm place.', style: NovaType.bodyDim),
      ],
    );
  }
}
