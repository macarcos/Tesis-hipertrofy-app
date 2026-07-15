// ============================================================
// lib/screens/entrenador/entrenador_inicio_screen.dart
// Pestaña INICIO del entrenador: bienvenida, código y resumen
// El QR se TOCA para verlo grande. State público para recargar().
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/entrenador_service.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class EntrenadorInicioScreen extends StatefulWidget {
  const EntrenadorInicioScreen({super.key});

  // State PÚBLICO para que el contenedor pueda llamar recargar()
  @override
  EntrenadorInicioScreenState createState() => EntrenadorInicioScreenState();
}

class EntrenadorInicioScreenState extends State<EntrenadorInicioScreen> {
  final _servicio = EntrenadorService();
  final _supabase = Supabase.instance.client;

  String _nombre = '';
  String? _codigo;
  int _totalUsuarios = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // Método público: lo llama el contenedor al volver a esta pestaña
  void recargar() => _cargar();

  Future<void> _cargar() async {
    final user = _supabase.auth.currentUser;
    String nombre = 'Entrenador';
    if (user != null) {
      try {
        final data = await _supabase
            .from('perfiles')
            .select('nombre')
            .eq('id', user.id)
            .maybeSingle();
        nombre = data?['nombre'] ?? 'Entrenador';
      } catch (_) {}
    }
    final codigo = await _servicio.miCodigo();
    final usuarios = await _servicio.misUsuarios();
    if (mounted) {
      setState(() {
        _nombre = nombre;
        _codigo = codigo;
        _totalUsuarios = usuarios.length;
        _cargando = false;
      });
    }
  }

  // Abre el QR en grande (pantalla completa) para que sea fácil de escanear
  void _abrirQrGrande() {
    if (_codigo == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => _QrGrandeDialog(codigo: _codigo!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: _amarillo))
            : RefreshIndicator(
                color: _amarillo,
                onRefresh: _cargar,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      const Text('BIOSMART',
                          style: TextStyle(
                              color: _amarillo, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text('Hola, $_nombre 👋',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Bienvenido a tu panel de entrenador',
                          style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 24),

                      // Tarjeta del código
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_amarillo.withOpacity(0.25), _amarillo.withOpacity(0.05)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _amarillo.withOpacity(0.5)),
                        ),
                        child: Column(
                          children: [
                            const Text('TU CÓDIGO DE ENTRENADOR',
                                style: TextStyle(color: _amarillo, fontSize: 12, letterSpacing: 1)),
                            const SizedBox(height: 10),
                            Text(_codigo ?? '------',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 8)),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              icon: const Icon(Icons.copy, color: _amarillo, size: 16),
                              label: const Text('Copiar código', style: TextStyle(color: _amarillo)),
                              onPressed: () {
                                if (_codigo != null) {
                                  Clipboard.setData(ClipboardData(text: _codigo!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Código copiado')));
                                }
                              },
                            ),
                            const Text('Comparte este código con tus usuarios',
                                style: TextStyle(color: Colors.white54, fontSize: 12)),

                            // Código QR (tocable: se abre grande para escanear fácil)
                            if (_codigo != null) ...[
                              const SizedBox(height: 18),
                              GestureDetector(
                                onTap: _abrirQrGrande,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: QrImageView(
                                    data: _codigo!,
                                    version: QrVersions.auto,
                                    size: 140,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _abrirQrGrande,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.zoom_in, color: _amarillo, size: 16),
                                    SizedBox(width: 6),
                                    Text('Toca el QR para ampliarlo',
                                        style: TextStyle(color: _amarillo, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Resumen
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _gris,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.people, color: _amarillo, size: 40),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$_totalUsuarios',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                                const Text('Usuarios conectados',
                                    style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _amarillo.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _amarillo.withOpacity(0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: _amarillo),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Ve a la pestaña "Usuarios" para revisar las sesiones de tus atletas y enviarles mensajes.',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Diálogo que muestra el QR en GRANDE para escanear fácil ──────────
class _QrGrandeDialog extends StatelessWidget {
  final String codigo;
  const _QrGrandeDialog({required this.codigo});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: codigo,
              version: QrVersions.auto,
              size: 280,
            ),
          ),
          const SizedBox(height: 20),
          Text(codigo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8)),
          const SizedBox(height: 8),
          const Text('El usuario escanea este código desde su app',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _amarillo,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.close),
              label: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}