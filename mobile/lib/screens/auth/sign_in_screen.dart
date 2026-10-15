import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../design/bold.dart';

/// Sign in, sign up, and the guest door — one screen, two modes.
///
/// Splitting these across two screens makes people who picked wrong navigate
/// back and retype; the fields are nearly identical, so the form flips
/// instead. PRD §5.1 lists email auth as P0.
class SignInScreen extends StatefulWidget {
  const SignInScreen(
      {super.key, required this.onSignedIn, this.startOnSignUp = false});

  final VoidCallback onSignedIn;
  final bool startOnSignUp;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const _auth = Auth();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _signUp = widget.startOnSignUp;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_signUp) {
        await _auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
        );
      } else {
        await _auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      if (_signUp && !_auth.isSignedIn) {
        setState(() {
          _notice =
              'Check your email to confirm your account, then sign in here.';
          _signUp = false;
          _password.clear();
        });
      } else {
        widget.onSignedIn();
      }
    } catch (e) {
      if (mounted) setState(() => _error = Auth.readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.continueAsGuest();
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted) setState(() => _error = Auth.readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above first, then tap this.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset link sent to $email.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = Auth.readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                children: [
                  const _Wordmark(),
                  const SizedBox(height: 32),
                  Text(_signUp ? 'Create your account' : 'Welcome back',
                      style: T.display.copyWith(color: Bold.ink)),
                  const SizedBox(height: 6),
                  Text(
                    _signUp
                        ? 'Your notes, questions and progress stay tied to this account.'
                        : 'Sign in to pick up where your revision left off.',
                    style: T.body.copyWith(color: Bold.slate),
                  ),
                  const SizedBox(height: 28),
                  if (_notice != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(_notice!,
                          style: T.body.copyWith(color: Bold.ink)),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_signUp) ...[
                    _Field(
                      controller: _name,
                      label: 'Name',
                      hint: 'Your name',
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Tell us your name.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _Field(
                    controller: _email,
                    label: 'Email',
                    hint: 'you@college.edu',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Enter your email.';
                      if (!t.contains('@') || !t.contains('.')) {
                        return 'That does not look like an email.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    controller: _password,
                    label: 'Password',
                    hint: _signUp ? 'At least 8 characters' : '',
                    obscure: _obscure,
                    onToggleObscure: () => setState(() => _obscure = !_obscure),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Enter your password.';
                      // Only enforced on sign-up: an existing account may
                      // predate the rule, and rejecting its owner at the door
                      // would be absurd.
                      if (_signUp && v!.length < 8) {
                        return 'Use at least 8 characters.';
                      }
                      return null;
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  if (!_signUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: Text('Forgot password?',
                            style: T.small.copyWith(color: Bold.brand)),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Bold.wash(Bold.danger),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 18, color: Bold.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: T.small
                                    .copyWith(color: Bold.danger, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_signUp ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _signUp = !_signUp;
                                _error = null;
                              }),
                      child: Text.rich(
                        TextSpan(
                          style: T.body.copyWith(color: Bold.slate),
                          children: [
                            TextSpan(
                                text: _signUp
                                    ? 'Already have an account? '
                                    : 'New here? '),
                            TextSpan(
                              text: _signUp ? 'Sign in' : 'Create one',
                              style: const TextStyle(
                                  color: Bold.brand,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Bold.line)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or',
                            style: T.small.copyWith(color: Bold.slate)),
                      ),
                      Expanded(child: Divider(color: Bold.line)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy ? null : _guest,
                    child: const Text('Try it without an account'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    // Said before they choose it, not after they lose work.
                    'A guest account lives on this device only. You can turn '
                    'it into a real account later without losing anything.',
                    textAlign: TextAlign.center,
                    style: T.small.copyWith(color: Bold.slate, height: 1.45),
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

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ViaXMark(size: 40, radius: 11),
        const SizedBox(width: 12),
        Text('ViaX', style: T.title.copyWith(color: Bold.ink)),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.validator,
    this.hint = '',
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.onToggleObscure,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.small.copyWith(color: Bold.slate)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          obscureText: obscure,
          autocorrect: !obscure,
          onFieldSubmitted: onSubmitted,
          style: T.body.copyWith(color: Bold.ink),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint.isEmpty ? null : hint,
            hintStyle: T.body.copyWith(color: Bold.slate),
            filled: true,
            fillColor: Bold.card,
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: Bold.slate,
                    ),
                    onPressed: onToggleObscure,
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Bold.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Bold.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Bold.brand, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          ),
        ),
      ],
    );
  }
}
