// ============================================================
// lib/screens/progreso_screen.dart
// Pantalla "Mi Progreso" — gráfico semanal + tarjetas + últimas sesiones
// ============================================================
import 'package:flutter/material.dart';
import '../../services/session_service.dart';
import '../../services/fecha_helper.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class ProgresoScreen extends StatefulWidget {
  const ProgresoScreen({super.key});

  @override
  State<ProgresoScreen> createState() => _ProgresoScreenState();
}

class _ProgresoScreenState extends State<ProgresoScreen> {
  final _sesiones = SessionService();
  Map<String, dynamic> _prog = {};
  List<Map<String, dynamic>> _ultimas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final prog = await _sesiones.obtenerProgreso();
    final ultimas = await _sesiones.obtenerHistorial();
    if (mounted) {
      setState(() {
        _prog = prog;
        _ultimas = ultimas.take(5).toList();
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: _negro,
        body: Center(child: CircularProgressIndicator(color: _amarillo)),
      );
    }

    final eficienciaPorDia =
        (_prog['eficienciaPorDia'] as List?)?.cast<double>() ?? List.filled(7, 0.0);
    final sesionesSemana = _prog['sesionesSemana'] ?? 0;

    return Scaffold(
      backgroundColor: _negro,
      body: RefreshIndicator(
        color: _amarillo,
        onRefresh: _cargar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text('Mi Progreso',
                  style: TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              Text('Semana actual · $sesionesSemana sesiones',
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 24),

              // ── Gráfico de eficiencia semanal ──
              _GraficoSemanal(eficiencias: eficienciaPorDia),

              const SizedBox(height: 20),

              // ── 4 tarjetas ──
              Row(
                children: [
                  Expanded(child: _tarjeta('🔥', '${_prog['sesionesTotales'] ?? 0}',
                      'SESIONES TOTALES', _amarillo)),
                  const SizedBox(width: 12),
                  Expanded(child: _tarjeta('✅', '${_prog['eficienciaMedia'] ?? 0}%',
                      'EFICIENCIA MEDIA', _amarillo)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _tarjeta('💪', '${_prog['repsValidas'] ?? 0}',
                      'REPS VÁLIDAS', _amarillo)),
                  const SizedBox(width: 12),
                  Expanded(child: _tarjeta('⚠️', '${_prog['erroresDetectados'] ?? 0}',
                      'ERRORES DETECTADOS', _amarillo)),
                ],
              ),

              const SizedBox(height: 28),
              const Text('Últimas sesiones',
                  style: TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),

              if (_ultimas.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Aún no tienes sesiones',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                ..._ultimas.map((s) => _sesionTile(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(String emoji, String valor, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 10),
          Text(valor,
              style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _sesionTile(Map<String, dynamic> s) {
    final ejercicio = s['ejercicio'] ?? 'Ejercicio';
    final validas = (s['reps_validas'] as int?) ?? 0;
    final totales = (s['reps_totales'] as int?) ?? 0;
    final pct = totales > 0 ? ((validas / totales) * 100).round() : 0;
    final cuando = FechaHelper.formatear(s['created_at']);

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
          Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(color: _amarillo, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ejercicio,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text('$cuando · $validas reps',
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

// ── Gráfico de barras semanal ──────────────────────────────────
class _GraficoSemanal extends StatelessWidget {
  final List<double> eficiencias; // 7 valores (L a D), 0-100
  const _GraficoSemanal({required this.eficiencias});

  @override
  Widget build(BuildContext context) {
    const dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _gris,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EFICIENCIA SEMANAL (%)',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final valor = eficiencias[i].clamp(0, 100);
                // altura mínima visible aunque sea 0
                final altura = valor == 0 ? 6.0 : (valor / 100 * 100) + 6;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: altura.toDouble(),
                          decoration: BoxDecoration(
                            color: valor == 0 ? Colors.white12 : _amarillo,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(dias[i],
                            style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}