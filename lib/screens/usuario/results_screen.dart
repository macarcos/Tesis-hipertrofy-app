import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:printing/printing.dart';
import '../../services/rep_counter.dart';
import '../../services/ai_coach_service.dart';
import '../../services/pdf_service.dart';
import '../../services/session_service.dart';
import '../../services/r2_service.dart';
import '../../services/offline_store.dart';

// Colores de marca BioSmart
const Color _amarillo = Color(0xFFFFD600);

class ResultsScreen extends StatefulWidget {
  final String ejercicio;
  final ExerciseType tipoEjercicio;
  final List<RepResult> reps;
  final List<Map<String, int>> errorTimestamps; // [{inicio: ms, fin: ms}]
  final String videoPath;
  final AiCoachService aiService;
  final List<String> allErrors; // Lista plana de todos los errores detectados

  const ResultsScreen({
    super.key,
    required this.ejercicio,
    required this.tipoEjercicio,
    required this.reps,
    required this.errorTimestamps,
    required this.videoPath,
    required this.aiService,
    required this.allErrors,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoError = false;
  int _currentErrorIndex = 0;
  MedicalReport? _medicalReport;
  bool _loadingReport = true;

  // Reporte completo de 4 hojas (para el PDF) y estado de generación
  ReporteCompleto? _reporteCompleto;
  bool _generandoPdf = false;

  // ── Estado del PDF (botón "Generar documento") ──────────────────────────
  String? _sesionId;          // ID de la sesión guardada (para actualizar el pdf_url)
  bool _pdfGenerado = false;  // ¿ya se generó y subió el PDF? → mostrar Descargar/Compartir
  bool _subiendoPdf = false;  // mientras genera + sube a R2
  List<int>? _pdfBytes;       // bytes del PDF ya generado (para descargar/compartir sin regenerar)
  bool _previsualizando = false; // mientras abre el visor de PDF

  // Guardamos el messenger capturado en initState (cuando el context es válido).
  ScaffoldMessengerState? _messenger;

  // ── Estado del GUARDADO BLOQUEANTE ──────────────────────────────────────
  // Mientras _guardando == true, la pantalla muestra un overlay con los pasos
  // y NO deja salir (botón X bloqueado). Esto evita el crash de salir y
  // empezar otra sesión mientras la anterior todavía sube el video.
  bool _guardando = true;          // arranca guardando al entrar
  bool _huboError = false;         // hubo un fallo (sin internet, etc.)
  bool _sinInternet = false;       // específicamente, no hay conexión
  bool _guardadoLocal = false;     // se guardó en el teléfono (pendiente de subir)
  String _pasoActual = 'Preparando...';   // texto del paso en curso
  String _pasoVideo = 'pendiente';   // pendiente | subiendo | ok | local | error
  String _pasoDatos = 'pendiente';   // pendiente | guardando | ok | error
  String _pasoIa    = 'pendiente';   // pendiente | generando | ok | sin_internet

  int get validReps => widget.reps.where((r) => r.isValid).length;
  int get invalidReps => widget.reps.where((r) => !r.isValid).length;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _procesarYGuardar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  Future<void> _initVideo() async {
    // Si no hay ruta de video, no intentar cargar
    if (widget.videoPath.isEmpty) {
      if (mounted) setState(() => _videoError = true);
      return;
    }
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        if (mounted) setState(() => _videoError = true);
        return;
      }
      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();
      if (!mounted) return;
      setState(() => _videoReady = true);
    } catch (e) {
      debugPrint('Error al cargar video: $e');
      if (mounted) setState(() => _videoError = true);
    }
  }

  void _seekToError(int index) {
    if (!_videoReady || index >= widget.errorTimestamps.length) return;
    _currentErrorIndex = index;
    final ms = widget.errorTimestamps[index]['inicio']!;
    _videoController!.seekTo(Duration(milliseconds: ms));
    _videoController!.play();
    setState(() {});
  }

  // Convierte milisegundos a formato "minuto:segundo" (ej: 1:07)
  String _formatoTiempo(int ms) {
    final totalSeg = ms ~/ 1000;
    final min = totalSeg ~/ 60;
    final seg = totalSeg % 60;
    return '$min:${seg.toString().padLeft(2, '0')}';
  }

  // ── FLUJO BLOQUEANTE: subir video + guardar datos + IA ──────────────────
  // Se ejecuta al entrar. Mientras corre, _guardando == true y no se puede salir.
  Future<void> _procesarYGuardar() async {
    // 1) Detectar si hay internet (probando un host confiable)
    final bool hayInternet = await _hayInternet();

    // ── PASO 1: VIDEO ─────────────────────────────────────────────────────
    String? videoUrl;
    if (widget.videoPath.isNotEmpty) {
      if (hayInternet) {
        _setPaso(pasoActual: 'Subiendo video a la nube...', pasoVideo: 'subiendo');
        videoUrl = await R2Service.subirVideo(widget.videoPath);
        if (videoUrl == null) {
          // Falló la subida aunque parecía haber internet
          _setPaso(pasoVideo: 'local');
        } else {
          _setPaso(pasoVideo: 'ok');
        }
      } else {
        // Sin internet: el video queda guardado localmente (no se pierde)
        _setPaso(pasoVideo: 'local');
      }
    } else {
      _setPaso(pasoVideo: 'ok'); // no había video que subir
    }

    // ── PASO 2: IA (solo con internet) ────────────────────────────────────
    MedicalReport? report;
    if (hayInternet) {
      _setPaso(pasoActual: 'Generando análisis...', pasoIa: 'generando');
      try {
        report = await widget.aiService.getMedicalReport(
          ejercicio: widget.ejercicio,
          errores: widget.allErrors,
          totalReps: widget.reps.length,
          invalidReps: invalidReps,
        );
        // Reporte completo de 4 hojas (para el PDF) con citas científicas
        _reporteCompleto = await widget.aiService.getReporteCompleto(
          ejercicio: widget.ejercicio,
          errores: widget.allErrors,
          totalReps: widget.reps.length,
          validReps: validReps,
          invalidReps: invalidReps,
        );
        _setPaso(pasoIa: 'ok');
      } catch (_) {
        report = null;
        _setPaso(pasoIa: 'sin_internet');
      }
    } else {
      // Sin internet, la IA no responde (decisión del usuario)
      _setPaso(pasoIa: 'sin_internet');
    }
    if (mounted) setState(() { _medicalReport = report; _loadingReport = false; });

    // ── PASO 3: GUARDAR DATOS ─────────────────────────────────────────────
    if (hayInternet) {
      _setPaso(pasoActual: 'Guardando tu sesión...', pasoDatos: 'guardando');
      final sesionId = await _guardarEnSupabase(report, videoUrl);
      if (sesionId == null) {
        _setPaso(pasoDatos: 'error');
        _terminarConError(sinInternet: false);
        return;
      }
      _sesionId = sesionId; // guardamos el ID para poder subir el PDF luego
      _setPaso(pasoDatos: 'ok');
    } else {
      // ── SIN INTERNET: guardar TODO en el teléfono (local store) ──────────
      // El video y los datos quedan pendientes. Cuando vuelva el internet,
      // se subirán solos (Pieza 2). No se pierde nada.
      _setPaso(pasoActual: 'Guardando en el teléfono...', pasoDatos: 'guardando');
      final repsDetalle = widget.reps.map((r) => {
        'valida': r.isValid,
        'razon': r.reason,
      }).toList();
      final idLocal = await OfflineStore.guardarPendiente(
        ejercicio: widget.ejercicio,
        repsTotales: widget.reps.length,
        repsValidas: validReps,
        repsInvalidas: invalidReps,
        errores: widget.allErrors,
        repsDetalle: repsDetalle,
        erroresTimestamps: widget.errorTimestamps,
        videoPath: widget.videoPath,
      );
      if (idLocal == null) {
        _setPaso(pasoDatos: 'error');
        _terminarConError(sinInternet: true);
        return;
      }
      // Guardado local OK: marcamos como guardado (no es error)
      _setPaso(pasoVideo: 'local', pasoDatos: 'ok');
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _huboError = false;
        _guardadoLocal = true; // para avisar que quedó pendiente de subir
        _pasoActual = 'Guardado en el teléfono';
      });
      return;
    }

    // ── TODO OK (con internet) ────────────────────────────────────────────
    if (!mounted) return;
    setState(() {
      _guardando = false;
      _huboError = false;
      _pasoActual = '¡Sesión guardada!';
    });
  }

  // Detecta internet REAL intentando alcanzar un host (no solo wifi conectado)
  Future<bool> _hayInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Llama al SessionService para guardar. Devuelve el ID de la sesión (o null).
  Future<String?> _guardarEnSupabase(MedicalReport? report, String? videoUrl) async {
    final servicio = SessionService();
    final diagnostico = report == null ? null : {
      'musculos_en_riesgo': report.musculosEnRiesgo,
      'posible_lesion': report.posibleLesion,
      'descripcion': report.descripcion,
      'recomendacion': report.recomendacion,
      'nivel_riesgo': report.nivelRiesgo,
    };

    // Guardamos el reporte completo (para poder regenerar el PDF idéntico luego)
    final reporteComp = _reporteCompleto == null ? null : {
      'resumen_general': _reporteCompleto!.resumenGeneral,
      'analisis_biomecanico': _reporteCompleto!.analisisBiomecanico,
      'musculos_en_riesgo': _reporteCompleto!.musculosEnRiesgo,
      'posible_lesion': _reporteCompleto!.posibleLesion,
      'evidencia_cientifica': _reporteCompleto!.evidenciaCientifica,
      'recomendaciones': _reporteCompleto!.recomendaciones,
      'nivel_riesgo': _reporteCompleto!.nivelRiesgo,
    };

    final repsDetalle = widget.reps.map((r) => {
      'valida': r.isValid,
      'razon': r.reason,
    }).toList();

    return servicio.guardarSesion(
      ejercicio: widget.ejercicio,
      repsTotales: widget.reps.length,
      repsValidas: validReps,
      repsInvalidas: invalidReps,
      errores: widget.allErrors,
      repsDetalle: repsDetalle,
      erroresTimestamps: widget.errorTimestamps,
      diagnosticoIa: diagnostico,
      reporteCompleto: reporteComp,
      videoUrl: videoUrl,
    );
  }

  // Marca que terminó con error (sin internet o fallo de guardado)
  void _terminarConError({required bool sinInternet}) {
    if (!mounted) return;
    setState(() {
      _guardando = false;
      _huboError = true;
      _sinInternet = sinInternet;
      _loadingReport = false;
      _pasoActual = sinInternet
          ? 'Sin conexión a internet'
          : 'No se pudo guardar la sesión';
    });
  }

  // Actualiza los textos de los pasos (helper para no repetir setState)
  void _setPaso({
    String? pasoActual,
    String? pasoVideo,
    String? pasoDatos,
    String? pasoIa,
  }) {
    if (!mounted) return;
    setState(() {
      if (pasoActual != null) _pasoActual = pasoActual;
      if (pasoVideo != null)  _pasoVideo = pasoVideo;
      if (pasoDatos != null)  _pasoDatos = pasoDatos;
      if (pasoIa != null)     _pasoIa = pasoIa;
    });
  }

  // Reintentar todo el proceso (botón cuando hubo error)
  void _reintentar() {
    setState(() {
      _guardando = true;
      _huboError = false;
      _sinInternet = false;
      _pasoActual = 'Reintentando...';
      _pasoVideo = 'pendiente';
      _pasoDatos = 'pendiente';
      _pasoIa = 'pendiente';
    });
    _procesarYGuardar();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  // ── GENERAR el documento: crea el PDF, lo sube a R2 y guarda la URL ───────
  // Después de esto aparecen los botones Previsualizar / Descargar / Compartir.
  Future<void> _generarDocumento() async {
    final reporte = _reporteCompleto ?? ReporteCompleto.respaldo(widget.ejercicio);
    setState(() => _subiendoPdf = true);
    try {
      // 1) Generar los bytes del PDF
      final bytes = await PdfService.generarBytes(
        reporte: reporte,
        ejercicio: widget.ejercicio,
        tipoEjercicio: widget.tipoEjercicio,
        nombreUsuario: 'Usuario BioSmart',
        reps: widget.reps,
        validReps: validReps,
        invalidReps: invalidReps,
        errores: widget.allErrors,
      );
      _pdfBytes = bytes;

      // 2) Subir el PDF a R2 (queda guardado en la nube)
      final pdfUrl = await R2Service.subirPdf(bytes);

      // 3) Guardar la URL del PDF en Supabase (para el historial)
      if (pdfUrl != null && _sesionId != null) {
        await SessionService().actualizarPdfUrl(_sesionId!, pdfUrl);
      }

      if (mounted) {
        setState(() {
          _pdfGenerado = true;
          _subiendoPdf = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pdfUrl != null
                ? 'Documento generado y guardado ✓'
                : 'Documento generado (no se pudo subir a la nube)'),
            backgroundColor: pdfUrl != null ? Colors.green[700] : Colors.orange[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _subiendoPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el documento: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  // ── PREVISUALIZAR el PDF dentro de la app (visor integrado) ───────────────
  // Usa los bytes ya generados (_pdfBytes), así abre al instante sin descargar.
  Future<void> _previsualizarPdf() async {
    // Si por alguna razón no tenemos los bytes, los regeneramos al vuelo.
    List<int>? bytes = _pdfBytes;
    if (bytes == null) {
      final reporte = _reporteCompleto ?? ReporteCompleto.respaldo(widget.ejercicio);
      try {
        bytes = await PdfService.generarBytes(
          reporte: reporte,
          ejercicio: widget.ejercicio,
          tipoEjercicio: widget.tipoEjercicio,
          nombreUsuario: 'Usuario BioSmart',
          reps: widget.reps,
          validReps: validReps,
          invalidReps: invalidReps,
          errores: widget.allErrors,
        );
        _pdfBytes = bytes;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo preparar el documento: $e'),
                backgroundColor: Colors.red[700]),
          );
        }
        return;
      }
    }

    setState(() => _previsualizando = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(bytes!),
        name: 'BioSmart_Reporte.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo previsualizar: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _previsualizando = false);
    }
  }

  // ── DESCARGAR el PDF a la carpeta Descargas ───────────────────────────────
  Future<void> _descargarPdf() async {
    final reporte = _reporteCompleto ?? ReporteCompleto.respaldo(widget.ejercicio);
    setState(() => _generandoPdf = true);
    try {
      final ruta = await PdfService.descargar(
        reporte: reporte,
        ejercicio: widget.ejercicio,
        tipoEjercicio: widget.tipoEjercicio,
        nombreUsuario: 'Usuario BioSmart',
        reps: widget.reps,
        validReps: validReps,
        invalidReps: invalidReps,
        errores: widget.allErrors,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF guardado en Descargas:\n$ruta'),
              backgroundColor: Colors.green[700], duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el PDF: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  // ── COMPARTIR el PDF (correo, whatsapp, etc.) ─────────────────────────────
  Future<void> _compartirPdf() async {
    final reporte = _reporteCompleto ?? ReporteCompleto.respaldo(widget.ejercicio);
    setState(() => _generandoPdf = true);
    try {
      await PdfService.compartir(
        reporte: reporte,
        ejercicio: widget.ejercicio,
        tipoEjercicio: widget.tipoEjercicio,
        nombreUsuario: 'Usuario BioSmart',
        reps: widget.reps,
        validReps: validReps,
        invalidReps: invalidReps,
        errores: widget.allErrors,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo compartir el PDF: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mientras se guarda, bloquea el botón "atrás" del teléfono también
      canPop: !_guardando,
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.ejercicio,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Icon(Icons.close,
              color: _guardando ? Colors.white24 : Colors.white),
          onPressed: _guardando ? null : () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── AVISO: guardado en el teléfono (sin internet) ────────────────
            if (_guardadoLocal) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Guardado en tu teléfono. Se subirá solo cuando vuelva el internet '
                        '(video, repeticiones y análisis).',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── RESUMEN DE REPS ──────────────────────────────────────────────
            _RepSummaryCard(
              total: widget.reps.length,
              valid: validReps,
              invalid: invalidReps,
            ),

            const SizedBox(height: 20),

            // ── DETALLE REP POR REP ──────────────────────────────────────────
            const Text('Detalle de repeticiones',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            ...widget.reps.asMap().entries.map((e) => _RepTile(index: e.key + 1, rep: e.value)),

            const SizedBox(height: 24),

            // ── VIDEO DE LA SESIÓN ───────────────────────────────────────────
            const Text('Video de la sesión',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),

            if (_videoError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.videocam_off, color: Colors.white38, size: 36),
                    SizedBox(height: 10),
                    Text('No se grabó video en esta sesión',
                        style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
                  ],
                ),
              )
            else if (_videoReady && _videoController != null) ...[
              // Duración del video (para verificar que grabó completo)
              Text(
                'Duración del video: ${_formatoTiempo(_videoController!.value.duration.inMilliseconds)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoController!),
                      // Botón play/pausa
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _videoController!.value.isPlaying
                                ? _videoController!.pause()
                                : _videoController!.play();
                          });
                        },
                        child: Container(
                          color: Colors.transparent,
                          width: double.infinity,
                          height: double.infinity,
                          child: Icon(
                            _videoController!.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.white.withOpacity(0.85),
                            size: 60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Barra de progreso del video
              VideoProgressIndicator(
                _videoController!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: _amarillo,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 12),

              // Botones para saltar a cada error (con su minuto)
              if (widget.errorTimestamps.isNotEmpty) ...[
                const Text('Saltar a los errores:',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(widget.errorTimestamps.length, (i) {
                    final isSelected = i == _currentErrorIndex;
                    final ms = widget.errorTimestamps[i]['inicio'] ?? 0;
                    final tiempo = _formatoTiempo(ms);
                    return GestureDetector(
                      onTap: () => _seekToError(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.redAccent : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isSelected ? Colors.red : Colors.grey[800]!),
                        ),
                        child: Text(
                          'Error ${i + 1} · $tiempo',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ]
            else
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: _amarillo),
                ),
              ),

            const SizedBox(height: 24),

            // ── DIAGNÓSTICO MÉDICO IA ────────────────────────────────────────
            const Text('Diagnóstico médico',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            if (_loadingReport)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _amarillo)),
                    SizedBox(width: 12),
                    Text('Analizando tu técnica...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else if (_medicalReport == null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2810),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[800]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 12),
                    Text('¡Técnica perfecta! No hay lesiones detectadas.',
                      style: TextStyle(color: Colors.greenAccent)),
                  ],
                ),
              )
            else
              _MedicalReportCard(report: _medicalReport!),

            const SizedBox(height: 16),

            // ── DOCUMENTO PDF ────────────────────────────────────────────────
            // Primero se muestra "Generar documento". Al tocarlo, genera el PDF,
            // lo sube a R2 y guarda la URL. Recién ahí aparecen
            // Previsualizar (grande) + Descargar/Compartir (pequeños).
            if (!_loadingReport) ...[
              if (!_pdfGenerado)
                // Botón GENERAR DOCUMENTO
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _amarillo,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _subiendoPdf ? null : _generarDocumento,
                    icon: _subiendoPdf
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.description, size: 20),
                    label: Text(
                      _subiendoPdf ? 'Generando documento...' : 'Generar documento',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                  ),
                )
              else
                // Ya generado → Previsualizar (grande) + Descargar/Compartir (pequeños)
                Column(
                  children: [
                    // ── BOTÓN GRANDE: PREVISUALIZAR ──
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _amarillo,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _previsualizando ? null : _previsualizarPdf,
                        icon: _previsualizando
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.visibility, size: 20),
                        label: Text(
                          _previsualizando ? 'Abriendo...' : 'Previsualizar documento',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── BOTONES PEQUEÑOS: DESCARGAR / COMPARTIR ──
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _amarillo,
                                side: const BorderSide(color: _amarillo, width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _generandoPdf ? null : _descargarPdf,
                              icon: _generandoPdf
                                  ? const SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: _amarillo))
                                  : const Icon(Icons.download, size: 18),
                              label: const Text('Descargar',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                                      color: _amarillo)),
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
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _generandoPdf ? null : _compartirPdf,
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('Compartir',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                                      color: _amarillo)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),

          // ── OVERLAY BLOQUEANTE (encima de todo mientras guarda) ──────────
          if (_guardando || _huboError)
            _OverlayGuardado(
              guardando: _guardando,
              huboError: _huboError,
              sinInternet: _sinInternet,
              pasoActual: _pasoActual,
              pasoVideo: _pasoVideo,
              pasoDatos: _pasoDatos,
              pasoIa: _pasoIa,
              onReintentar: _reintentar,
              onSalir: () => Navigator.pop(context),
            ),
        ],
      ),
      ),
    );
  }
}

// ── WIDGETS INTERNOS ───────────────────────────────────────────────────────────

class _RepSummaryCard extends StatelessWidget {
  final int total, valid, invalid;
  const _RepSummaryCard({required this.total, required this.valid, required this.invalid});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text('Completaste $total repeticiones',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatPill(label: 'Válidas', value: valid, color: Colors.greenAccent),
              const SizedBox(width: 12),
              _StatPill(label: 'No válidas', value: invalid, color: Colors.redAccent),
            ],
          ),
          if (invalid > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Solo $valid de $total contaron. Revisa los errores abajo 👇',
              style: TextStyle(color: Colors.orange[300], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
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
}

class _RepTile extends StatelessWidget {
  final int index;
  final RepResult rep;
  const _RepTile({required this.index, required this.rep});

  @override
  Widget build(BuildContext context) {
    final color = rep.isValid ? Colors.greenAccent : Colors.redAccent;
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
              child: Text('$index', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rep.isValid ? 'Rep válida ✓' : 'Rep no válida ✗',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  rep.isValid
                      ? (rep.reason.isNotEmpty ? rep.reason : 'Técnica correcta, buena ejecución')
                      : rep.reason,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Icon(rep.isValid ? Icons.check_circle : Icons.cancel_outlined, color: color, size: 18),
        ],
      ),
    );
  }
}

class _MedicalReportCard extends StatelessWidget {
  final MedicalReport report;
  const _MedicalReportCard({required this.report});

  Color get _riskColor {
    switch (report.nivelRiesgo) {
      case 'alto': return Colors.redAccent;
      case 'medio': return Colors.orange;
      default: return _amarillo;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _riskColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _riskColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_information, color: _riskColor, size: 20),
              const SizedBox(width: 8),
              Text('Riesgo ${report.nivelRiesgo.toUpperCase()}',
                style: TextStyle(color: _riskColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(label: 'Lesión posible', value: report.posibleLesion),
          const SizedBox(height: 8),
          _InfoRow(label: 'Músculo en riesgo', value: report.musculosEnRiesgo),
          const SizedBox(height: 12),
          Text(report.descripcion, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
          const SizedBox(height: 12),
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
                  child: Text(report.recomendacion,
                    style: const TextStyle(color: _amarillo, fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
    ],
  );
}

// ── OVERLAY DE GUARDADO BLOQUEANTE ──────────────────────────────────────────
// Cubre toda la pantalla mientras se sube el video y se guardan los datos.
// No deja salir hasta terminar. Si hay error, muestra reintentar/salir.
class _OverlayGuardado extends StatelessWidget {
  final bool guardando;
  final bool huboError;
  final bool sinInternet;
  final String pasoActual;
  final String pasoVideo;
  final String pasoDatos;
  final String pasoIa;
  final VoidCallback onReintentar;
  final VoidCallback onSalir;

  const _OverlayGuardado({
    required this.guardando,
    required this.huboError,
    required this.sinInternet,
    required this.pasoActual,
    required this.pasoVideo,
    required this.pasoDatos,
    required this.pasoIa,
    required this.onReintentar,
    required this.onSalir,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.92),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ícono/estado principal
                  if (guardando)
                    const SizedBox(
                      width: 54, height: 54,
                      child: CircularProgressIndicator(color: _amarillo, strokeWidth: 3),
                    )
                  else
                    Icon(
                      sinInternet ? Icons.wifi_off : Icons.error_outline,
                      color: sinInternet ? Colors.orangeAccent : Colors.redAccent,
                      size: 56,
                    ),

                  const SizedBox(height: 20),

                  Text(
                    pasoActual,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // Lista de pasos
                  _PasoItem(
                    label: pasoVideo == 'local'
                        ? 'Video guardado en el teléfono'
                        : 'Subir video a la nube',
                    estado: pasoVideo,
                  ),
                  const SizedBox(height: 10),
                  _PasoItem(
                    label: pasoIa == 'sin_internet'
                        ? 'Análisis (necesita internet)'
                        : 'Generar análisis',
                    estado: pasoIa,
                  ),
                  const SizedBox(height: 10),
                  _PasoItem(label: 'Guardar tu sesión', estado: pasoDatos),

                  const SizedBox(height: 28),

                  // Mensaje de ayuda según el caso
                  if (huboError)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (sinInternet ? Colors.orange : Colors.red).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (sinInternet ? Colors.orange : Colors.red).withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        sinInternet
                            ? 'Sin conexión a internet. Tu video quedó guardado en el teléfono y no se perdió. Conéctate e intenta de nuevo.'
                            : 'No se pudo guardar la sesión. Revisa tu conexión e intenta otra vez.',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  if (huboError) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _amarillo,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: onReintentar,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Reintentar',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: onSalir,
                            child: const Text('Salir sin guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Una fila de paso (con su ícono de estado)
class _PasoItem extends StatelessWidget {
  final String label;
  final String estado; // pendiente | subiendo | guardando | generando | ok | local | error | sin_internet
  const _PasoItem({required this.label, required this.estado});

  @override
  Widget build(BuildContext context) {
    Widget icono;
    Color colorTexto = Colors.white70;

    switch (estado) {
      case 'ok':
        icono = const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22);
        break;
      case 'local':
        icono = const Icon(Icons.save_alt, color: Colors.orangeAccent, size: 22);
        break;
      case 'error':
        icono = const Icon(Icons.cancel, color: Colors.redAccent, size: 22);
        break;
      case 'sin_internet':
        icono = const Icon(Icons.cloud_off, color: Colors.white38, size: 22);
        colorTexto = Colors.white38;
        break;
      case 'subiendo':
      case 'guardando':
      case 'generando':
        icono = const SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(color: _amarillo, strokeWidth: 2),
        );
        colorTexto = Colors.white;
        break;
      default: // pendiente
        icono = const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 22);
        colorTexto = Colors.white38;
    }

    return Row(
      children: [
        SizedBox(width: 24, height: 24, child: Center(child: icono)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(color: colorTexto, fontSize: 14)),
        ),
      ],
    );
  }
}