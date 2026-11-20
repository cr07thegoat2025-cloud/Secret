import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/chats_screen.dart';

// The project URL and publishable (anon) key are meant to be public: they ship
// inside every client app. Access is protected by Row Level Security in the
// database. Override with --dart-define=SUPABASE_URL=... if you ever move.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://sgzbbbrhoskipnvclskl.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_KEY',
    defaultValue: 'sb_publishable_Mzlu_uSXfnGzaWYI2dp1og_ha7RJV1W');

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const TextChatApp());
}

class TextChatApp extends StatelessWidget {
  const TextChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF128C7E)),
        useMaterial3: true,
      ),
      home: StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, snap) {
          final session = snap.data?.session ?? db.auth.currentSession;
          return session != null ? const ChatsScreen() : const AuthScreen();
        },
      ),
    );
  }
}
