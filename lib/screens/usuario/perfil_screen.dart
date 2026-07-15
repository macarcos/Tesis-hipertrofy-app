// ============================================================
// lib/screens/usuario/perfil_screen.dart
// Perfil del usuario con botón al historial completo
// Recarga datos/badge automáticamente al volver de otras pantallas.
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/entrenador_service.dart';
import '../../services/app_config.dart';
import '../auth/auth_gate.dart';
import 'historial_screen.dart';
import 'mi_entrenador_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _supabase = Supabase.instance.client;
  final _entrenadorService = EntrenadorService();

  String _nombre = '...';
  String _apellido = '';
  String _email = '';
  int _mensajesNoLeidos = 0;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
    _cargarNoLeidos();
  }

  Future<void> _cargarNoLeidos() async {
    final n = await _entrenadorService.misMensajesNoLeidos();
    if (mounted) setState(() => _mensajesNoLeidos = n);
  }

  Future<void> _cargarPerfil() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase
          .from('perfiles')
          .select('nombre, apellido, correo')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _nombre = data?['nombre'] ?? 'Usuario';
          _apellido = data?['apellido'] ?? '';
          _email = data?['correo'] ?? user.email ?? '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _nombre = user.userMetadata?['first_name'] ?? 'Usuario';
          _email = user.email ?? '';
        });
      }
    }
  }

  Future<void> _signOut() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
        content: const Text('¿Seguro que quieres cerrar sesión?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  Future<void> _eliminarCuenta() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Eliminar cuenta', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Seguro que quieres eliminar tu cuenta? Se borrarán TODOS tus datos '
          '(sesiones, videos, mensajes) y no se puede deshacer.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar todo', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _supabase.rpc('eliminar_mi_cuenta');
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e'),
              backgroundColor: Colors.red[700]));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iniciales = (_nombre.isNotEmpty ? _nombre[0] : '') +
        (_apellido.isNotEmpty ? _apellido[0] : '');

    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Perfil', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            CircleAvatar(
              radius: 44,
              backgroundColor: _amarillo,
              child: Text(
                iniciales.toUpperCase(),
                style: const TextStyle(
                    color: Colors.black, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text('$_nombre $_apellido',
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_email, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 30),

            // ── AJUSTES ──────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('AJUSTES',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 12, letterSpacing: 1.5,
                        fontWeight: FontWeight.bold)),
              ),
            ),

            // Interruptor: Grabar video de la sesión
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _gris,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _amarillo.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.videocam, color: _amarillo),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Grabar video',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Graba la pantalla durante el ejercicio',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: AppConfig.grabarVideo,
                    activeColor: _amarillo,
                    activeTrackColor: _amarillo.withOpacity(0.4),
                    inactiveThumbColor: Colors.white54,
                    onChanged: (v) => setState(() => AppConfig.grabarVideo = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Opción: Historial
            _opcion(
              icono: Icons.history,
              titulo: 'Historial completo',
              subtitulo: 'Mira todas tus sesiones de entrenamiento',
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HistorialScreen()));
                _cargarNoLeidos();
              },
            ),

            const SizedBox(height: 12),

            // Opción: Mi Entrenador
            _opcion(
              icono: Icons.fitness_center,
              titulo: 'Mi Entrenador',
              subtitulo: 'Conéctate y comunícate con tu entrenador',
              badge: _mensajesNoLeidos,
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MiEntrenadorScreen()));
                // Al volver, refrescar el contador (pudo leer mensajes)
                _cargarNoLeidos();
              },
            ),

            const SizedBox(height: 12),

            // Opción: Cerrar sesión
            _opcion(
              icono: Icons.logout,
              titulo: 'Cerrar sesión',
              subtitulo: 'Salir de tu cuenta',
              colorIcono: Colors.redAccent,
              onTap: _signOut,
            ),

            const SizedBox(height: 12),

            // Opción: Eliminar cuenta
            _opcion(
              icono: Icons.delete_forever,
              titulo: 'Eliminar cuenta',
              subtitulo: 'Borra tu cuenta y todos tus datos',
              colorIcono: Colors.redAccent,
              onTap: _eliminarCuenta,
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcion({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    Color colorIcono = _amarillo,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _gris,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorIcono.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icono, color: colorIcono),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitulo,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (badge > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _amarillo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}