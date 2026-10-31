import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'election_home.dart';
import 'login_screen.dart';

/// Decides what to show: the login screen, or the app.
/// It listens to Firebase, so login and logout switch the screen by themselves.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        // The key makes a NEW Election for every different account.
        return ElectionHome(key: ValueKey(user.uid), user: user);
      },
    );
  }
}