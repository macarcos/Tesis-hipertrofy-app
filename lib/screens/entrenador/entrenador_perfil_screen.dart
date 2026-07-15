// ============================================================
// lib/screens/entrenador/entrenador_perfil_screen.dart
// Perfil del ENTRENADOR (consistente con el del usuario)
// Incluye acceso a "Usuarios bloqueados".
// State PÚBLICO + recargar() para refrescar el conteo al volver.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/entrenador_service.dart';
import '../auth/auth_gate.dart';
import 'entrenador_bloqueados_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class EntrenadorPerfilScreen extends StatefulWidget {
  const EntrenadorPerfilScreen({super.key});

  // State PÚBLICO para que el contenedor pueda llamar recargar()
  @override
  EntrenadorPerfilScreenState createState() => EntrenadorPerfilScreenState();
}

class EntrenadorPerfilScreenState extends State<EntrenadorPerfilScreen> {
  final _supabase = Supabase.instance.client;
  final _servicio = EntrenadorService();

  String _nombre = '...';
  String _apellido = '';
  String _email = '';
  String? _codigo;
  int _totalUsuarios = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // Método público: lo llama el contenedor al volver a esta pestaña
  void recargar() => _cargar();

  Future<void> _cargar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase
          .from('perfiles')
          .select('nombre, apellido, correo')
          .eq('id', user.id)
          .maybeSingle();
      final codigo = await _servicio.miCodigo();
      final usuarios = await _servicio.misUsuarios();
      if (mounted) {
        setState(() {
          _nombre = data?['nombre'] ?? 'Entrenador';
          _apellido = data?['apellido'] ?? '';
          _email = data?['correo'] ?? user.email ?? '';
          _codigo = codigo;
          _totalUsuarios = usuarios.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _signOut() async {
    final ok = await _confirmar('Cerrar sesión', '¿Seguro que quieres cerrar sesión?', 'Cerrar sesión');
    if (ok != true) return;
    await _supabase.auth.signOut();
    _irAlLogin();
  }

  Future<void> _eliminarCuenta() async {
    final ok = await _confirmar(
      'Eliminar cuenta',
      '¿Seguro que quieres eliminar tu cuenta de entrenador? Se borrarán todos tus datos y conexiones. No se puede deshacer.',
      'Eliminar todo',
    );
    if (ok != true) return;
    try {
      await _supabase.rpc('eliminar_mi_cuenta');
      await _supabase.auth.signOut();
      _irAlLogin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e'), backgroundColor: Colors.red[700]));
      }
    }
  }

  Future<bool?> _confirmar(String titulo, String texto, String accion) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        content: Text(texto, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(accion, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _irAlLogin() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicial = _nombre.isNotEmpty ? _nombre[0].toUpperCase() : 'E';

    return Scaffold(
      backgroundColor: _negro,
      body: SafeArea(
        child: RefreshIndicator(
          color: _amarillo,
          onRefresh: _cargar,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                const Text('Mi Perfil',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // Tarjeta de perfil
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _gris,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _amarillo.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: _amarillo,
                        child: Text(inicial,
                            style: const TextStyle(
                                color: Colors.black, fontSize: 36, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 16),
                      Text('$_nombre $_apellido'.trim(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_email, style: const TextStyle(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _amarillo.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('ENTRENADOR',
                            style: TextStyle(
                                color: _amarillo, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Tarjetas de estadísticas
                Row(
                  children: [
                    Expanded(child: _statCard('$_totalUsuarios', 'Usuarios', Icons.people)),
                    const SizedBox(width: 12),
                    Expanded(child: _statCardCodigo()),
                  ],
                ),

                const SizedBox(height: 24),

                // Opción: Usuarios bloqueados
                _opcion(
                  icono: Icons.block,
                  titulo: 'Usuarios bloqueados',
                  subtitulo: 'Ver y desbloquear usuarios',
                  colorIcono: Colors.orangeAccent,
                  onTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const EntrenadorBloqueadosScreen()));
                    _cargar(); // refrescar al volver
                  },
                ),
                const SizedBox(height: 12),

                // Opción: Cerrar sesión
                _opcion(
                  icono: Icons.logout,
                  titulo: 'Cerrar sesión',
                  subtitulo: 'Salir de tu cuenta',
                  onTap: _signOut,
                ),
                const SizedBox(height: 12),
                // Opción: Eliminar cuenta
                _opcion(
                  icono: Icons.delete_forever,
                  titulo: 'Eliminar cuenta',
                  subtitulo: 'Borra tu cuenta y todos tus datos',
                  onTap: _eliminarCuenta,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String valor, String label, IconData icono) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(icono, color: _amarillo, size: 26),
          const SizedBox(height: 8),
          Text(valor, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _statCardCodigo() {
    return GestureDetector(
      onTap: () {
        if (_codigo != null) {
          Clipboard.setData(ClipboardData(text: _codigo!));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Código copiado')));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _gris,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _amarillo.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.qr_code, color: _amarillo, size: 26),
            const SizedBox(height: 8),
            Text(_codigo ?? '------',
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const Text('Mi código', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
    Color colorIcono = Colors.redAccent,
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
            Icon(icono, color: colorIcono),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitulo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}