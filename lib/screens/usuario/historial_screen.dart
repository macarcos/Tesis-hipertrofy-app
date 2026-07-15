// ============================================================
// lib/screens/historial_screen.dart
// Historial COMPLETO de todas las sesiones (va en Perfil)
// Muestra las sesiones de Supabase Y las pendientes del teléfono (sin internet).
// Las pendientes salen marcadas y NO se pueden abrir en detalle (aún no subidas).
// ============================================================
import 'package:flutter/material.dart';
import '../../services/session_service.dart';
import '../../services/entrenador_service.dart';
import '../../services/fecha_helper.dart';
import '../../services/offline_store.dart';
import '../../services/sync_service.dart';
import '../shared/detalle_sesion_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _sesiones = SessionService();
  final _entrenadorService = EntrenadorService();
  List<Map<String, dynamic>> _todo = [];
  List<Map<String, dynamic>> _pendientes = []; // sesiones guardadas sin internet
  Map<String, dynamic>? _entrenador;
  bool _cargando = true;

  // ── Estado del aviso de subida ────────────────────────────────────────────
  bool _subiendo = false;   // hay una subida en curso

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    // 1) Leer pendientes del teléfono (local, rápido, sin internet)
    List<Map<String, dynamic>> pend = [];
    try {
      pend = await OfflineStore.leerPendientes();
    } catch (_) {}

    // 2) Cargar lo de Supabase (con límite de tiempo para no colgar)
    List<Map<String, dynamic>> data = [];
    Map<String, dynamic>? ent;
    try {
      data = await _sesiones.obtenerTodoElHistorial()
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
    } catch (_) {
      data = [];
    }
    try {
      ent = await _entrenadorService.miEntrenador()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {
      ent = null;
    }

    // 3) Mostrar ya la pantalla con lo que hay
    if (mounted) setState(() {
      _todo = data;
      _pendientes = pend;
      _entrenador = ent;
      _cargando = false;
    });

    // 4) Si hay pendientes, intentar subirlos MOSTRANDO la barra de progreso.
    //    (La sincronización revisa internet por dentro; si no hay, no hace nada.)
    if (pend.isNotEmpty) {
      await _sincronizarConBarra();
    }
  }

  // Sube los pendientes mostrando un aviso simple mientras trabaja.
  Future<void> _sincronizarConBarra() async {
    if (_subiendo) return;
    if (mounted) setState(() => _subiendo = true);

    final subidas = await SyncService.sincronizar();

    if (!mounted) return;

    // -1 = ya había una subida en curso (otra llamada). Igual quitamos el aviso
    // de ESTA pantalla; la otra terminará por su cuenta.
    // Cualquier otro valor: terminó. Recargamos para reflejar lo subido.
    setState(() => _subiendo = false);

    // Recargar la lista SIEMPRE (por si subió algo, que ya no salga pendiente)
    final pend = await OfflineStore.leerPendientes();
    List<Map<String, dynamic>> data = [];
    try {
      data = await _sesiones.obtenerTodoElHistorial()
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
    } catch (_) {}
    if (mounted) setState(() { _todo = data; _pendientes = pend; });
  }

  Future<void> _eliminarSesion(Map<String, dynamic> s) async {
    final sesionId = s['id']?.toString();
    if (sesionId == null) return;

    setState(() => _todo.removeWhere((x) => x['id'] == sesionId));

    final error = await _sesiones.eliminarSesion(sesionId);
    if (!mounted) return;

    if (error != null) {
      _msg(error);
      _cargar();
    } else {
      _msg('Entrenamiento eliminado', exito: true);
    }
  }

  void _msg(String m, {bool exito = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: exito ? Colors.green[700] : Colors.red[700]),
      );

  @override
  Widget build(BuildContext context) {
    final hayAlgo = _todo.isNotEmpty || _pendientes.isNotEmpty;
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Historial completo', style: TextStyle(color: Colors.white)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _amarillo))
          : !hayAlgo
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, color: Colors.white38, size: 48),
                      SizedBox(height: 12),
                      Text('Aún no tienes entrenamientos',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: _amarillo,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Barra de progreso de subida (solo mientras sube)
                      if (_subiendo) _barraProgreso(),
                      // Primero los pendientes (guardados sin internet)
                      ..._pendientes.map((p) => _tilePendiente(p)),
                      // Luego los de Supabase (ya subidos)
                      ..._todo.map((s) => _tileDeslizable(s)),
                    ],
                  ),
                ),
    );
  }

  // ── AVISO SIMPLE de subida (solo texto + spinner, robusto) ────────────────
  Widget _barraProgreso() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amarillo.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _amarillo),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Subiendo tus sesiones pendientes...',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // Tarjeta de una sesión PENDIENTE (guardada sin internet, aún no subida)
  Widget _tilePendiente(Map<String, dynamic> p) {
    final ejercicio = p['ejercicio'] ?? 'Ejercicio';
    final validas = (p['reps_validas'] as int?) ?? 0;
    final totales = (p['reps_totales'] as int?) ?? 0;
    final invalidas = (p['reps_invalidas'] as int?) ?? 0;
    final pct = totales > 0 ? ((validas / totales) * 100).round() : 0;
    final cuando = FechaHelper.formatear(p['creado']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
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
          Text(cuando, style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
          const SizedBox(height: 12),
          // Aviso de pendiente de subir
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Guardado en el teléfono. Se subirá cuando vuelva el internet.',
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileDeslizable(Map<String, dynamic> s) {
    return Dismissible(
      key: ValueKey(s['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _gris,
            title: const Text('Eliminar entrenamiento',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              '¿Seguro que quieres eliminar este entrenamiento? '
              'Tu entrenador ya no podrá verlo. No se puede deshacer.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _eliminarSesion(s),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(width: 8),
            Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      child: _tile(s),
    );
  }

  Widget _tile(Map<String, dynamic> s) {
    final ejercicio = s['ejercicio'] ?? 'Ejercicio';
    final validas = (s['reps_validas'] as int?) ?? 0;
    final totales = (s['reps_totales'] as int?) ?? 0;
    final invalidas = (s['reps_invalidas'] as int?) ?? 0;
    final pct = totales > 0 ? ((validas / totales) * 100).round() : 0;
    final cuando = FechaHelper.formatear(s['created_at']);

    final diag = s['diagnostico_ia'];
    String? recomendacion;
    if (diag is Map && diag['recomendacion'] != null) {
      recomendacion = diag['recomendacion'].toString();
    }

    return GestureDetector(
      onTap: () async {
        final borrado = await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => DetalleSesionScreen(
              sesion: s,
              puedeEliminar: true,
              chatConId: _entrenador?['id'],
              chatConNombre: _entrenador == null
                  ? null
                  : '${_entrenador!['nombre'] ?? ''} ${_entrenador!['apellido'] ?? ''}'.trim(),
            )));
        if (borrado == true) _cargar();
      },
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
            if (recomendacion != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _amarillo.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, color: _amarillo, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(recomendacion,
                          style: const TextStyle(color: _amarillo, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
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