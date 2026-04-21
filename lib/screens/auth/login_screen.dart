import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signIn(
            email: _email.text,
            password: _password.text,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SepColors.light,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('SEPing',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(letterSpacing: 1.5)),
                      const SizedBox(height: 4),
                      Text(
                        'Drop pins. Assign tasks. Prove it.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: SepColors.blueGray),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        // Pressing Enter in the email field should jump to
                        // the password field, not submit (the password is
                        // still empty at this point).
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        // Enter on the password field == clicking SIGN IN.
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                        validator: (v) =>
                            (v == null || v.length < 6) ? 'At least 6 characters' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: SepColors.danger)),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: SepColors.light))
                            : const Text('SIGN IN'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => const SignupScreen()),
                                ),
                        child: const Text('No account? Sign up'),
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
}
