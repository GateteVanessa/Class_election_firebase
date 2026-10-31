import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'logic/election_logic.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();

  bool creating = false; // false = log in, true = create account
  bool busy = false;
  String? error;
  String? info; // a green message, like "Account created"

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    // Checks every field first. Nothing is sent if one is wrong.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (creating) {
        final cred = await auth.createUserWithEmailAndPassword(
            email: email.text.trim(), password: password.text);

        // Keep the name on the account itself.
        final fullName =
            '${cleanName(firstName.text)} ${cleanName(lastName.text)}';
        await cred.user?.updateDisplayName(fullName);

        // New account: write the three sample candidates, once.
        try {
          await addSampleCandidates();
        } on FirebaseException catch (e) {
          if (mounted) setState(() => error = 'Account created, but ${e.code}');
        }

        // Log out, so the person logs in with the same details.
        await auth.signOut();
        if (mounted) {
          setState(() {
            creating = false;
            password.clear();
            confirm.clear();
            info = 'Account created. Now log in.';
          });
        }
      } else {
        await auth.signInWithEmailAndPassword(
            email: email.text.trim(), password: password.text);
      }
      // No navigation here: AuthGate sees the login and changes the screen.
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = _message(e.code));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _message(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email is not valid';
      case 'weak-password':
        return 'Password needs at least 6 characters';
      case 'email-already-in-use':
        return 'This email already has an account. Log in instead.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return 'Something went wrong ($code)';
    }
  }

  String? _required(String? v, String what) {
    if ((v ?? '').trim().isEmpty) return 'Enter your $what';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.how_to_vote,
                      size: 64, color: Color(0xFF3F3D9E)),
                  const SizedBox(height: 8),
                  Text('Ijwi',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),

                  // Only when creating an account
                  if (creating) ...[
                    TextFormField(
                      controller: firstName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'First name',
                          border: OutlineInputBorder()),
                      validator: (v) => _required(v, 'first name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: lastName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Second name',
                          border: OutlineInputBorder()),
                      validator: (v) => _required(v, 'second name'),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email', border: OutlineInputBorder()),
                    validator: (v) {
                      final e = (v ?? '').trim();
                      if (e.isEmpty) return 'Enter your email';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
                        return 'Enter a valid email, like aline@gmail.com';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password', border: OutlineInputBorder()),
                    validator: (v) =>
                    (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  ),

                  // Only when creating an account
                  if (creating) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder()),
                      validator: (v) =>
                      v != password.text ? 'Passwords do not match' : null,
                    ),
                  ],

                  if (info != null) ...[
                    const SizedBox(height: 12),
                    Text(info!, style: const TextStyle(color: Colors.green)),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(creating ? 'Create account' : 'Log in'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                      creating = !creating;
                      error = null;
                      info = null;
                      _formKey.currentState?.reset();
                    }),
                    child: Text(creating
                        ? 'I already have an account'
                        : 'Create a new account'),
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