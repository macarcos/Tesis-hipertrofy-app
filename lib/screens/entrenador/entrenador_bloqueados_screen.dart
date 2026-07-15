// ============================================================
// lib/screens/entrenador/entrenador_bloqueados_screen.dart
// Lista de usuarios BLOQUEADOS por el entrenador.
// Permite DESBLOQUEAR (ahí el usuario podrá reconectarse).
// ============================================================
import 'package:flutter/material.dart';
import '../../services/entrenador_service.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class EntrenadorBloqueadosScreen extends StatefulWidget {
  const EntrenadorBloqueadosScreen({super.key});

  @override
  State<EntrenadorBloqueadosScreen> createState() => _EntrenadorBloqueadosScreenState();
}

class _EntrenadorBloqueadosScreenState extends State<EntrenadorBloqueadosScreen> {
  final _servicio = EntrenadorService();
  List<Map<String, dynamic>> _bloqueados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await _servicio.usuariosBloqueados();
    if (mounted) setState(() { _bloqueados = lista; _cargando = false; });
  }

  Future<void> _desbloquear(Map<String, dynamic> u) async {
    final nombre = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}'.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Desbloquear usuario', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Desbloquear a ${nombre.isEmpty ? "este usuario" : nombre}? '
          'Podrá volver a conectarse contigo y escribirte.',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desbloquear', style: TextStyle(color: _amarillo))),
        ],
      ),
    );
    if (ok != true) return;

    // Quitar de la lista al instante
    setState(() => _bloqueados.removeWhere((x) => x['id'] == u['id']));

    final error = await _servicio.desbloquearUsuario(u['id']);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red[700]));
      _cargar(); // si falló, recargar para que vuelva a aparecer
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Usuario desbloqueado'),
            backgroundColor: Colors.green[700]));
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
        title: const Text('Usuarios bloqueados', style: TextStyle(color: Colors.white)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _amarillo))
          : _bloqueados.isEmpty
              ? _vacio()
              : RefreshIndicator(
                  color: _amarillo,
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _bloqueados.length,
                    itemBuilder: (context, i) => _tile(_bloqueados[i]),
                  ),
                ),
    );
  }

  Widget _vacio() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
            color: _gris,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            children: [
              Icon(Icons.block, color: Colors.white38, size: 44),
              SizedBox(height: 12),
              Text('No tienes usuarios bloqueados',
                  style: TextStyle(color: Colors.white54)),
              SizedBox(height: 4),
              Text('Los usuarios que bloquees aparecerán aquí',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> u) {
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
        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Colors.redAccent.withOpacity(0.2),
          child: Text(inicial.toUpperCase(),
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ),
        title: Text(nombre.isEmpty ? 'Usuario' : nombre,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: TextButton(
          onPressed: () => _desbloquear(u),
          child: const Text('Desbloquear',
              style: TextStyle(color: _amarillo, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}