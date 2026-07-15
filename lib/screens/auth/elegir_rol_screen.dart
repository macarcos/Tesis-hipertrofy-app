// ============================================================
// lib/screens/elegir_rol_screen.dart
// Sale UNA vez cuando entras con Google y aún no tienes rol.
// Elige usuario o entrenador.
// Si el usuario ya no existe en auth.users (cuenta borrada), cierra
// sesión y regresa al login en vez de quedar atascado.
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class ElegirRolScreen extends StatefulWidget {
  const ElegirRolScreen({super.key});

  @override
  State<ElegirRolScreen> createState() => _ElegirRolScreenState();
}

class _ElegirRolScreenState extends State<ElegirRolScreen> {
  final _sb = Supabase.instance.client;
  bool _guardando = false;

  Future<void> _elegir(String rol) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      _volverAlLogin();
      return;
    }

    setState(() => _guardando = true);
    try {
      // Generar código si es entrenador
      String? codigo;
      if (rol == 'entrenador') {
        final res = await _sb.rpc('generar_codigo_entrenador');
        codigo = res as String?;
      }

      // Crear o actualizar el perfil con el rol elegido
      await _sb.from('perfiles').upsert({
        'id': user.id,
        'nombre': user.userMetadata?['full_name']?.toString().split(' ').first ??
            user.userMetadata?['name']?.toString().split(' ').first ?? 'Usuario',
        'apellido': user.userMetadata?['full_name']?.toString().split(' ').skip(1).join(' ') ?? '',
        'correo': user.email,
        'rol': rol,
        'codigo_entrenador': codigo,
      });

      // Guardar el rol también en los metadatos (para el arranque rápido)
      await _sb.auth.updateUser(UserAttributes(data: {'rol': rol}));

      // El AuthGate detectará el rol y entrará a la pantalla correcta.
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      // Si el error es de clave foránea (el usuario ya no existe en auth.users
      // porque su cuenta fue eliminada), cerramos sesión y volvemos al login.
      final msg = e.toString().toLowerCase();
      final usuarioBorrado = msg.contains('foreign key') ||
          msg.contains('not present in table') ||
          msg.contains('users');

      if (usuarioBorrado) {
        await _cerrarSesionYVolver(
          'Tu cuenta ya no existe. Inicia sesión de nuevo o crea una cuenta.',
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]));
        setState(() => _guardando = false);
      }
    }
  }

  // Cierra la sesión (limpia el login de Google guardado) y va al login.
  Future<void> _cerrarSesionYVolver(String mensaje) async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.orange[800]));
    _volverAlLogin();
  }

  void _volverAlLogin() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('¿Cómo vas a usar BioSmart?',
                  style: TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Elige tu tipo de cuenta. Esto no se puede cambiar después.',
                  style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              const SizedBox(height: 40),

              if (_guardando)
                const CircularProgressIndicator(color: _amarillo)
              else ...[
                _tarjetaRol(
                  emoji: '💪',
                  titulo: 'Usuario',
                  desc: 'Entreno y analizo mi técnica con la IA',
                  onTap: () => _elegir('usuario'),
                ),
                const SizedBox(height: 16),
                _tarjetaRol(
                  emoji: '🏋️',
                  titulo: 'Entrenador',
                  desc: 'Superviso a mis usuarios y reviso su progreso',
                  onTap: () => _elegir('entrenador'),
                ),

                const SizedBox(height: 24),
                // Botón para salir por si la cuenta quedó en un estado raro
                TextButton(
                  onPressed: () => _cerrarSesionYVolver('Sesión cerrada'),
                  child: const Text('Cerrar sesión',
                      style: TextStyle(color: Colors.white38)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRol({
    required String emoji,
    required String titulo,
    required String desc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _gris,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _amarillo.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          color: _amarillo, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _amarillo),
          ],
        ),
      ),
    );
  }
}