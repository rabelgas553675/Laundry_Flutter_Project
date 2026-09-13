import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
// `hide AuthState`: supabase_flutter re-exports GoTrue's own `AuthState`
// class (an auth-event type, unrelated to ours). Now that this file also
// imports our core/services/auth_state.dart, both names collide —
// `ambiguous_import` — since main.dart never uses Supabase's AuthState,
// hiding it here is the correct fix rather than prefixing every
// supabase_flutter symbol we DO use (Supabase.initialize, etc.).
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'app/app.dart';
import 'core/services/auth_state.dart';
import 'firebase_options.dart';

// Supabase project credentials (Storage only — Auth/Firestore/etc. all
// stay on Firebase). The anon key is safe to embed client-side; it has
// no elevated access on its own, RLS/bucket policies gate what it can
// actually do. Replace both with your own project's values from
// Supabase Dashboard → Project Settings → API.
const _supabaseUrl = 'https://eeviglsvyolbkzpwyebx.supabase.co';
const _supabaseAnonKey = 'sb_publishable_R4hjIdd605JdmA7HtFFW_g_WxqzF98a';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError? initError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ROOT-CAUSE FIX for the User Dashboard's intermittent "stuck on
    // loading" bug: subscribe to Firebase Auth's authStateChanges()
    // (via AuthState.warmUp()) immediately here — before the
    // Supabase.initialize() await below gets any chance to run and
    // widen the race window — so the very first auth-restoration
    // event can never be missed. See AuthState.warmUp()'s doc comment
    // for the full explanation. This one line must stay exactly here:
    // after Firebase.initializeApp(), before every other await in
    // this function, and before runApp().
    AuthState.warmUp();

    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
  } catch (e, stack) {
    // Don't crash the whole app on a Firebase init failure — show a
    // clear error screen instead so it's obvious what went wrong
    // (most commonly: firebase_options.dart still has placeholder
    // values, or google-services.json / GoogleService-Info.plist
    // is missing from the native project). The stack trace is still
    // reported (not swallowed) so it shows up in debug/crash logs.
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack));
    initError = FlutterError(e.toString());
  }

  runApp(initError == null ? const LaundryApp() : _FirebaseInitErrorApp(error: initError));
}

class _FirebaseInitErrorApp extends StatelessWidget {
  const _FirebaseInitErrorApp({required this.error});

  final FlutterError error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Firebase failed to initialize',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Check that firebase_options.dart has real values '
                  '(run `flutterfire configure`) and that '
                  'google-services.json / GoogleService-Info.plist '
                  'are in place.\n\n${error.message}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}