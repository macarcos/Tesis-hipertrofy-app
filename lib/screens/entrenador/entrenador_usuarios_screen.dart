// ============================================================
// lib/screens/entrenador/entrenador_usuarios_screen.dart
// Pestaña USUARIOS del entrenador: lista de usuarios conectados
// Cuando vuelves de la pantalla de un usuario (donde pudiste
// bloquear/eliminar), avisa al contenedor para recargar TODAS
// las pestañas (onCambio).
// ============================================================
import 'package:flutter/material.dart';
import '../../services/entrenador_service.dart';
import 'entrenador_usuario_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class EntrenadorUsuariosScreen extends StatefulWidget {
  // Aviso opcional: se llama cuando algo cambia (bloquear/eliminar)
  final VoidCallback? onCambio;
  const EntrenadorUsuariosScreen({super.key, this.onCambio});

  // State PÚBLICO para que el contenedor pueda llamar recargar()
  @override
  EntrenadorUsuariosScreenState createState() => EntrenadorUsuariosScreenState();
}

class EntrenadorUsuariosScreenState extends State<EntrenadorUsuariosScreen> {
  final _servicio = EntrenadorService();
  List<Map<String, dynamic>> _usuarios = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // Método público: lo llama el contenedor al volver a esta pestaña
  void recargar() => _cargar();

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    final usuarios = await _servicio.misUsuarios();
    usuarios.sort((a, b) =>
        ((b['total_mensajes'] ?? 0) as int).compareTo((a['total_mensajes'] ?? 0) as int));
    if (mounted) setState(() { _usuarios = usuarios; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Text('Mis Usuarios (${_usuarios.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: _cargando
                    ? const Center(child: CircularProgressIndicator(color: _amarillo))
                    : _usuarios.isEmpty
                        ? _vacio()
                        : RefreshIndicator(
                            color: _amarillo,
                            onRefresh: _cargar,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _usuarios.length,
                              itemBuilder: (context, i) => _usuarioTile(_usuarios[i]),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vacio() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
            color: _gris,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            children: [
              Icon(Icons.people_outline, color: Colors.white38, size: 44),
              SizedBox(height: 12),
              Text('Aún no tienes usuarios conectados',
                  style: TextStyle(color: Colors.white54)),
              SizedBox(height: 4),
              Text('Comparte tu código (pestaña Inicio) para que se conecten',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }

  Widget _usuarioTile(Map<String, dynamic> u) {
    final nombre = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}'.trim();
    final email = u['correo'] ?? '';
    final inicial = (u['nombre']?.toString() ?? 'U').isNotEmpty
        ? (u['nombre']?.toString() ?? 'U')[0]
        : 'U';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: _amarillo,
          child: Text(inicial.toUpperCase(),
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        title: Text(nombre.isEmpty ? 'Usuario' : nombre,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((u['total_mensajes'] ?? 0) > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _amarillo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${u['total_mensajes']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
        onTap: () async {
          // Al volver de la pantalla del usuario:
          //  - recargar esta lista
          //  - avisar al contenedor para recargar TAMBIÉN Inicio y Perfil
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => EntrenadorUsuarioScreen(
              usuarioId: u['id'],
              usuarioNombre: nombre.isEmpty ? 'Usuario' : nombre,
            ),
          ));
          await _cargar();
          widget.onCambio?.call(); // recarga Inicio + Perfil también
        },
      ),
    );
  }
}