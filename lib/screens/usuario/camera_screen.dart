import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../services/angle_calculator.dart';
import '../../services/rep_counter.dart';
import '../../services/app_config.dart';
import '../../services/ai_coach_service.dart';
import '../../services/ejercicios_service.dart';
import 'results_screen.dart';

// Colores de marca BioSmart
const Color _amarillo = Color(0xFFFFD600);
const Color _negro = Color(0xFF0A0A0A);

enum ScreenState { esperandoInicio, calibrando, cuentaRegresiva, entrenando }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isReady = false;
  bool _isDisposed = false;

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  bool _isBusy = false;

  List<Pose> _poses = [];
  Size _imageSize = Size.zero;

  ExerciseType _ejercicioSeleccionado = ExerciseType.sentadilla;

  // Ejercicios "en desarrollo" traídos de Supabase (los que el admin agregó
  // pero aún no tienen la detección programada). Se muestran con candado.
  List<EjercicioRemoto> _ejerciciosBloqueados = [];

  // Claves de los 4 ejercicios base que el ADMIN bloqueó desde la web.
  // Aunque la app sabe detectarlos, si el admin los bloqueó, salen con candado.
  Set<String> _basesBloqueadas = {};

  // Claves de los ejercicios que YA funcionan en la app (los 4 programados).
  static const _clavesFuncionando = {
    'sentadilla', 'gobletSquat', 'pressMilitar', 'elevacionLateral',
  };
  ScreenState _appState = ScreenState.esperandoInicio;
  int _conteo = 3;
  Timer? _countdownTimer;

  final FlutterTts _flutterTts = FlutterTts();

  late RepCounter _repCounter;
  String _faseActual = 'Listo';
  String _lastFeedback = '';
  Color _feedbackColor = Colors.white;

  double _liveAngle = 0;
  double _liveFrac = 0;  // valor codoVsHombro de las elevaciones (para calibrar)
  double _liveCodo = 0;  // ángulo del codo del curl (para calibrar)

  // Meta de repeticiones CORRECTAS. Al llegar, termina solo. Default 12 (1-99).
  int _metaReps = 12;
  final TextEditingController _metaCtrl = TextEditingController(text: '12');

  // Auto-pausa: si no detecta persona por un rato, pausa (no cuenta errores).
  bool _pausado = false;
  int _ultimaDeteccionMs = 0;       // última vez que vio una persona
  static const int _msParaPausar = 1500; // 1.5 seg sin ver persona → pausa

  // Control de luz manual (-100 a +100). Combina DOS cosas para más rango:
  //  1) la exposición real del sensor de la cámara
  //  2) un refuerzo de brillo por software en la imagen de ML Kit
  double _luz = 0;              // valor del slider: -100 (oscuro) a +100 (claro)
  double _expMin = -4;          // mínimo de exposición que soporta la cámara
  double _expMax = 4;           // máximo de exposición que soporta la cámara
  double _expActual = 0;        // exposición actual de la cámara (para auto-ajuste)

  // ── Auto-ajuste de luz al inicio ──────────────────────────────────────────
  // Durante los primeros segundos, la app mide el brillo de la imagen y ajusta
  // la exposición SOLA. Después se queda fija; el slider queda para retoques.
  bool _autoAjusteHecho = false;      // ya se hizo el ajuste automático
  int _autoAjusteInicioMs = 0;        // cuándo empezó a medir
  final List<int> _brilloMuestras = []; // muestras de brillo para promediar
  int _ultimoBrillo = 128;            // último brillo promedio medido

  String _lastSpoken = '';
  int _lastSpokenMs = 0;

  DateTime _lastAlarm = DateTime.fromMillisecondsSinceEpoch(0);
  bool _enHold = false;

  final AiCoachService _aiService = AiCoachService(
    userLevel: 'Principiante',
    userWeightKg: 70,
  );

  Timer? _clearWarningTimer;
  final List<String> _allErrors = [];

  bool _grabando = false;
  String _videoPath = '';
  int _grabacionInicioMs = 0;

  // ¿El ejercicio actual es de tren superior (brazos)? (curl o elevaciones)
  bool get _esBrazos =>
      _ejercicioSeleccionado == ExerciseType.pressMilitar ||
      _ejercicioSeleccionado == ExerciseType.elevacionLateral;

  // Modo de medición según el ejercicio
  ModoMedicion get _modoActual {
    switch (_ejercicioSeleccionado) {
      case ExerciseType.pressMilitar:     return ModoMedicion.press;
      case ExerciseType.elevacionLateral: return ModoMedicion.elevacion;
      case ExerciseType.sentadilla:
      case ExerciseType.gobletSquat:      return ModoMedicion.piernas;
    }
  }

  @override
  void initState() {
    super.initState();
    _repCounter = RepCounter(exercise: _ejercicioSeleccionado);
    _initVoice();
    _initCamera();
    _cargarEjerciciosBloqueados();
  }

  // Carga de Supabase los ejercicios que NO están entre los 4 que funcionan
  // (o que están marcados como no disponibles). Se mostrarán con candado.
  Future<void> _cargarEjerciciosBloqueados() async {
    final remotos = await EjerciciosService().obtenerEjercicios();
    // Ejercicios extra (no son de los 4 base) → siempre con candado
    final bloqueados = remotos.where((e) =>
        !_clavesFuncionando.contains(e.clave)).toList();
    // Ejercicios base que el admin bloqueó desde la web (disponible = false)
    final basesBloq = remotos
        .where((e) => _clavesFuncionando.contains(e.clave) && !e.disponible)
        .map((e) => e.clave)
        .toSet();
    if (mounted) setState(() {
      _ejerciciosBloqueados = bloqueados;
      _basesBloqueadas = basesBloq;
    });
  }

  Future<void> _initVoice() async {
    await _flutterTts.setLanguage('es-ES');
    await _flutterTts.setSpeechRate(0.65);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;
      final camera = _cameras!.length > 1 ? _cameras![1] : _cameras![0];
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,  // máxima detección (si traba, baja a medium)
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (!mounted) return;
      await _controller!.setFocusMode(FocusMode.auto);
      // Leer el rango de exposición que soporta esta cámara (para el slider)
      try {
        _expMin = await _controller!.getMinExposureOffset();
        _expMax = await _controller!.getMaxExposureOffset();
        debugPrint('CAMARA | Exposición soportada: min=$_expMin, max=$_expMax');
        // Si la cámara NO soporta cambio de exposición (min=max=0), avisamos.
        if (_expMin == 0 && _expMax == 0) {
          debugPrint('CAMARA | ⚠️ Esta cámara NO soporta cambiar la exposición (frontal limitada)');
        }
      } catch (e) {
        _expMin = -4; _expMax = 4;
        debugPrint('CAMARA | No se pudo leer exposición: $e');
      }
      // Arrancamos con la exposición NORMAL de la cámara (offset 0), sin
      // forzar ningún boost de luz al abrir. El slider parte de 0 = normal.
      try {
        await _controller!.setExposureMode(ExposureMode.auto);
        await _controller!.setExposureOffset(0);
        _expActual = 0;   // punto de partida = cámara tal cual (normal)
        _luz = 0; // el slider arranca en 0
        // El auto-ajuste NO se hace aquí (al abrir), sino durante la calibración,
        // cuando el usuario ya está en su posición de entrenamiento.
        _autoAjusteHecho = true; // desactivado hasta que empiece la serie
      } catch (_) {
        try { await _controller!.setExposureMode(ExposureMode.auto); } catch (_) {}
      }
      setState(() => _isReady = true);
      _controller!.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint('BIOSMART | Error cámara: $e');
    }
  }

  bool _esPersonaReal(Pose pose) {
    final lm = pose.landmarks;

    // Para ejercicios de BRAZOS: validar con el HOMBRO (de pie, siempre visible).
    if (_esBrazos) {
      final shoL = lm[PoseLandmarkType.leftShoulder];
      final shoR = lm[PoseLandmarkType.rightShoulder];
      if (shoL == null && shoR == null) return false;
      final confSho = ((shoL?.likelihood ?? 0) > (shoR?.likelihood ?? 0))
          ? shoL!.likelihood : shoR!.likelihood;
      return confSho > 0.2;
    }

    // Sentadilla / goblet: validar con la CADERA (igual que siempre).
    final hipL = lm[PoseLandmarkType.leftHip];
    final hipR = lm[PoseLandmarkType.rightHip];
    if (hipL == null && hipR == null) return false;
    final conf = ((hipL?.likelihood ?? 0) > (hipR?.likelihood ?? 0))
        ? hipL!.likelihood : hipR!.likelihood;
    return conf > 0.2;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _isDisposed) return;
    _isBusy = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) { _isBusy = false; return; }

      final poses = await _poseDetector.processImage(inputImage);

      if (_isDisposed) return;

      // ── Auto-ajuste de luz guiado por la confianza de detección ───────────
      // IMPORTANTE: solo se ajusta cuando el usuario YA está en posición
      // (fase calibrando o cuenta regresiva), NO al abrir la cámara (ahí está
      // pegado a la pantalla seleccionando y el ajuste saldría mal calibrado).
      // El auto-ajuste corre desde que estás en posición (calibrando) y puede
      // continuar los primeros segundos de entrenamiento, hasta completar sus
      // 5 segundos de ajuste. Así le da tiempo aunque la cuenta pase rápido.
      final enPosicion = _appState == ScreenState.calibrando ||
                         _appState == ScreenState.cuentaRegresiva ||
                         _appState == ScreenState.entrenando;
      if (!_autoAjusteHecho && enPosicion) {
        double conf = 0;
        bool hayCuerpo = false;
        if (poses.isNotEmpty) {
          conf = _confianzaPromedio(poses.first);
          hayCuerpo = _esPersonaReal(poses.first);
        }
        _autoAjustarPorConfianza(conf, _ultimoBrillo, hayCuerpo);
      }

      if (mounted) {
        setState(() {
          _poses = poses;
          if (_imageSize == Size.zero) {
            _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          }
        });
      }

      if (_appState == ScreenState.calibrando) {
        if (poses.isNotEmpty && _esPersonaReal(poses.first)) {
          _iniciarCuentaRegresiva();
        } else {
          if (mounted) setState(() => _faseActual = 'Ubícate en el encuadre');
        }
        return;
      }

      if (_appState == ScreenState.entrenando) {
        final hayPersona = poses.isNotEmpty && _esPersonaReal(poses.first);
        final ahoraMs = DateTime.now().millisecondsSinceEpoch;

        if (hayPersona) {
          _ultimaDeteccionMs = ahoraMs;
          // Si estaba pausado y volvió la persona → reanudar
          if (_pausado) {
            if (mounted) setState(() {
              _pausado = false;
              _faseActual = 'Reanudando...';
            });
          }
        } else {
          // No hay persona: si pasó el tiempo sin verla → pausar
          if (!_pausado && _ultimaDeteccionMs > 0 &&
              (ahoraMs - _ultimaDeteccionMs) > _msParaPausar) {
            if (mounted) setState(() {
              _pausado = true;
              _faseActual = 'Pausado';
            });
          }
          return; // sin persona, no procesamos nada (no cuenta errores)
        }

        // Si está pausado, no procesamos hasta que se confirme la persona
        if (_pausado) return;

        final angles = AngleCalculator.extract(poses.first, modo: _modoActual);
        if (angles == null) return;

        if (mounted) setState(() {
          _liveAngle = angles.torsoSquat;
          _liveFrac = angles.codoVsHombroFrac;
          _liveCodo = angles.elbow;
        });

        final currentMs = DateTime.now().millisecondsSinceEpoch;
        final result = _repCounter.process(angles, currentMs);

        if (_isDisposed) return;
        if (mounted) setState(() => _faseActual = result.phase);

        _enHold = result.holdSecondsLeft != null && !result.repCompleted;

        // ── Voz guiada (2, 1, Suba/Baje) ──────────────────────────────────
        if (result.voice != null && result.voice != _lastSpoken) {
          final isNumber = result.voice == '2' || result.voice == '1';
          final now = DateTime.now().millisecondsSinceEpoch;
          final enoughTime = (now - _lastSpokenMs) > (isNumber ? 800 : 300);
          if (enoughTime) {
            _lastSpoken = result.voice!;
            _lastSpokenMs = now;
            _flutterTts.speak(result.voice!);
          }
        }

        if (result.repCompleted) _lastSpoken = '';

        // ── Aviso de postura en pantalla ──────────────────────────────────
        if (result.liveWarning != null) {
          if (mounted) {
            setState(() {
              _lastFeedback  = result.liveWarning!;
              _feedbackColor = Colors.redAccent;
            });
          }

          // Voz del warning REAL del ejercicio (sin el ⚠️), no texto fijo.
          if (!_enHold) {
            final now = DateTime.now();
            if (now.difference(_lastAlarm).inSeconds >= 5) {
              _lastAlarm = now;
              final textoVoz = result.liveWarning!.replaceAll('⚠️', '').trim();
              if (textoVoz.isNotEmpty) _flutterTts.speak(textoVoz);
            }
          }

          _clearWarningTimer?.cancel();
          _clearWarningTimer = Timer(const Duration(milliseconds: 1000), () {
            if (mounted && !_isDisposed) {
              setState(() { _lastFeedback = ''; _feedbackColor = Colors.white; });
            }
          });

        } else {
          _clearWarningTimer?.cancel();
          _clearWarningTimer = Timer(const Duration(milliseconds: 600), () {
            if (mounted && !_isDisposed && _lastFeedback.contains('⚠️')) {
              setState(() { _lastFeedback = ''; _feedbackColor = Colors.white; });
            }
          });
        }

        // ── Rep completada ────────────────────────────────────────────────
        if (result.repCompleted) {
          _clearWarningTimer?.cancel();
          _enHold = false;

          if (result.lastRepErrors.isNotEmpty) {
            _allErrors.addAll(result.lastRepErrors);
            final msgPantalla = result.lastRepErrors.join(' · ');

            // Voz: para sentadilla/goblet priorizamos rodilla/torso.
            // Para brazos decimos el primer error tal cual.
            String vozCorta;
            if (_esBrazos) {
              vozCorta = result.lastRepErrors.first;
            } else {
              final errorRodilla = result.lastRepErrors
                  .where((e) => e.contains('No bajó') || e.contains('Subió muy rápido'))
                  .firstOrNull;
              final errorTorso = result.lastRepErrors
                  .where((e) => e.contains('Espalda'))
                  .firstOrNull;
              if (errorRodilla != null) {
                vozCorta = errorRodilla.contains('No bajó')
                    ? 'No bajó suficiente' : 'Subió muy rápido';
              } else if (errorTorso != null) {
                vozCorta = 'Espalda muy inclinada';
              } else {
                vozCorta = result.lastRepErrors.first;
              }
            }

            if (mounted) setState(() {
              _lastFeedback = '✗ Rep inválida — $msgPantalla';
              _feedbackColor = Colors.redAccent;
            });
            _flutterTts.speak('Repetición inválida. $vozCorta');

          } else {
            if (mounted) setState(() {
              _lastFeedback =
                  '✓ ¡Rep válida! ${_repCounter.validReps} de $_metaReps';
              _feedbackColor = Colors.greenAccent;
            });
            _flutterTts.speak('Repetición válida');

            // ¿Llegó a la meta de reps correctas? → terminar solo
            if (_repCounter.validReps >= _metaReps) {
              _flutterTts.speak('¡Meta alcanzada! $_metaReps repeticiones');
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && !_isDisposed) _terminarSerie();
              });
              return;
            }
          }

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_isDisposed) {
              setState(() { _lastFeedback = ''; _feedbackColor = Colors.white; });
            }
          });
        }
      }
    } catch (e) {
      debugPrint('BIOSMART | Error frame: $e');
    } finally {
      _isBusy = false;
    }
  }

  void _iniciarCuentaRegresiva() {
    if (_appState == ScreenState.cuentaRegresiva ||
        _appState == ScreenState.entrenando) return;
    setState(() { _appState = ScreenState.cuentaRegresiva; _conteo = 3; });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) { timer.cancel(); return; }
      if (_conteo > 0) {
        if (mounted) setState(() => _faseActual = 'Comenzamos en $_conteo...');
        _flutterTts.speak(_conteo.toString());
        _conteo--;
      } else {
        timer.cancel();
        final primeraInstruccion = _esBrazos ? 'Suba' : 'Baje';
        if (mounted) setState(() {
          _appState = ScreenState.entrenando;
          _faseActual = primeraInstruccion;
        });
        _flutterTts.speak('Comienza. $primeraInstruccion');
      }
    });
  }

  Future<void> _iniciarGrabacion() async {
    if (_grabando) return;
    // Si el usuario apagó la grabación en su perfil, no grabamos.
    if (!AppConfig.grabarVideo) {
      debugPrint('BIOSMART | Grabación desactivada por el usuario');
      return;
    }
    try {
      final bool iniciado = await FlutterScreenRecording.startRecordScreen(
        'biosmart_${DateTime.now().millisecondsSinceEpoch}',
        titleNotification: 'BioSmart grabando',
        messageNotification: 'Analizando tu técnica',
      );
      _grabando = iniciado;
      if (iniciado) _grabacionInicioMs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('BIOSMART | Grabación de pantalla: $iniciado');
    } catch (e) {
      debugPrint('BIOSMART | No se pudo grabar pantalla: $e');
      _grabando = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;
    final camera  = _controller!.description;
    final isFront = camera.lensDirection == CameraLensDirection.front;
    final sensor  = camera.sensorOrientation;
    final int rotDeg = isFront ? (360 - sensor) % 360 : sensor;

    final InputImageRotation rotation;
    switch (rotDeg) {
      case 0:   rotation = InputImageRotation.rotation0deg;   break;
      case 90:  rotation = InputImageRotation.rotation90deg;  break;
      case 180: rotation = InputImageRotation.rotation180deg; break;
      case 270: rotation = InputImageRotation.rotation270deg; break;
      default:  rotation = InputImageRotation.rotation90deg;
    }

    if (image.planes.length < 3) return null;
    return InputImage.fromBytes(
      bytes: _yuv420ToNv21(image),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  // Auto-ajuste de exposición guiado por la CONFIANZA de detección de ML Kit.
  // Durante ~6 segundos prueba ajustes y mide con qué confianza detecta el
  // cuerpo. En cuanto la confianza llega a 0.7, se queda con ese ajuste. Si no
  // lo logra en 6 seg, se queda con el mejor ajuste encontrado. Después, el
  // slider manual queda libre y no choca (el automático ya terminó).
  static const double _confianzaObjetivo = 0.7;
  double _mejorConfianza = 0;      // mejor confianza vista hasta ahora
  double _mejorExp = 0;            // exposición que dio la mejor confianza
  double _mejorLuz = 0;            // brillo software que dio la mejor confianza
  int _ultimoAjusteMs = 0;         // para no cambiar la exposición muy seguido

  void _autoAjustarPorConfianza(double confianza, int brilloPromedio, bool hayCuerpo) {
    if (_autoAjusteHecho) return;

    // Esperar a que la cámara detecte el cuerpo. Sin cuerpo en el encuadre,
    // no tiene sentido calibrar. Apenas lo detecta, arranca el ajuste.
    if (!hayCuerpo) return;

    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (_autoAjusteInicioMs == 0) {
      _autoAjusteInicioMs = ahora;
      _ultimoAjusteMs = 0; // ajustar de inmediato
      debugPrint('AUTO-LUZ | Cuerpo detectado, empieza ajuste (5 seg)');
    }

    // Guardar el mejor ajuste visto (el que dio más confianza)
    if (confianza > _mejorConfianza) {
      _mejorConfianza = confianza;
      _mejorExp = _expActual;
      _mejorLuz = _luz;
    }

    // Si ya detecta muy bien, terminamos antes
    if (confianza >= _confianzaObjetivo) {
      _autoAjusteHecho = true;
      debugPrint('AUTO-LUZ | Objetivo logrado. conf=$confianza, _luz=$_luz');
      return;
    }

    // Si pasaron 5 segundos desde que detectó el cuerpo, nos quedamos con el mejor
    if (ahora - _autoAjusteInicioMs >= 5000) {
      if (mounted) setState(() => _luz = _mejorLuz);
      _controller?.setExposureOffset(_mejorExp).catchError((_) => 0.0);
      _expActual = _mejorExp;
      _autoAjusteHecho = true;
      debugPrint('AUTO-LUZ | Fin. Mejor conf=$_mejorConfianza, _luz=$_mejorLuz');
      return;
    }

    // Cada 500 ms, probar un ajuste de brillo por software (notorio) y exposición
    if (ahora - _ultimoAjusteMs >= 500) {
      _ultimoAjusteMs = ahora;
      const objetivoBrillo = 130;
      final diferencia = objetivoBrillo - brilloPromedio;

      // Brillo por software (más notorio ahora)
      double pasoLuz = (diferencia / 128.0) * 80;
      double nuevaLuz = (_luz + pasoLuz).clamp(-100.0, 100.0);
      if (mounted) setState(() => _luz = nuevaLuz);

      // Exposición de cámara (por si la soporta)
      double pasoExp = (diferencia / 128.0) * _expMax * 0.6;
      _expActual = (_expActual + pasoExp).clamp(_expMin, _expMax);
      _controller?.setExposureOffset(_expActual).catchError((_) => 0.0);

      debugPrint('AUTO-LUZ | ajustando brillo=$brilloPromedio conf=$confianza _luz=$nuevaLuz');
    }
  }

  // Confianza promedio de los puntos clave del cuerpo (0 a 1).
  // Sirve para saber si ML Kit está detectando bien con la luz actual.
  double _confianzaPromedio(Pose pose) {
    final lm = pose.landmarks;
    final claves = [
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
    ];
    double suma = 0;
    int n = 0;
    for (final k in claves) {
      final p = lm[k];
      if (p != null) { suma += p.likelihood; n++; }
    }
    return n > 0 ? suma / n : 0;
  }

  // Potencia (base^exp) para la curva gamma. Usa la de dart:math.
  double _pow(double base, double exp) => math.pow(base, exp).toDouble();

  Uint8List _yuv420ToNv21(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final w = image.width, h = image.height;
    final ySize = w * h;
    final nv21 = Uint8List(ySize + (w ~/ 2) * (h ~/ 2) * 2);

    int yMin = 255, yMax = 0;
    int sumaBrillo = 0, cuentaBrillo = 0;
    for (int row = 0; row < h; row += 4) {
      final rs = row * yPlane.bytesPerRow;
      for (int col = 0; col < w; col += 4) {
        final v = yPlane.bytes[rs + col];
        if (v < yMin) yMin = v;
        if (v > yMax) yMax = v;
        sumaBrillo += v;
        cuentaBrillo++;
      }
    }
    final range = yMax - yMin;
    final int brilloPromedio = cuentaBrillo > 0 ? (sumaBrillo ~/ cuentaBrillo) : 128;
    _ultimoBrillo = brilloPromedio; // guardado para el auto-ajuste por confianza
    // Auto-contraste cuando la imagen tiene POCO CONTRASTE (rango estrecho),
    // que es justo lo que pasa con luz desde arriba: los brazos quedan en sombra
    // y se confunden con el fondo. Estiramos el rango para separarlos.
    // Antes solo se activaba si estaba oscura; ahora también si el contraste es bajo.
    final bool bajoContraste = range > 5 && range < 130;

    // Refuerzo de brillo por software según el slider de luz (-100..+100).
    // Suavizado: factores moderados para que subir/bajar NO queme ni apague la
    // imagen (eso hacía que ML Kit perdiera la detección). Mejor poco y estable.
    final int brilloSoftware = (_luz * 1.0).round();

    // Factor multiplicador moderado.
    // slider +100 → x1.5 (más claro, sin quemar); slider -100 → x0.6
    final double factorLuz = _luz >= 0
        ? 1.0 + (_luz / 100) * 0.5
        : 1.0 + (_luz / 100) * 0.4;

    // Realce de contraste ADAPTATIVO: si la imagen está lavada (mucho brillo),
    // subimos más el contraste para separar el cuerpo del fondo del mismo color.
    // Si está normal, contraste suave. Esto ataca el problema de "todo igual".
    final double factorContraste = brilloPromedio > 165
        ? 1.35   // imagen muy clara/lavada → más contraste para separar
        : (brilloPromedio > 140 ? 1.25 : 1.18); // normal → contraste suave

    // ── REALCE PARA POCA LUZ (lo más importante para el gym oscuro) ──────────
    // Si la imagen está oscura (brillo bajo), aplicamos una curva GAMMA que
    // aclara MUCHO las zonas oscuras sin quemar las claras. Es la técnica que
    // usan las cámaras en "modo noche". Cuanto más oscura, más fuerte el realce.
    // Precalculamos una tabla de 256 valores (rápido: se calcula una vez por frame).
    final Uint8List tablaRealce = Uint8List(256);
    // gamma < 1 aclara; a menor brillo, gamma más agresivo (más aclarado)
    double gamma;
    if (brilloPromedio < 60)       gamma = 0.45; // muy oscuro → aclarar fuerte
    else if (brilloPromedio < 100) gamma = 0.60; // oscuro → aclarar bastante
    else if (brilloPromedio < 140) gamma = 0.80; // medio → aclarar un poco
    else                           gamma = 1.0;  // ya hay luz → no tocar
    for (int i = 0; i < 256; i++) {
      // curva gamma: salida = 255 * (i/255)^gamma
      double norm = i / 255.0;
      double out = 255.0 * _pow(norm, gamma);
      // aplicar también el contraste adaptativo alrededor del medio
      out = ((out - 128) * factorContraste) + 128;
      // aplicar el ajuste manual del slider (multiplica + suma)
      if (_luz != 0) {
        out = out * factorLuz + brilloSoftware;
      }
      tablaRealce[i] = out.round().clamp(0, 255);
    }

    int yi = 0;
    for (int row = 0; row < h; row++) {
      final rs = row * yPlane.bytesPerRow;
      for (int col = 0; col < w; col++) {
        int val = yPlane.bytes[rs + col];
        // 1) Auto-contraste: estira el rango si el contraste es bajo
        if (bajoContraste) {
          val = (((val - yMin) * 255) / range).round().clamp(0, 255);
        }
        // 2) Aplicar la tabla de realce (gamma + contraste + slider) de un golpe
        nv21[yi++] = tablaRealce[val];
      }
    }

    int uvi = ySize;
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        nv21[uvi++] = vPlane.bytes[(row * vPlane.bytesPerRow + col).toInt()];
        nv21[uvi++] = uPlane.bytes[(row * uPlane.bytesPerRow + col).toInt()];
      }
    }
    return nv21;
  }

  void _iniciarSerie() async {
    // Validar la meta: si quedó vacía o inválida, usar 12 por defecto
    final n = int.tryParse(_metaCtrl.text);
    if (n == null || n < 1 || n > 99) {
      _metaReps = 12;
      _metaCtrl.text = '12';
    } else {
      _metaReps = n;
    }
    await _iniciarGrabacion();
    if (!mounted) return;
    AngleCalculator.resetCurl();  // reinicia el brazo fijado del curl
    // Reiniciar el auto-ajuste de luz: ahora medirá cuando ya estás en posición
    // (durante la calibración), NO cuando estabas pegado a la cámara.
    _autoAjusteHecho = false;
    _autoAjusteInicioMs = 0;
    _mejorConfianza = 0;
    _mejorExp = _expActual;
    _mejorLuz = _luz;
    setState(() {
      _appState = ScreenState.calibrando;
      _repCounter = RepCounter(exercise: _ejercicioSeleccionado);
      _allErrors.clear();
      _lastFeedback = '';
      _liveAngle = 0;
      _enHold = false;
      _pausado = false;
      _ultimaDeteccionMs = 0;
      _faseActual = 'Buscando sujeto...';
    });
  }

  Future<void> _terminarSerie() async {
    _countdownTimer?.cancel();
    _clearWarningTimer?.cancel();
    _flutterTts.stop();

    if (_grabando) {
      try {
        final String path = await FlutterScreenRecording.stopRecordScreen;
        _videoPath = path;
        _grabando = false;
        debugPrint('BIOSMART | Video guardado en: $_videoPath');
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        debugPrint('BIOSMART | Error al detener grabación: $e');
        _videoPath = '';
      }
    }

    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}

    final List<Map<String, int>> erroresVideo = [];
    for (final e in _repCounter.errorTimestamps) {
      final inicioRel = (e['inicio'] ?? 0) - _grabacionInicioMs;
      final finRel = (e['fin'] ?? 0) - _grabacionInicioMs;
      erroresVideo.add({
        'inicio': inicioRel < 0 ? 0 : inicioRel,
        'fin': finRel < 0 ? 0 : finRel,
      });
    }

    _isDisposed = true;
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          ejercicio: _nombreEjercicio(_ejercicioSeleccionado),
          tipoEjercicio: _ejercicioSeleccionado,
          reps: _repCounter.reps,
          errorTimestamps: erroresVideo,
          videoPath: _videoPath,
          aiService: _aiService,
          allErrors: _allErrors,
        ),
      ),
    );
  }

  String _nombreEjercicio(ExerciseType t) {
    switch (t) {
      case ExerciseType.sentadilla:       return 'Sentadilla';
      case ExerciseType.gobletSquat:      return 'Sentadilla con Mancuerna';
      case ExerciseType.pressMilitar:     return 'Press Militar';
      case ExerciseType.elevacionLateral: return 'Elevaciones Laterales';
    }
  }

  // Clave del ejercicio (la misma que está en Supabase) para cada tipo
  String _claveDeType(ExerciseType t) {
    switch (t) {
      case ExerciseType.sentadilla:       return 'sentadilla';
      case ExerciseType.gobletSquat:      return 'gobletSquat';
      case ExerciseType.pressMilitar:     return 'pressMilitar';
      case ExerciseType.elevacionLateral: return 'elevacionLateral';
    }
  }

  // Indicación de cómo poner la cámara según el ejercicio
  String _vistaEjercicio(ExerciseType t) {
    switch (t) {
      case ExerciseType.pressMilitar:     return '📷 Siéntate de FRENTE a la cámara';
      case ExerciseType.elevacionLateral: return '📷 Ponte de FRENTE a la cámara';
      case ExerciseType.sentadilla:
      case ExerciseType.gobletSquat:      return '📷 Ponte de PERFIL a la cámara';
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    _clearWarningTimer?.cancel();
    _flutterTts.stop();
    if (_grabando) {
      try { FlutterScreenRecording.stopRecordScreen; } catch (_) {}
      _grabando = false;
    }
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        _controller!.stopImageStream();
      }
    } catch (_) {}
    _controller?.dispose();
    _poseDetector.close();
    _metaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: _negro,
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _amarillo),
            SizedBox(height: 16),
            Text('Iniciando sensores...', style: TextStyle(color: Colors.white70)),
          ],
        )),
      );
    }

    return Scaffold(
      backgroundColor: _negro,
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_controller!),
                  if (_poses.isNotEmpty &&
                      _imageSize != Size.zero &&
                      _appState != ScreenState.esperandoInicio)
                    CustomPaint(
                      painter: PosePainter(
                        poses: _poses,
                        imageSize: _imageSize,
                        skeletonColor: _feedbackColor == Colors.redAccent
                            ? Colors.redAccent : _amarillo,
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (_appState == ScreenState.cuentaRegresiva)
            Center(
              child: Text('$_conteo',
                  style: const TextStyle(
                      fontSize: 150, fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: _amarillo, blurRadius: 30)])),
            ),

          // ── OVERLAY DE PAUSA (cuando no detecta persona) ──────────────────
          if (_appState == ScreenState.entrenando && _pausado)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.pause_circle_filled, color: _amarillo, size: 90),
                    SizedBox(height: 20),
                    Text('PAUSADO',
                        style: TextStyle(
                            color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    SizedBox(height: 10),
                    Text('Vuelve al encuadre para continuar',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Tu progreso está guardado',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 14)),
                  ],
                ),
              ),
            ),

          // ── ÁNGULO GRANDE para calibrar las elevaciones (visible de lejos) ──
          if (_appState == ScreenState.entrenando &&
              _ejercicioSeleccionado == ExerciseType.elevacionLateral)
            Positioned(
              top: 90,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _liveFrac >= elev_anguloArriba && _liveFrac <= elev_anguloMuyAlto
                          ? Colors.greenAccent
                          : (_liveFrac > elev_anguloMuyAlto
                              ? Colors.redAccent
                              : Colors.white54),
                      width: 3,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_liveFrac.round()}°',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: _liveFrac >= elev_anguloArriba && _liveFrac <= elev_anguloMuyAlto
                              ? Colors.greenAccent
                              : (_liveFrac > elev_anguloMuyAlto
                                  ? Colors.redAccent
                                  : Colors.white),
                          shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                      Text(
                        _liveFrac > elev_anguloMuyAlto
                            ? 'MUY ARRIBA'
                            : (_liveFrac >= elev_anguloArriba
                                ? 'CORRECTO'
                                : (_liveFrac < elev_anguloAbajo ? 'ABAJO' : 'SUBE MÁS')),
                        style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold,
                          color: Colors.white, letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── ÁNGULOS GRANDES para calibrar el PRESS MILITAR (visible de lejos) ──
          // Y = ángulo del codo (arriba/abajo). X = apertura de muñecas.
          if (_appState == ScreenState.entrenando &&
              _ejercicioSeleccionado == ExerciseType.pressMilitar)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Y = ángulo del codo (grande)
                      Text(
                        'Y = ${_liveCodo.round()}',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: _liveCodo >= press_codoArriba
                              ? Colors.greenAccent
                              : (_liveCodo <= press_codoAbajo
                                  ? Colors.cyanAccent
                                  : Colors.white),
                          shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                      // X = apertura de muñecas (grande)
                      Text(
                        'X = ${_liveFrac.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: _liveFrac > (_liveCodo >= press_codoArriba
                                  ? press_aperturaArriba
                                  : (_liveCodo <= press_codoAbajo
                                      ? press_aperturaAbajo
                                      : press_aperturaMedio))
                              ? Colors.redAccent       // muy abierto para su zona
                              : Colors.greenAccent,    // bien
                          shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── CONTROL DE BRILLO MANUAL de la cámara (lado derecho) ──────────
          if (_appState == ScreenState.esperandoInicio ||
              _appState == ScreenState.entrenando ||
              _appState == ScreenState.calibrando ||
              _appState == ScreenState.cuentaRegresiva)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wb_sunny, color: _amarillo, size: 20),
                      const SizedBox(height: 4),
                      Text('${_luz.round()}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      SizedBox(
                        height: 180,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: _amarillo,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: _amarillo,
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            ),
                            child: Slider(
                              min: -100,
                              max: 100,
                              value: _luz,
                              onChanged: (v) async {
                                setState(() => _luz = v);
                                // El usuario tomó control manual → detener el
                                // auto-ajuste para que no choquen entre sí.
                                _autoAjusteHecho = true;
                                // 0 = exposición NORMAL de la cámara (offset 0).
                                // +100 → sube hasta el máximo que soporta la cámara.
                                // -100 → baja hasta el mínimo (más oscuro).
                                try {
                                  double exp;
                                  if (v >= 0) {
                                    exp = (v / 100) * _expMax;
                                  } else {
                                    exp = (v / 100) * _expMin.abs();
                                  }
                                  _expActual = exp;
                                  await _controller?.setExposureOffset(exp);
                                } catch (_) {}
                              },
                            ),
                          ),
                        ),
                      ),
                      const Icon(Icons.nightlight_round, color: Colors.white54, size: 16),
                    ],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () async {
                      _flutterTts.stop();
                      _isDisposed = true;
                      if (_grabando) {
                        try { await FlutterScreenRecording.stopRecordScreen; } catch (_) {}
                        _grabando = false;
                      }
                      try {
                        if (_controller != null &&
                            _controller!.value.isStreamingImages) {
                          await _controller!.stopImageStream();
                        }
                      } catch (_) {}
                      if (mounted) Navigator.pop(context);
                    },
                  ),

                  // Badge ángulo en vivo (solo sentadilla/goblet, muestra torso)
                  if (_appState == ScreenState.entrenando && _liveAngle > 0 && !_esBrazos)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _liveAngle < squat_torsoLimit
                            ? Colors.redAccent.withOpacity(0.9)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _liveAngle < squat_torsoLimit
                              ? Colors.redAccent : Colors.white30,
                        ),
                      ),
                      child: Text(
                        '${_liveAngle.round()}° torso',
                        style: TextStyle(
                          color: _liveAngle < squat_torsoLimit
                              ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_poses.isNotEmpty && _esPersonaReal(_poses.first))
                          ? Colors.green.withOpacity(0.8)
                          : Colors.red.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      (_poses.isNotEmpty && _esPersonaReal(_poses.first))
                          ? '✓ Validado' : 'Buscando...',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: _appState == ScreenState.esperandoInicio
                  ? _buildExerciseSelector()
                  : _buildActiveSerieHUD(),
            ),
          ),
        ],
      ),
    );
  }

  // Aviso cuando un ejercicio base fue bloqueado por el admin (mantenimiento)
  void _mostrarBaseBloqueada(ExerciseType type) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: _amarillo, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_nombreEjercicio(type),
                  style: const TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _amarillo.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _amarillo.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: _amarillo, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('Este ejercicio no está disponible temporalmente.',
                    style: TextStyle(color: _amarillo, fontSize: 12.5, height: 1.3)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido', style: TextStyle(color: _amarillo)),
          ),
        ],
      ),
    );
  }

  // Muestra un aviso de que el ejercicio está en desarrollo (próximas versiones)
  void _mostrarEjercicioBloqueado(EjercicioRemoto ej) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: _amarillo, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ej.nombre,
                  style: const TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ej.musculo.isNotEmpty) ...[
              Text('Músculo: ${ej.musculo}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              const SizedBox(height: 8),
            ],
            if (ej.descripcion.isNotEmpty) ...[
              Text(ej.descripcion,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _amarillo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _amarillo.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: _amarillo, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Este ejercicio estará disponible en próximas actualizaciones.',
                        style: TextStyle(color: _amarillo, fontSize: 12.5, height: 1.3)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido', style: TextStyle(color: _amarillo)),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseSelector() {
    final isLeft = AngleCalculator.bodySide == BodySide.izquierdo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Selecciona el ejercicio',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Los 4 ejercicios que YA funcionan (programados en la app)
              ...ExerciseType.values.map((type) {
                final isSel = type == _ejercicioSeleccionado;
                final bloqueadoPorAdmin = _basesBloqueadas.contains(_claveDeType(type));

                // Si el admin bloqueó este ejercicio base, sale con candado
                if (bloqueadoPorAdmin) {
                  return GestureDetector(
                    onTap: () => _mostrarBaseBloqueada(type),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[800]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 5),
                          Text(_nombreEjercicio(type),
                              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                }

                return GestureDetector(
                  onTap: () => setState(() => _ejercicioSeleccionado = type),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? _amarillo : Colors.grey[850],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSel ? _amarillo : Colors.grey[700]!),
                    ),
                    child: Text(_nombreEjercicio(type),
                        style: TextStyle(
                            color: isSel ? Colors.black : Colors.grey[400],
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12)),
                  ),
                );
              }),
              // Los ejercicios "en desarrollo" traídos de Supabase (con candado)
              ..._ejerciciosBloqueados.map((ej) {
                return GestureDetector(
                  onTap: () => _mostrarEjercicioBloqueado(ej),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[800]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 5),
                        Text(ej.nombre,
                            style: TextStyle(
                                color: Colors.grey[500],
                                fontWeight: FontWeight.normal,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Indicación de la vista (perfil / frente) según el ejercicio
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _amarillo.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _amarillo.withOpacity(0.3)),
          ),
          child: Text(
            _vistaEjercicio(_ejercicioSeleccionado),
            style: const TextStyle(color: _amarillo, fontSize: 13, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 14),

        // Selector de lado (solo aplica a sentadilla/goblet; en brazos se elige solo)
        if (!_esBrazos)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _amarillo.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _amarillo.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.accessibility_new, color: _amarillo, size: 15),
                    SizedBox(width: 6),
                    Text('¿Qué lado de tu cuerpo ve la cámara?',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                            () => AngleCalculator.bodySide = BodySide.izquierdo),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 70,
                          decoration: BoxDecoration(
                            color: isLeft ? _amarillo : Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLeft ? _amarillo : Colors.grey[700]!,
                              width: isLeft ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🧍⬅️', style: TextStyle(fontSize: 22)),
                              const SizedBox(height: 4),
                              Text('Lado IZQUIERDO',
                                  style: TextStyle(
                                      color: isLeft ? Colors.black : Colors.grey[500],
                                      fontSize: 11,
                                      fontWeight: isLeft
                                          ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                            () => AngleCalculator.bodySide = BodySide.derecho),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 70,
                          decoration: BoxDecoration(
                            color: !isLeft ? _amarillo : Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !isLeft ? _amarillo : Colors.grey[700]!,
                              width: !isLeft ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('➡️🧍', style: TextStyle(fontSize: 22)),
                              const SizedBox(height: 4),
                              Text('Lado DERECHO',
                                  style: TextStyle(
                                      color: !isLeft ? Colors.black : Colors.grey[500],
                                      fontSize: 11,
                                      fontWeight: !isLeft
                                          ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        const SizedBox(height: 14),

        // ── SELECTOR DE META DE REPETICIONES (correctas) ──────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _amarillo.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _amarillo.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Repeticiones correctas\npara terminar',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              // Botón menos
              _BotonMeta(
                icono: Icons.remove,
                onTap: () => setState(() {
                  if (_metaReps > 1) {
                    _metaReps--;
                    _metaCtrl.text = '$_metaReps';
                  }
                }),
              ),
              // Número grande editable (se puede borrar y escribir libremente)
              Container(
                width: 56,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: _metaCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 2,
                  style: const TextStyle(
                      color: _amarillo, fontSize: 26, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    // Permitir borrar (queda vacío sin forzar 1)
                    if (v.isEmpty) return;
                    final n = int.tryParse(v);
                    if (n != null && n >= 1 && n <= 99) {
                      _metaReps = n;
                      setState(() {}); // actualiza el texto del botón Iniciar
                    }
                  },
                ),
              ),
              // Botón más
              _BotonMeta(
                icono: Icons.add,
                onTap: () => setState(() {
                  if (_metaReps < 99) {
                    _metaReps++;
                    _metaCtrl.text = '$_metaReps';
                  }
                }),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _amarillo,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _iniciarSerie,
            child: Text('Iniciar — $_metaReps reps',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSerieHUD() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_nombreEjercicio(_ejercicioSeleccionado),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _amarillo.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _amarillo.withOpacity(0.5)),
              ),
              child: Text(_faseActual,
                  style: const TextStyle(
                      color: _amarillo,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _RepBox(
                label: 'Total', value: _repCounter.totalReps, color: Colors.white)),
            const SizedBox(width: 10),
            Expanded(child: _RepBox(
                label: 'Válidas', value: _repCounter.validReps, color: Colors.greenAccent)),
            const SizedBox(width: 10),
            Expanded(child: _RepBox(
                label: 'Inválidas', value: _repCounter.invalidReps, color: Colors.redAccent)),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _lastFeedback.isNotEmpty
              ? Container(
                  key: ValueKey(_lastFeedback),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _feedbackColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _feedbackColor.withOpacity(0.5)),
                  ),
                  child: Text(_lastFeedback,
                      style: TextStyle(
                          color: _feedbackColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      textAlign: TextAlign.center),
                )
              : const SizedBox(height: 0, key: ValueKey('empty')),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _terminarSerie,
            child: const Text('Terminar — Ver resultados',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _BotonMeta extends StatelessWidget {
  final IconData icono;
  final VoidCallback onTap;
  const _BotonMeta({required this.icono, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: _amarillo,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icono, color: Colors.black, size: 22),
        ),
      );
}

class _RepBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _RepBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
          ],
        ),
      );
}

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final Color skeletonColor;

  const PosePainter({
    required this.poses,
    required this.imageSize,
    this.skeletonColor = Colors.white,
  });

  static const _connections = [
    [PoseLandmarkType.nose,          PoseLandmarkType.leftEyeInner],
    [PoseLandmarkType.leftEyeInner,  PoseLandmarkType.leftEye],
    [PoseLandmarkType.leftEye,       PoseLandmarkType.leftEyeOuter],
    [PoseLandmarkType.leftEyeOuter,  PoseLandmarkType.leftEar],
    [PoseLandmarkType.nose,          PoseLandmarkType.rightEyeInner],
    [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
    [PoseLandmarkType.rightEye,      PoseLandmarkType.rightEyeOuter],
    [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow,     PoseLandmarkType.leftWrist],
    [PoseLandmarkType.leftWrist,     PoseLandmarkType.leftPinky],
    [PoseLandmarkType.leftWrist,     PoseLandmarkType.leftIndex],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow,    PoseLandmarkType.rightWrist],
    [PoseLandmarkType.rightWrist,    PoseLandmarkType.rightPinky],
    [PoseLandmarkType.rightWrist,    PoseLandmarkType.rightIndex],
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip,       PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip,       PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee,      PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.leftAnkle,     PoseLandmarkType.leftHeel],
    [PoseLandmarkType.leftHeel,      PoseLandmarkType.leftFootIndex],
    [PoseLandmarkType.rightHip,      PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee,     PoseLandmarkType.rightAnkle],
    [PoseLandmarkType.rightAnkle,    PoseLandmarkType.rightHeel],
    [PoseLandmarkType.rightHeel,     PoseLandmarkType.rightFootIndex],
  ];

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paintPoint     = Paint()..style = PaintingStyle.fill..color = Colors.cyanAccent;
    final paintConfident = Paint()..style = PaintingStyle.fill..color = Colors.orangeAccent;
    final paintLine = Paint()
      ..style = PaintingStyle.stroke
      ..color = skeletonColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    for (final pose in poses) {
      pose.landmarks.forEach((_, lm) {
        final o = _toOffset(lm, canvasSize);
        canvas.drawCircle(o, lm.likelihood > 0.6 ? 8 : 5,
            lm.likelihood > 0.6 ? paintConfident : paintPoint);
      });
      for (final conn in _connections) {
        final a = pose.landmarks[conn[0] as PoseLandmarkType];
        final b = pose.landmarks[conn[1] as PoseLandmarkType];
        if (a == null || b == null || a.likelihood < 0.15 || b.likelihood < 0.15) continue;
        canvas.drawLine(_toOffset(a, canvasSize), _toOffset(b, canvasSize), paintLine);
      }
    }
  }

  Offset _toOffset(PoseLandmark lm, Size canvas) {
    final double x = lm.x * (canvas.width  / imageSize.height);
    final double y = canvas.height - (lm.y * (canvas.height / imageSize.width));
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.poses != poses || old.skeletonColor != skeletonColor;
}