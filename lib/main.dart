// ============================================================
// lib/main.dart
// Arranque INSTANTÁNEO sin internet (no espera el refresh de token)
// + escucha el enlace de recuperación de contraseña (deep link)
// ============================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/nueva_password_screen.dart';

const Color kAmarillo = Color(0xFFFFD600);
const Color kNegro = Color(0xFF0A0A0A);
const Color kGris = Color(0xFF1A1A1A);

// Llave global para poder navegar desde fuera de un widget (al llegar el enlace)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  try {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    ).timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        return Supabase.instance;
      },
    );
  } catch (_) {
    try {
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL'] ?? '',
        anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      );
    } catch (_) {}
  }

  runApp(const BioSmartApp());
}

class BioSmartApp extends StatefulWidget {
  const BioSmartApp({super.key});

  @override
  State<BioSmartApp> createState() => _BioSmartAppState();
}

class _BioSmartAppState extends State<BioSmartApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _escucharRecuperacion();
  }

  // Escucha cuando el usuario llega por el ENLACE de recuperación del email.
  // Supabase dispara el evento passwordRecovery; ahí abrimos la pantalla para
  // poner la nueva contraseña.
  void _escucharRecuperacion() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        // Abrir la pantalla de nueva contraseña
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NuevaPasswordScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'BioSmart Hypertrophy',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kNegro,
        primaryColor: kAmarillo,
        colorScheme: const ColorScheme.dark(
          primary: kAmarillo,
          secondary: kAmarillo,
          surface: kGris,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAmarillo,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAmarillo),
      ),
      home: const AuthGate(),
    );
  }
}