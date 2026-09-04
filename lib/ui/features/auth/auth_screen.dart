import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool otpMode = false;
  bool createAccount = false;
  bool codeSent = false;
  bool isSubmitting = false;
  String? errorMessage;
  final email = TextEditingController();
  final displayName = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final otpCode = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    displayName.dispose();
    password.dispose();
    confirmPassword.dispose();
    otpCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to ChargeMY')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 68,
                color: Color(0xFF007F62),
              ),
              const SizedBox(height: 18),
              Text(
                'Find, navigate, and charge with confidence.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Email password')),
                  ButtonSegment(value: true, label: Text('Email OTP')),
                ],
                selected: {otpMode},
                onSelectionChanged:
                    (selection) => setState(() {
                      otpMode = selection.first;
                      codeSent = false;
                      otpCode.clear();
                      errorMessage = null;
                    }),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              if (createAccount && !otpMode) ...[
                TextField(
                  controller: displayName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (otpMode)
                if (codeSent)
                  TextField(
                    controller: otpCode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      hintText: '123456',
                      border: OutlineInputBorder(),
                    ),
                  )
                else
                  const _OtpInfoCard()
              else if (!otpMode)
                Column(
                  children: [
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (createAccount) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: confirmPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 20),
              if (errorMessage != null) ...[
                Text(
                  errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: isSubmitting ? null : _submit,
                child: Text(
                  isSubmitting
                      ? 'Please wait...'
                      : otpMode
                      ? codeSent
                          ? 'Verify code'
                          : 'Send 6-digit code'
                      : createAccount
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
              const SizedBox(height: 12),
              if (!otpMode)
                TextButton(
                  onPressed:
                      isSubmitting
                          ? null
                          : () => setState(() {
                            createAccount = !createAccount;
                            errorMessage = null;
                          }),
                  child: Text(
                    createAccount
                        ? 'Already have an account? Sign in'
                        : 'New to ChargeMY? Create an account',
                  ),
                ),
              if (otpMode && codeSent)
                TextButton(
                  onPressed:
                      isSubmitting
                          ? null
                          : () => setState(() {
                            codeSent = false;
                            otpCode.clear();
                            errorMessage = null;
                          }),
                  child: const Text('Use a different email'),
                ),
              const SizedBox(height: 14),
              Text(
                'Use an email and a password of at least 6 characters, or receive a passwordless 6-digit code through Supabase.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final emailValue = email.text.trim();
    final passwordValue = password.text;
    final confirmValue = confirmPassword.text;
    if (emailValue.isEmpty ||
        (!otpMode && passwordValue.isEmpty) ||
        (createAccount && !otpMode && displayName.text.trim().isEmpty) ||
        (createAccount && !otpMode && passwordValue != confirmValue) ||
        (otpMode && codeSent && otpCode.text.trim().length != 6)) {
      setState(
        () =>
            errorMessage =
                otpMode
                    ? codeSent
                        ? 'Enter the 6-digit code from your email.'
                        : 'Enter your email address.'
                    : createAccount && displayName.text.trim().isEmpty
                    ? 'Enter a display name.'
                    : createAccount && passwordValue != confirmValue
                    ? 'Passwords do not match.'
                    : 'Enter both your email address and password.',
      );
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });
    try {
      final session = ref.read(sessionProvider);
      if (otpMode) {
        if (codeSent) {
          await session.verifyEmailOtp(emailValue, otpCode.text);
        } else {
          await session.sendEmailOtp(emailValue);
        }
        if (mounted) {
          if (!codeSent) {
            setState(() => codeSent = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'A 6-digit code was sent. Enter it here to sign in.',
                ),
              ),
            );
            return;
          }
        }
      } else if (createAccount) {
        await session.registerWithEmail(
          emailValue,
          passwordValue,
          displayName: displayName.text,
        );
      } else {
        await session.signInWithEmail(emailValue, passwordValue);
      }
      if (mounted) {
        context.go(session.isAdmin ? '/admin' : '/home');
      }
    } catch (error) {
      if (mounted) {
        setState(() => errorMessage = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  String _friendlyError(Object error) => friendlyErrorMessage(
    error,
    fallback: 'Could not continue. Please try again.',
  );
}

class _OtpInfoCard extends StatelessWidget {
  const _OtpInfoCard();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Padding(
      padding: EdgeInsets.all(14),
      child: Text('Insert the 6-digit code sent to your email.'),
    ),
  );
}
