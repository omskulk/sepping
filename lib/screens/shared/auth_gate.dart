import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../active/active_home.dart';
import '../auth/login_screen.dart';
import '../pnm/pnm_home.dart';

/// Single source of truth for "what do I render right now."
/// Listens to FirebaseAuth, then to the /users/{uid} doc, and routes accordingly.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: auth.authStateChanges,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _FullScreenLoader();
        }
        final user = authSnap.data;
        if (user == null) return const LoginScreen();
        return _RoleRouter(uid: user.uid);
      },
    );
  }
}

class _RoleRouter extends StatelessWidget {
  const _RoleRouter({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final users = context.read<UserService>();
    return StreamBuilder<AppUser?>(
      stream: users.watchUser(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _FullScreenLoader();
        }
        final appUser = snap.data;
        if (appUser == null) {
          // Auth succeeded but the /users doc isn't there yet. Usually a race on signup.
          return const _FullScreenLoader(hint: 'Preparing your account…');
        }
        return Provider<AppUser>.value(
          value: appUser,
          child: appUser.isActive ? const ActiveHome() : const PnmHome(),
        );
      },
    );
  }
}

class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader({this.hint});
  final String? hint;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SepColors.light,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: SepColors.navy),
            if (hint != null) ...[
              const SizedBox(height: 16),
              Text(hint!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
