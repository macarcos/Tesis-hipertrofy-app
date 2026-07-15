// ============================================================
// lib/screens/home_screen.dart
// Panel principal — SIN barra propia (la barra vive en MainScreen)
// Muestra historial de HOY y estadísticas desde Supabase
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/session_service.dart';
import '../../services/fecha_helper.dart';
import 'camera_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  final _sesiones = SessionService();

  String _userName = "...";
  Map<String, int> _stats = {'sesiones': 0, 'repsValidas': 0, 'eficiencia': 0};
  List<Map<String, dynamic>> _historial = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _getProfileData();
    _cargarDatos();
  }

  Future<void> _getProfileData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase
          .from('perfiles')
          .select('nombre')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) setState(() => _userName = data?['nombre'] ?? 'Usuario');
    } catch (_) {
      final meta = user.userMetadata?['first_name'] as String?;
      if (mounted) setState(() => _userName = meta ?? 'Usuario');
    }
  }

  Future<void> _cargarDatos() async {
    final stats = await _sesiones.obtenerEstadisticas();
    final hist = await _sesiones.obtenerSesionesDeHoy();
    if (mounted) {
      setState(() {
        _stats = stats;
        _historial = hist;
        _cargandoHistorial = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('BIOSMART',
            style: TextStyle(color: _amarillo, fontWeight: FontWeight.w900, letterSpacing: 2)),
      ),
      body: RefreshIndicator(
        color: _amarillo,
        onRefresh: _cargarDatos,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hola, $_userName 👋',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('¿Qué vamos a analizar hoy?',
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 24),

              // Tarjeta Iniciar Análisis
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_amarillo.withOpacity(0.25), _amarillo.withOpacity(0.05)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _amarillo.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.videocam_rounded, size: 40, color: _amarillo),
                    const SizedBox(height: 14),
                    const Text('Iniciar Análisis',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _amarillo)),
                    const SizedBox(height: 4),
                    const Text('Usa la IA para corregir tu técnica en tiempo real.',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _amarillo,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const CameraScreen()));
                        _cargarDatos(); // recargar al volver
                      },
                      child: const Text('Abrir Cámara',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Stats reales
              Row(
                children: [
                  Expanded(child: _statCard('🔥', 'SESIONES', '${_stats['sesiones']}')),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('📈', 'EFICIENCIA', '${_stats['eficiencia']}%')),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('✅', 'REPS VÁLIDAS', '${_stats['repsValidas']}')),
                ],
              ),

              const SizedBox(height: 28),
              const Text('Historial Reciente',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 14),

              if (_cargandoHistorial)
                const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: _amarillo),
                ))
              else if (_historial.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: _gris,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.history_toggle_off, color: Colors.white38, size: 40),
                      SizedBox(height: 10),
                      Text('Aún no has entrenado hoy',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              else
                ..._historial.map((s) => _historialTile(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String emoji, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _historialTile(Map<String, dynamic> s) {
    final ejercicio = s['ejercicio'] ?? 'Ejercicio';
    final validas = (s['reps_validas'] as int?) ?? 0;
    final totales = (s['reps_totales'] as int?) ?? 0;
    final pct = totales > 0 ? ((validas / totales) * 100).round() : 0;
    final cuando = FechaHelper.soloHora(s['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ejercicio,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text('$validas de $totales válidas · $cuando',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Text('$pct%',
              style: TextStyle(
                  color: pct >= 70 ? _amarillo : Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ],
      ),
    );
  }
}