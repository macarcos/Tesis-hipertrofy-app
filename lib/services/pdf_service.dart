import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'rep_counter.dart' show RepResult, ExerciseType;
import 'ai_coach_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// pdf_service.dart — PDF profesional de 4 hojas (diseño BioSmart)
//   Hoja 1: datos generales + barras válidas/inválidas + resumen
//   Hoja 2: riesgos y diagnóstico (con citas)
//   Hoja 3: estadísticas de ángulos + línea de tiempo + tabla de TODAS las reps
//   Hoja 4: referencias científicas + nota
// ══════════════════════════════════════════════════════════════════════════════

const _amarillo  = PdfColor.fromInt(0xFFFFD600);
const _negro     = PdfColor.fromInt(0xFF0A0A0A);
const _grisTexto = PdfColor.fromInt(0xFF444444);
const _grisSuave = PdfColor.fromInt(0xFFF2F2F2);
const _verde     = PdfColor.fromInt(0xFF3E8E41);
const _rojoSuave = PdfColor.fromInt(0xFFD64545);
const _rosaBg    = PdfColor.fromInt(0xFFFBEDED);

// Referencias bibliográficas FIJAS (verificables, la IA no las inventa).
// Cada una con una nota de "para qué se usó".
const List<List<String>> _referencias = [
  [
    'Serafim et al. (2023)',
    'Which resistance training is safest to practice? A systematic review. '
        'J. Orthopaedic Surgery and Research, 18:296.',
    'Epidemiología de lesiones y factores de riesgo en entrenamiento de fuerza.'
  ],
  [
    'Chae et al. (2023)',
    'An artificial intelligence exercise coaching mobile app: RCT in posture '
        'correction. Interactive J. of Medical Research, 12:e37604.',
    'Efectividad del feedback de IA en la mejora de la técnica.'
  ],
  [
    'Ko et al. (2024)',
    'Pose estimation for exercise analysis. IEEE Access, 12.',
    'Detección de errores de postura mediante estimación de pose.'
  ],
  [
    'Liew et al. (2025)',
    'Human pose estimation for exercise monitoring. IJACSA, 16(9).',
    'Validez del cálculo de ángulos articulares en dispositivos móviles.'
  ],
  [
    'Supanich et al. (2023)',
    'Real-time body movement detection. ICACCS, IEEE.',
    'Cuantificación de ángulos articulares y calidad del movimiento.'
  ],
];

class PdfService {
  // Construye el documento PDF (compartido por descargar y compartir).
  static Future<pw.Document> _construir({
    required ReporteCompleto reporte,
    required String ejercicio,
    required ExerciseType tipoEjercicio,
    required String nombreUsuario,
    required List<RepResult> reps,
    required int validReps,
    required int invalidReps,
    required List<String> errores,
  }) async {
    final doc = pw.Document();

    pw.MemoryImage? logo;
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    final fecha = DateTime.now();
    final fechaStr = '${fecha.day}/${fecha.month}/${fecha.year} - '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
    final total = reps.length;
    final eficiencia = total > 0 ? ((validReps / total) * 100).round() : 0;

    // ¿Es ejercicio de piernas? (para mostrar tronco+rodilla o solo un ángulo)
    final esPiernas = tipoEjercicio == ExerciseType.sentadilla ||
        tipoEjercicio == ExerciseType.gobletSquat;

    final colorRiesgo = reporte.nivelRiesgo == 'alto'
        ? _rojoSuave
        : (reporte.nivelRiesgo == 'medio' ? PdfColors.orange : _verde);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (ctx) => _footer(ctx),
      build: (ctx) => [
        // ════════════════ HOJA 1 ════════════════
        _bannerSuperior(logo, fechaStr),
        pw.SizedBox(height: 12),
        _subtitulo('HOJA 1 · DATOS GENERALES'),
        pw.SizedBox(height: 10),
        _filaDatos(nombreUsuario, ejercicio),
        pw.SizedBox(height: 12),
        _cajasStats(total, validReps, invalidReps, eficiencia),
        pw.SizedBox(height: 16),
        _tituloAmarillo('Descripción del ejercicio'),
        _parrafo(reporte.analisisBiomecanico),
        pw.SizedBox(height: 14),
        _tituloAmarillo('Válidas vs inválidas'),
        pw.SizedBox(height: 6),
        _graficoBarras(validReps, invalidReps),
        pw.SizedBox(height: 16),
        _tituloAmarillo('Resumen general'),
        _cajaResumen(reporte.resumenGeneral),

        // ════════════════ HOJA 2 ════════════════
        pw.NewPage(),
        _subtitulo('HOJA 2 · RIESGOS Y DIAGNÓSTICO'),
        pw.SizedBox(height: 10),
        _tarjetaRiesgo(
          titulo: 'Músculos o articulaciones en riesgo',
          etiqueta: reporte.nivelRiesgo.toUpperCase(),
          colorEtiqueta: colorRiesgo,
          contenido: reporte.musculosEnRiesgo,
        ),
        pw.SizedBox(height: 10),
        _tarjetaRiesgo(
          titulo: 'Posible lesión a prevenir',
          etiqueta: '',
          colorEtiqueta: colorRiesgo,
          contenido: reporte.posibleLesion,
        ),
        pw.SizedBox(height: 14),
        _tituloAmarillo('Diagnóstico'),
        _cajaResumen(reporte.analisisBiomecanico),
        pw.SizedBox(height: 14),
        _tituloAmarillo('Recomendaciones'),
        ..._recomendacionesBullets(reporte.recomendaciones),

        // ════════════════ HOJA 3 ════════════════
        pw.NewPage(),
        _subtitulo('HOJA 3 · DETALLE TÉCNICO Y TIEMPOS'),
        pw.SizedBox(height: 10),
        _tituloAmarillo('Estadísticas de la sesión'),
        pw.SizedBox(height: 6),
        _estadisticasAngulos(reps, esPiernas),
        pw.SizedBox(height: 14),
        _tituloAmarillo('Línea de tiempo de la sesión'),
        pw.SizedBox(height: 6),
        _lineaTiempo(reps),
        pw.SizedBox(height: 14),
        _tituloAmarillo('Detalle de todas las repeticiones'),
        pw.SizedBox(height: 6),
        _tablaReps(reps, esPiernas),

        // ════════════════ HOJA 4 ════════════════
        pw.NewPage(),
        _subtitulo('HOJA 4 · REFERENCIAS CIENTÍFICAS'),
        pw.SizedBox(height: 10),
        _parrafo('El análisis y las observaciones de este reporte se fundamentan '
            'en las siguientes fuentes verificadas. Junto a cada una se indica '
            'para qué se utilizó.'),
        pw.SizedBox(height: 10),
        ..._referencias.asMap().entries.map((e) => _itemReferencia(e.key + 1, e.value)),
        pw.SizedBox(height: 16),
        _notaDescargo(),
      ],
    ));

    return doc;
  }

  // ── GENERAR los BYTES del PDF (para subirlo a R2) ─────────────────────────
  static Future<List<int>> generarBytes({
    required ReporteCompleto reporte,
    required String ejercicio,
    required ExerciseType tipoEjercicio,
    required String nombreUsuario,
    required List<RepResult> reps,
    required int validReps,
    required int invalidReps,
    required List<String> errores,
  }) async {
    final doc = await _construir(
      reporte: reporte, ejercicio: ejercicio, tipoEjercicio: tipoEjercicio,
      nombreUsuario: nombreUsuario, reps: reps,
      validReps: validReps, invalidReps: invalidReps, errores: errores,
    );
    return await doc.save();
  }

  // ── DESCARGAR directo a la carpeta de Descargas ───────────────────────────
  static Future<String> descargar({
    required ReporteCompleto reporte,
    required String ejercicio,
    required ExerciseType tipoEjercicio,
    required String nombreUsuario,
    required List<RepResult> reps,
    required int validReps,
    required int invalidReps,
    required List<String> errores,
  }) async {
    final doc = await _construir(
      reporte: reporte, ejercicio: ejercicio, tipoEjercicio: tipoEjercicio,
      nombreUsuario: nombreUsuario, reps: reps,
      validReps: validReps, invalidReps: invalidReps, errores: errores,
    );
    final bytes = await doc.save();

    // Intentar la carpeta de Descargas pública en Android
    Directory? dir;
    try {
      dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) dir = await getExternalStorageDirectory();
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();

    final nombre = 'BioSmart_Reporte_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final ruta = '${dir.path}/$nombre';
    await File(ruta).writeAsBytes(bytes);
    return ruta;
  }

  // ── COMPARTIR (correo, whatsapp, etc.) ────────────────────────────────────
  static Future<void> compartir({
    required ReporteCompleto reporte,
    required String ejercicio,
    required ExerciseType tipoEjercicio,
    required String nombreUsuario,
    required List<RepResult> reps,
    required int validReps,
    required int invalidReps,
    required List<String> errores,
  }) async {
    final doc = await _construir(
      reporte: reporte, ejercicio: ejercicio, tipoEjercicio: tipoEjercicio,
      nombreUsuario: nombreUsuario, reps: reps,
      validReps: validReps, invalidReps: invalidReps, errores: errores,
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'BioSmart_Reporte_$ejercicio.pdf',
    );
  }

  // ════════════════════════ COMPONENTES VISUALES ════════════════════════════

  static pw.Widget _bannerSuperior(pw.MemoryImage? logo, String fecha) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _negro,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(children: [
            if (logo != null) pw.Image(logo, width: 28, height: 28),
            if (logo != null) pw.SizedBox(width: 8),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('BioSmart',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
                      color: _amarillo)),
              pw.Text('AI COACH',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.white,
                      letterSpacing: 2)),
            ]),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Reporte de análisis biomecánico',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
            pw.Text(fecha,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey300)),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _subtitulo(String texto) {
    return pw.Center(
      child: pw.Text('— $texto —',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600,
              letterSpacing: 1)),
    );
  }

  static pw.Widget _tituloAmarillo(String texto) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(children: [
        pw.Container(width: 4, height: 14, color: _amarillo),
        pw.SizedBox(width: 6),
        pw.Text(texto,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold,
                color: _negro)),
      ]),
    );
  }

  static pw.Widget _parrafo(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Text(texto.isEmpty ? 'No disponible.' : texto,
          style: const pw.TextStyle(fontSize: 10.5, color: _grisTexto, lineSpacing: 2),
          textAlign: pw.TextAlign.justify),
    );
  }

  static pw.Widget _filaDatos(String usuario, String ejercicio) {
    pw.Widget caja(String label, String valor) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _grisSuave,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600,
                  letterSpacing: 1)),
              pw.SizedBox(height: 3),
              pw.Text(valor, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold,
                  color: _negro)),
            ]),
          ),
        );
    return pw.Row(children: [caja('USUARIO', usuario), caja('EJERCICIO', ejercicio)]);
  }

  static pw.Widget _cajasStats(int total, int validas, int invalidas, int efic) {
    pw.Widget caja(String valor, String label, PdfColor bg, PdfColor fg) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.symmetric(vertical: 12),
            decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              pw.Text(valor, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: fg)),
              pw.SizedBox(height: 2),
              pw.Text(label, style: pw.TextStyle(fontSize: 8, color: fg, letterSpacing: 1)),
            ]),
          ),
        );
    return pw.Row(children: [
      caja('$total', 'TOTALES', _negro, _amarillo),
      caja('$validas', 'VÁLIDAS', PdfColor.fromInt(0xFFE8F3EC), _verde),
      caja('$invalidas', 'INVÁLIDAS', _rosaBg, _rojoSuave),
      caja('$efic%', 'EFICIENCIA', PdfColor.fromInt(0xFFFBF4E9), PdfColor.fromInt(0xFFBA7517)),
    ]);
  }

  static pw.Widget _graficoBarras(int validas, int invalidas) {
    final maxV = math.max(validas, invalidas).clamp(1, 9999);
    const alturaMax = 70.0;
    pw.Widget barra(int valor, PdfColor color, String label) {
      final h = (valor / maxV) * alturaMax;
      return pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Container(width: 46, height: h < 4 ? 4 : h,
            decoration: pw.BoxDecoration(color: color,
                borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)))),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
      ]);
    }
    return pw.Container(
      height: alturaMax + 24,
      alignment: pw.Alignment.bottomLeft,
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        barra(validas, _verde, '$validas válidas'),
        pw.SizedBox(width: 24),
        barra(invalidas, _rojoSuave, '$invalidas inválidas'),
      ]),
    );
  }

  static pw.Widget _cajaResumen(String texto) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _grisSuave,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(texto.isEmpty ? 'No disponible.' : texto,
          style: const pw.TextStyle(fontSize: 10.5, color: _grisTexto, lineSpacing: 2),
          textAlign: pw.TextAlign.justify),
    );
  }

  static pw.Widget _tarjetaRiesgo({
    required String titulo,
    required String etiqueta,
    required PdfColor colorEtiqueta,
    required String contenido,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _rosaBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE5C5C5)),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(
            child: pw.Text(titulo,
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _negro)),
          ),
          if (etiqueta.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: pw.BoxDecoration(color: colorEtiqueta,
                  borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Text(etiqueta,
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold)),
            ),
        ]),
        pw.SizedBox(height: 5),
        pw.Text(contenido.isEmpty ? 'No disponible.' : contenido,
            style: const pw.TextStyle(fontSize: 10, color: _grisTexto, lineSpacing: 2),
            textAlign: pw.TextAlign.justify),
      ]),
    );
  }

  static List<pw.Widget> _recomendacionesBullets(String texto) {
    // Partimos por puntos o saltos para hacer viñetas
    final partes = texto
        .split(RegExp(r'(?<=\.)\s+|\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (partes.isEmpty) return [_parrafo(texto)];
    return partes.map((p) => pw.Bullet(text: p,
        style: const pw.TextStyle(fontSize: 10.5, color: _grisTexto, lineSpacing: 2))).toList();
  }

  static pw.Widget _estadisticasAngulos(List<RepResult> reps, bool esPiernas) {
    final conDatos = reps.where((r) => r.anguloRodilla > 0).toList();
    pw.Widget caja(String label, String valor) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: pw.BoxDecoration(color: _grisSuave, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600,
                  letterSpacing: 0.5)),
              pw.SizedBox(height: 4),
              pw.Text(valor, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold,
                  color: _negro)),
            ]),
          ),
        );

    int prom(List<int> xs) => xs.isEmpty ? 0 : (xs.reduce((a, b) => a + b) / xs.length).round();
    int minimo(List<int> xs) => xs.isEmpty ? 0 : xs.reduce(math.min);

    if (esPiernas) {
      final troncos = conDatos.where((r) => r.anguloTronco > 0).map((r) => r.anguloTronco).toList();
      final rodillas = conDatos.map((r) => r.anguloRodilla).toList();
      return pw.Row(children: [
        caja('TRONCO PROM.', '${prom(troncos)}°'),
        caja('TRONCO MÍN.', '${minimo(troncos)}°'),
        caja('RODILLA PROM.', '${prom(rodillas)}°'),
        caja('RODILLA MÍN.', '${minimo(rodillas)}°'),
      ]);
    } else {
      final angs = conDatos.map((r) => r.anguloRodilla).toList();
      return pw.Row(children: [
        caja('ÁNGULO PROM.', '${prom(angs)}°'),
        caja('ÁNGULO MÍN.', '${minimo(angs)}°'),
        caja('ÁNGULO MÁX.', '${angs.isEmpty ? 0 : angs.reduce(math.max)}°'),
        caja('REPS', '${reps.length}'),
      ]);
    }
  }

  static pw.Widget _lineaTiempo(List<RepResult> reps) {
    if (reps.isEmpty) {
      return pw.Text('Sin datos de tiempo.', style: const pw.TextStyle(fontSize: 9));
    }
    final t0 = reps.first.timestamp;
    final tFin = reps.last.timestamp;
    final dur = (tFin - t0).clamp(1, 1 << 30);

    // Marcas de cada rep en una barra horizontal
    final marcas = <pw.Widget>[];
    for (final r in reps) {
      final frac = ((r.timestamp - t0) / dur).clamp(0.0, 1.0);
      final color = r.isValid ? _verde : _rojoSuave;
      marcas.add(pw.Container(
        margin: pw.EdgeInsets.only(left: frac * 430),
        width: 4, height: 22, color: color,
      ));
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        height: 28,
        decoration: pw.BoxDecoration(color: _grisSuave, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Stack(children: marcas),
      ),
      pw.SizedBox(height: 4),
      pw.Row(children: [
        _leyenda(_verde, 'Válida'),
        pw.SizedBox(width: 12),
        _leyenda(_rojoSuave, 'Con error'),
      ]),
    ]);
  }

  static pw.Widget _leyenda(PdfColor color, String texto) {
    return pw.Row(children: [
      pw.Container(width: 8, height: 8, color: color),
      pw.SizedBox(width: 4),
      pw.Text(texto, style: const pw.TextStyle(fontSize: 8, color: _grisTexto)),
    ]);
  }

  static String _mmss(int ms, int t0) {
    final s = ((ms - t0) / 1000).round();
    final m = s ~/ 60;
    final ss = s % 60;
    return '$m:${ss.toString().padLeft(2, '0')}';
  }

  static pw.Widget _tablaReps(List<RepResult> reps, bool esPiernas) {
    if (reps.isEmpty) {
      return pw.Text('Sin repeticiones.', style: const pw.TextStyle(fontSize: 9));
    }
    final t0 = reps.first.timestamp;

    final headers = esPiernas
        ? ['Rep', 'Estado', 'Tronco', 'Rodilla', 'Tiempo', 'Observación']
        : ['Rep', 'Estado', 'Ángulo', 'Tiempo', 'Observación'];

    final data = <List<String>>[];
    for (var i = 0; i < reps.length; i++) {
      final r = reps[i];
      final estado = r.isValid ? 'Válida' : 'Error';
      final obs = r.reason.isEmpty ? '—' : r.reason;
      if (esPiernas) {
        data.add([
          '${i + 1}', estado,
          r.anguloTronco > 0 ? '${r.anguloTronco}°' : '—',
          r.anguloRodilla > 0 ? '${r.anguloRodilla}°' : '—',
          _mmss(r.timestamp, t0), obs,
        ]);
      } else {
        data.add([
          '${i + 1}', estado,
          r.anguloRodilla > 0 ? '${r.anguloRodilla}°' : '—',
          _mmss(r.timestamp, t0), obs,
        ]);
      }
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: null,
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _negro),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: _grisTexto),
      cellHeight: 18,
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.center},
    );
  }

  static pw.Widget _itemReferencia(int n, List<String> ref) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('$n. ${ref[0]}',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFFBA7517))),
        pw.SizedBox(height: 2),
        pw.Text(ref[1],
            style: const pw.TextStyle(fontSize: 9.5, color: _grisTexto, lineSpacing: 1.5)),
        pw.SizedBox(height: 2),
        pw.Text('-> ${ref[2]}',
            style: pw.TextStyle(fontSize: 9, color: _verde,
                fontStyle: pw.FontStyle.italic)),
      ]),
    );
  }

  static pw.Widget _notaDescargo() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _grisSuave,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: 'Nota: ',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _negro)),
          pw.TextSpan(
            text: 'Este reporte es un apoyo informativo basado en evidencia científica '
                'y en los ángulos detectados durante la sesión. No constituye un '
                'diagnóstico médico ni confirma la existencia de una lesión. Ante dolor '
                'o molestia, consulte a un profesional de salud certificado.',
            style: const pw.TextStyle(fontSize: 9, color: _grisTexto, lineSpacing: 1.5),
          ),
        ]),
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text('BioSmart AI Coach · Página ${ctx.pageNumber} de ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
    );
  }
}