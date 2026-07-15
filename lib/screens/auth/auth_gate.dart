// ============================================================
// lib/screens/auth_gate.dart
// - Login normal: entra instantáneo (rol en metadata)
// - Google nuevo (sin rol): manda a elegir rol
// - Revisa SIEMPRE si la cuenta está bloqueada por el admin
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import '../usuario/main_screen.dart';
import '../entrenador/entrenador_main_screen.dart';
import 'elegir_rol_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;

        // Sin sesión -> Login
        if (session == null) {
          return const AuthScreen();
        }

        // SIEMPRE consultamos la BD para (1) revisar si está bloqueado y
        // (2) confirmar el rol. Esto asegura que un usuario bloqueado NO entre,
        // aunque tenga el rol guardado en los metadatos.
        return FutureBuilder<_EstadoCuenta>(
          future: _revisarCuenta(supabase, session.user.id),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              // Mientras carga: si hay rol en metadatos, mostramos cargando
              // (rápido). No dejamos entrar todavía hasta confirmar bloqueo.
              return const _Cargando();
            }

            final estado = snap.data;

            // Si no pudimos leer la BD (sin internet, etc.):
            // dejamos entrar con el rol de los metadatos como respaldo,
            // PERO solo si existe (para no romper el uso offline).
            if (estado == null || estado.errorLectura) {
              final rolMeta = session.user.userMetadata?['rol'] as String?;
              if (rolMeta == 'entrenador') return const EntrenadorMainScreen();
              if (rolMeta == 'usuario') return const MainScreen();
              return const _Cargando();
            }

            // Cuenta bloqueada por el admin -> pantalla de bloqueo
            if (estado.bloqueada) return const _CuentaBloqueada();

            // Según el rol
            if (estado.rol == 'entrenador') return const EntrenadorMainScreen();
            if (estado.rol == 'usuario') return const MainScreen();

            // No tiene rol -> elegir rol (Google nuevo)
            return const ElegirRolScreen();
          },
        );
      },
    );
  }

  // Lee de la BD el rol y si está bloqueada. Devuelve un estado claro.
  Future<_EstadoCuenta> _revisarCuenta(SupabaseClient sb, String userId) async {
    try {
      final data = await sb
          .from('perfiles')
          .select('rol, cuenta_bloqueada')
          .eq('id', userId)
          .maybeSingle();

      final bloqueada = data?['cuenta_bloqueada'] == true;
      if (bloqueada) {
        // Cerrar sesión para que no quede logueado
        await sb.auth.signOut();
        return _EstadoCuenta(bloqueada: true, rol: null, errorLectura: false);
      }
      return _EstadoCuenta(
        bloqueada: false,
        rol: data?['rol'] as String?,
        errorLectura: false,
      );
    } catch (_) {
      // No se pudo leer (sin internet). Marcamos error para usar respaldo.
      return _EstadoCuenta(bloqueada: false, rol: null, errorLectura: true);
    }
  }
}

// Estado de la cuenta tras revisar la BD
class _EstadoCuenta {
  final bool bloqueada;
  final String? rol;
  final bool errorLectura; // true si no se pudo leer la BD
  _EstadoCuenta({required this.bloqueada, required this.rol, required this.errorLectura});
}

class _Cargando extends StatelessWidget {
  const _Cargando();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD600))),
      );
}

class _CuentaBloqueada extends StatelessWidget {
  const _CuentaBloqueada();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, color: Colors.redAccent, size: 64),
              const SizedBox(height: 20),
              const Text('Cuenta bloqueada',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                'Tu cuenta ha sido bloqueada por el administrador. '
                'Si crees que es un error, contacta con soporte.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD600),
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthGate()),
                    (route) => false,
                  );
                },
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}