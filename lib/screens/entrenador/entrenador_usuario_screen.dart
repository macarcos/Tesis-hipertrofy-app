// ============================================================
// lib/screens/entrenador/entrenador_usuario_screen.dart
// El entrenador ve las sesiones de UN usuario + chat
// Puede ELIMINAR (desconectar) o BLOQUEAR al usuario.
// ============================================================
import 'package:flutter/material.dart';
import '../../services/entrenador_service.dart';
import '../../services/fecha_helper.dart';
import '../shared/detalle_sesion_screen.dart';
import '../shared/chat_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class EntrenadorUsuarioScreen extends StatefulWidget {
  final String usuarioId;
  final String usuarioNombre;
  const EntrenadorUsuarioScreen({
    super.key,
    required this.usuarioId,
    required this.usuarioNombre,
  });

  @override
  State<EntrenadorUsuarioScreen> createState() => _EntrenadorUsuarioScreenState();
}

class _EntrenadorUsuarioScreenState extends State<EntrenadorUsuarioScreen> {
  final _servicio = EntrenadorService();
  List<Map<String, dynamic>> _sesiones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final sesiones = await _servicio.sesionesDeUsuario(widget.usuarioId);
    if (mounted) setState(() { _sesiones = sesiones; _cargando = false; });
  }

  Future<void> _eliminarUsuario() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Eliminar usuario', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Quitar a ${widget.usuarioNombre} de tus usuarios? Podrá volver a conectarse con tu código.',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    final error = await _servicio.eliminarUsuario(widget.usuarioId);
    if (mounted) {
      if (error == null) {
        Navigator.pop(context); // volver a la lista
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red[700]));
      }
    }
  }

  Future<void> _bloquearUsuario() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Bloquear usuario', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Bloquear a ${widget.usuarioNombre}? Se eliminará de tus usuarios y '
          'no podrá volver a conectarse contigo ni escribirte. '
          'Podrás desbloquearlo desde tu perfil cuando quieras.',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bloquear', style: TextStyle(color: Colors.orangeAccent))),
        ],
      ),
    );
    if (ok != true) return;

    // La RPC bloquear_usuario guarda el bloqueo Y borra la conexión de una vez
    final error = await _servicio.bloquearUsuario(widget.usuarioId);
    if (mounted) {
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.usuarioNombre} fue bloqueado'),
              backgroundColor: Colors.green[700]));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red[700]));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.usuarioNombre, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble, color: _amarillo),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ChatScreen(
                otroId: widget.usuarioId,
                otroNombre: widget.usuarioNombre,
              ),
            )),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: _gris,
            onSelected: (v) {
              if (v == 'eliminar') _eliminarUsuario();
              if (v == 'bloquear') _bloquearUsuario();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'bloquear',
                child: Text('Bloquear usuario', style: TextStyle(color: Colors.orangeAccent)),
              ),
              const PopupMenuItem(
                value: 'eliminar',
                child: Text('Eliminar usuario', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _amarillo))
          : _sesiones.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, color: Colors.white38, size: 48),
                      SizedBox(height: 12),
                      Text('Este usuario aún no tiene sesiones',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: _amarillo,
                  onRefresh: _cargar,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _amarillo,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.chat_bubble),
                            label: const Text('Enviar mensaje',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                otroId: widget.usuarioId,
                                otroNombre: widget.usuarioNombre,
                              ),
                            )),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _sesiones.length,
                          itemBuilder: (context, i) => _sesionTile(_sesiones[i]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sesionTile(Map<String, dynamic> s) {
    final ejercicio = s['ejercicio'] ?? 'Ejercicio';
    final validas = (s['reps_validas'] as int?) ?? 0;
    final totales = (s['reps_totales'] as int?) ?? 0;
    final invalidas = (s['reps_invalidas'] as int?) ?? 0;
    final pct = totales > 0 ? ((validas / totales) * 100).round() : 0;
    final cuando = FechaHelper.formatear(s['created_at']);
    final tieneVideo = (s['video_url'] != null &&
        s['video_url'].toString().isNotEmpty);

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DetalleSesionScreen(
            sesion: s,
            chatConId: widget.usuarioId,
            chatConNombre: widget.usuarioNombre,
            puedeGenerar: false, // el entrenador solo VE el PDF, no lo genera
          ))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _gris,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(ejercicio,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text('$pct%',
                    style: TextStyle(
                        color: pct >= 70 ? _amarillo : Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(cuando, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const Spacer(),
                if (tieneVideo)
                  const Icon(Icons.videocam, color: _amarillo, size: 16),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _chip('$totales total', Colors.white),
                const SizedBox(width: 8),
                _chip('$validas válidas', Colors.greenAccent),
                const SizedBox(width: 8),
                _chip('$invalidas inválidas', Colors.redAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}