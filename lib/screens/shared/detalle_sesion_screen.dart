// ============================================================
// lib/screens/detalle_sesion_screen.dart
// Detalle completo de UNA sesión guardada (se abre desde el historial)
// Muestra: resumen, detalle rep por rep, video (si hay), diagnóstico IA
// y el DOCUMENTO PDF (si ya se generó, se descarga; si no, botón para generarlo).
// El usuario DUEÑO puede ELIMINAR su entrenamiento (puedeEliminar=true).
// ============================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../services/fecha_helper.dart';
import '../../services/session_service.dart';
import '../../services/rep_counter.dart';
import '../../services/ai_coach_service.dart';
import '../../services/pdf_service.dart';
import '../../services/r2_service.dart';
import 'chat_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class DetalleSesionScreen extends StatefulWidget {
  final Map<String, dynamic> sesion;
  final String? chatConId;
  final String? chatConNombre;
  final bool puedeEliminar;
  // Si es true (el DUEÑO), puede generar el PDF cuando no existe.
  // Si es false (el ENTRENADOR), solo lo ve si el usuario ya lo generó.
  final bool puedeGenerar;
  const DetalleSesionScreen({
    super.key,
    required this.sesion,
    this.chatConId,
    this.chatConNombre,
    this.puedeEliminar = false,
    this.puedeGenerar = true,
  });

  @override
  State<DetalleSesionScreen> createState() => _DetalleSesionScreenState();
}

class _DetalleSesionScreenState extends State<DetalleSesionScreen> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _eliminando = false;
  List<Map<String, int>> _erroresTimestamps = [];

  // ── Estado del PDF ────────────────────────────────────────────────────────
  String? _pdfUrl;            // URL del PDF en R2 (si ya existe)
  bool _generandoPdf = false; // mientras genera + sube
  bool _bajandoPdf = false;   // mientras descarga/comparte

  @override
  void initState() {
    super.initState();
    _pdfUrl = widget.sesion['pdf_url']?.toString();
    if (_pdfUrl != null && _pdfUrl!.isEmpty) _pdfUrl = null;
    _cargarTimestamps();
    _initVideo();
    _refrescarPdfUrl(); // consulta la versión fresca por si ya se generó el PDF
  }

  // Consulta a Supabase la sesión fresca para ver si ya tiene pdf_url.
  // Esto arregla que, tras generar el PDF y volver a entrar, aparezcan
  // directamente Descargar/Compartir (y no vuelva a pedir Generar).
  Future<void> _refrescarPdfUrl() async {
    final sesionId = widget.sesion['id']?.toString();
    if (sesionId == null) return;
    final fresca = await SessionService().sesionPorId(sesionId);
    if (!mounted || fresca == null) return;
    final url = fresca['pdf_url']?.toString();
    if (url != null && url.isNotEmpty && url != _pdfUrl) {
      setState(() => _pdfUrl = url);
    }
  }

  void _cargarTimestamps() {
    final raw = widget.sesion['errores_timestamps'];
    if (raw is List) {
      _erroresTimestamps = raw.map((e) {
        final m = e as Map;
        return {
          'inicio': (m['inicio'] as num?)?.toInt() ?? 0,
          'fin': (m['fin'] as num?)?.toInt() ?? 0,
        };
      }).toList();
    }
  }

  String _formatoTiempo(int ms) {
    final totalSeg = ms ~/ 1000;
    final min = totalSeg ~/ 60;
    final seg = totalSeg % 60;
    return '$min:${seg.toString().padLeft(2, '0')}';
  }

  Future<void> _initVideo() async {
    final url = widget.sesion['video_url'];
    if (url == null || url.toString().isEmpty) return;
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url.toString()));
      await _videoController!.initialize();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {}
  }

  // ── Reconstruir el ExerciseType desde el nombre guardado ──────────────────
  ExerciseType _tipoDesdeNombre(String nombre) {
    final n = nombre.toLowerCase();
    if (n.contains('press')) return ExerciseType.pressMilitar;
    if (n.contains('elevaci')) return ExerciseType.elevacionLateral;
    if (n.contains('mancuerna') || n.contains('goblet')) return ExerciseType.gobletSquat;
    return ExerciseType.sentadilla;
  }

  // ── Reconstruir las reps desde reps_detalle guardado en Supabase ──────────
  List<RepResult> _repsDesdeSesion() {
    final raw = (widget.sesion['reps_detalle'] as List?) ?? [];
    final reps = <RepResult>[];
    for (final r in raw) {
      final m = r as Map;
      reps.add(RepResult(
        isValid: m['valida'] == true,
        reason: m['razon']?.toString() ?? '',
        timestamp: 0,
      ));
    }
    return reps;
  }

  // ── Reconstruir el ReporteCompleto desde lo guardado ──────────────────────
  ReporteCompleto _reporteDesdeSesion() {
    final rc = widget.sesion['reporte_completo'];
    if (rc is Map) {
      return ReporteCompleto(
        resumenGeneral:      rc['resumen_general']?.toString() ?? '',
        analisisBiomecanico: rc['analisis_biomecanico']?.toString() ?? '',
        musculosEnRiesgo:    rc['musculos_en_riesgo']?.toString() ?? '',
        posibleLesion:       rc['posible_lesion']?.toString() ?? 'Ninguna',
        evidenciaCientifica: rc['evidencia_cientifica']?.toString() ?? '',
        recomendaciones:     rc['recomendaciones']?.toString() ?? '',
        nivelRiesgo:         rc['nivel_riesgo']?.toString() ?? 'bajo',
      );
    }
    // Si no hay reporte completo guardado, intentar armar algo con el diagnóstico
    final diag = widget.sesion['diagnostico_ia'];
    if (diag is Map) {
      return ReporteCompleto(
        resumenGeneral: '',
        analisisBiomecanico: diag['descripcion']?.toString() ?? '',
        musculosEnRiesgo: diag['musculos_en_riesgo']?.toString() ?? '',
        posibleLesion: diag['posible_lesion']?.toString() ?? 'Ninguna',
        evidenciaCientifica: '',
        recomendaciones: diag['recomendacion']?.toString() ?? '',
        nivelRiesgo: diag['nivel_riesgo']?.toString() ?? 'bajo',
      );
    }
    return ReporteCompleto.respaldo(widget.sesion['ejercicio']?.toString() ?? 'Ejercicio');
  }

  // ── GENERAR el documento desde el historial (genera + sube + guarda URL) ──
  Future<void> _generarDocumento() async {
    setState(() => _generandoPdf = true);
    try {
      final ejercicio = widget.sesion['ejercicio']?.toString() ?? 'Ejercicio';
      final reps = _repsDesdeSesion();
      final validas = (widget.sesion['reps_validas'] as int?) ?? reps.where((r) => r.isValid).length;
      final invalidas = (widget.sesion['reps_invalidas'] as int?) ?? reps.where((r) => !r.isValid).length;
      final errores = ((widget.sesion['errores'] as List?) ?? [])
          .map((e) => e.toString()).toList();

      // 1) Generar bytes del PDF
      final bytes = await PdfService.generarBytes(
        reporte: _reporteDesdeSesion(),
        ejercicio: ejercicio,
        tipoEjercicio: _tipoDesdeNombre(ejercicio),
        nombreUsuario: 'Usuario BioSmart',
        reps: reps,
        validReps: validas,
        invalidReps: invalidas,
        errores: errores,
      );

      // 2) Subir a R2
      final url = await R2Service.subirPdf(bytes);

      // 3) Guardar la URL en Supabase
      final sesionId = widget.sesion['id']?.toString();
      if (url != null && sesionId != null) {
        await SessionService().actualizarPdfUrl(sesionId, url);
      }

      if (mounted) {
        setState(() {
          _pdfUrl = url;
          _generandoPdf = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(url != null
                ? 'Documento generado y guardado ✓'
                : 'No se pudo subir el documento'),
            backgroundColor: url != null ? Colors.green[700] : Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generandoPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  // ── Previsualizar el PDF DENTRO de la app (visor integrado) ───────────────
  Future<void> _previsualizarPdf() async {
    if (_pdfUrl == null) return;
    setState(() => _bajandoPdf = true);
    try {
      final resp = await http.get(Uri.parse(_pdfUrl!));
      if (resp.statusCode == 404) {
        _pdfYaNoExiste();
        return;
      }
      if (resp.statusCode != 200) throw 'No se pudo bajar (${resp.statusCode})';
      final bytes = resp.bodyBytes;
      if (!mounted) return;
      setState(() => _bajandoPdf = false);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'BioSmart_Reporte.pdf',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _bajandoPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo previsualizar: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  // El PDF ya no existe en R2 (fue borrado). Limpiamos la URL para que
  // vuelva a aparecer el botón "Generar documento" y se pueda regenerar.
  Future<void> _pdfYaNoExiste() async {
    final sesionId = widget.sesion['id']?.toString();
    if (sesionId != null) {
      // Limpiar la URL en Supabase (guardar vacío)
      await SessionService().actualizarPdfUrl(sesionId, '');
    }
    if (mounted) {
      setState(() {
        _pdfUrl = null;   // vuelve a mostrar "Generar documento"
        _bajandoPdf = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('El documento ya no está disponible. Puedes generarlo de nuevo.'),
            backgroundColor: Colors.orange[800]),
      );
    }
  }

  // ── Descargar el PDF ya guardado (desde su URL de R2) ─────────────────────
  Future<void> _descargarPdfGuardado({required bool compartir}) async {
    if (_pdfUrl == null) return;
    setState(() => _bajandoPdf = true);
    try {
      final resp = await http.get(Uri.parse(_pdfUrl!));
      if (resp.statusCode == 404) {
        _pdfYaNoExiste();
        return;
      }
      if (resp.statusCode != 200) throw 'No se pudo bajar (${resp.statusCode})';
      final bytes = resp.bodyBytes;

      if (compartir) {
        await Printing.sharePdf(bytes: bytes, filename: 'BioSmart_Reporte.pdf');
      } else {
        Directory? dir;
        try {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) dir = await getExternalStorageDirectory();
        } catch (_) {
          dir = await getApplicationDocumentsDirectory();
        }
        dir ??= await getApplicationDocumentsDirectory();
        final ruta = '${dir.path}/BioSmart_Reporte_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(ruta).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF guardado en Descargas:\n$ruta'),
                backgroundColor: Colors.green[700], duration: const Duration(seconds: 4)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener el PDF: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _bajandoPdf = false);
    }
  }

  // ── Eliminar este entrenamiento (con confirmación) ──────────
  Future<void> _eliminarEntrenamiento() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Eliminar entrenamiento',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Seguro que quieres eliminar este entrenamiento? '
          'Se borrará para siempre y tu entrenador ya no podrá verlo. '
          'No se puede deshacer.',
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
    if (ok != true) return;

    final sesionId = widget.sesion['id']?.toString();
    if (sesionId == null) {
      _msg('No se pudo identificar el entrenamiento');
      return;
    }

    setState(() => _eliminando = true);
    final error = await SessionService().eliminarSesion(sesionId);
    if (!mounted) return;
    setState(() => _eliminando = false);

    if (error != null) {
      _msg(error);
    } else {
      Navigator.pop(context, true);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: Colors.red[700]),
      );

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    final ejercicio = s['ejercicio'] ?? 'Ejercicio';
    final totales = (s['reps_totales'] as int?) ?? 0;
    final validas = (s['reps_validas'] as int?) ?? 0;
    final invalidas = (s['reps_invalidas'] as int?) ?? 0;
    final cuando = FechaHelper.formatear(s['created_at']);

    final repsDetalle = (s['reps_detalle'] as List?) ?? [];
    final errores = (s['errores'] as List?) ?? [];
    final diag = s['diagnostico_ia'];

    return Scaffold(
      backgroundColor: _negro,
      floatingActionButton: (widget.chatConId != null)
          ? FloatingActionButton.extended(
              backgroundColor: _amarillo,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.reply),
              label: const Text('Comentar en el chat',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    otroId: widget.chatConId!,
                    otroNombre: widget.chatConNombre ?? 'Chat',
                    sesionIdAdjunta: widget.sesion['id']?.toString(),
                    ejercicioAdjunto: widget.sesion['ejercicio']?.toString() ?? 'Ejercicio',
                  ),
                ));
              },
            )
          : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(ejercicio, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (widget.puedeEliminar)
            IconButton(
              icon: _eliminando
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2))
                  : const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Eliminar entrenamiento',
              onPressed: _eliminando ? null : _eliminarEntrenamiento,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cuando, style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 16),

            // ── RESUMEN ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_amarillo.withOpacity(0.25), _amarillo.withOpacity(0.05)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _amarillo.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Completaste $totales repeticiones',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _pill('Válidas', validas, Colors.greenAccent),
                      const SizedBox(width: 12),
                      _pill('No válidas', invalidas, Colors.redAccent),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── DETALLE REP POR REP ──
            if (repsDetalle.isNotEmpty) ...[
              const Text('Detalle de repeticiones',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              ...repsDetalle.asMap().entries.map((e) {
                final i = e.key + 1;
                final rep = e.value as Map;
                final valida = rep['valida'] == true;
                final razon = rep['razon']?.toString() ?? '';
                return _repTile(i, valida, razon);
              }),
              const SizedBox(height: 20),
            ]
            else if (errores.isNotEmpty) ...[
              const Text('Errores detectados',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              ...errores.map((err) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(err.toString(),
                              style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 20),
            ],

            // ── VIDEO (si hay) ──
            if (_videoReady && _videoController != null) ...[
              const Text('Video de la sesión',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoController!),
                      IconButton(
                        icon: Icon(
                          _videoController!.value.isPlaying
                              ? Icons.pause_circle : Icons.play_circle,
                          color: Colors.white, size: 50,
                        ),
                        onPressed: () {
                          setState(() {
                            _videoController!.value.isPlaying
                                ? _videoController!.pause()
                                : _videoController!.play();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_erroresTimestamps.isNotEmpty) ...[
                const Text('Saltar a los errores:',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_erroresTimestamps.length, (i) {
                    final ms = _erroresTimestamps[i]['inicio'] ?? 0;
                    return GestureDetector(
                      onTap: () {
                        _videoController!.seekTo(Duration(milliseconds: ms));
                        _videoController!.play();
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[800]!),
                        ),
                        child: Text('Error ${i + 1} · ${_formatoTiempo(ms)}',
                            style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
              ],
            ],

            if (diag is Map) ...[
              const Text('Diagnóstico médico',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              _diagnostico(diag),
            ],

            // ── DOCUMENTO PDF ────────────────────────────────────────────────
            // El DUEÑO puede generar/ver. El ENTRENADOR solo ve si ya existe.
            if (widget.puedeGenerar || _pdfUrl != null) ...[
              const SizedBox(height: 24),
              const Text('Documento del reporte',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              _seccionPdf(),
            ],

            // ── BOTÓN ELIMINAR ENTRENAMIENTO (solo el dueño) ──
            if (widget.puedeEliminar) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _eliminando
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2))
                      : const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: Text(_eliminando ? 'Eliminando...' : 'Eliminar este entrenamiento',
                      style: const TextStyle(
                          color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: _eliminando ? null : _eliminarEntrenamiento,
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // Sección del PDF: si ya existe → Descargar/Compartir; si no → Generar
  Widget _seccionPdf() {
    if (_pdfUrl != null) {
      // Ya existe el documento → Ver (previsualizar) + Descargar + Compartir
      return Column(
        children: [
          // Botón grande: PREVISUALIZAR
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _amarillo,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _bajandoPdf ? null : _previsualizarPdf,
              icon: _bajandoPdf
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.visibility, size: 20),
              label: const Text('Previsualizar documento',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          ),
          const SizedBox(height: 10),
          // Descargar + Compartir
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _amarillo,
                      side: const BorderSide(color: _amarillo, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _bajandoPdf ? null : () => _descargarPdfGuardado(compartir: false),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Descargar',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _amarillo)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _amarillo,
                      side: const BorderSide(color: _amarillo, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _bajandoPdf ? null : () => _descargarPdfGuardado(compartir: true),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Compartir',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _amarillo)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // No existe el PDF.
    // Si es el entrenador (no puede generar) → mostrar aviso, sin botón.
    if (!widget.puedeGenerar) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _gris,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            Icon(Icons.description_outlined, color: Colors.white38, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text('El usuario aún no ha generado el documento de esta sesión.',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    // Es el dueño → botón generar documento
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _amarillo,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _generandoPdf ? null : _generarDocumento,
        icon: _generandoPdf
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.description, size: 20),
        label: Text(_generandoPdf ? 'Generando documento...' : 'Generar documento',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }

  Widget _pill(String label, int value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Text('$value', style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
          ],
        ),
      );

  Widget _repTile(int index, bool valida, String razon) {
    final color = valida ? Colors.greenAccent : Colors.redAccent;
    final comentario = valida
        ? (razon.isNotEmpty ? razon : 'Técnica correcta, buena ejecución')
        : razon;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
            child: Center(
              child: Text('$index',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valida ? 'Rep válida ✓' : 'Rep no válida ✗',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                if (comentario.isNotEmpty)
                  Text(comentario, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Icon(valida ? Icons.check_circle : Icons.cancel_outlined, color: color, size: 18),
        ],
      ),
    );
  }

  Widget _diagnostico(Map diag) {
    final nivel = diag['nivel_riesgo']?.toString() ?? 'bajo';
    Color riskColor;
    switch (nivel) {
      case 'alto': riskColor = Colors.redAccent; break;
      case 'medio': riskColor = Colors.orange; break;
      default: riskColor = _amarillo;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: riskColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_information, color: riskColor, size: 20),
              const SizedBox(width: 8),
              Text('Riesgo ${nivel.toUpperCase()}',
                  style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          if (diag['posible_lesion'] != null)
            _infoRow('Lesión posible', diag['posible_lesion'].toString()),
          const SizedBox(height: 8),
          if (diag['musculos_en_riesgo'] != null)
            _infoRow('Músculo en riesgo', diag['musculos_en_riesgo'].toString()),
          const SizedBox(height: 12),
          if (diag['descripcion'] != null)
            Text(diag['descripcion'].toString(),
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
          const SizedBox(height: 12),
          if (diag['recomendacion'] != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _amarillo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _amarillo.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: _amarillo, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(diag['recomendacion'].toString(),
                        style: const TextStyle(color: _amarillo, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      );
}