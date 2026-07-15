import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ══════════════════════════════════════════════════════════════════════════════
// UMBRALES — edita estos números para calibrar
// ══════════════════════════════════════════════════════════════════════════════

enum BodySide { izquierdo, derecho }

// Modo de medición que necesita cada ejercicio:
//   piernas   → sentadilla / goblet (oreja-cadera-rodilla-tobillo, de pie de perfil)
//   press     → press militar con mancuernas (de FRENTE, sentado, ambos brazos)
//   elevacion → elevaciones laterales (altura del codo, de pie de FRENTE)
enum ModoMedicion { piernas, press, elevacion }

// ── SENTADILLA ───────────────────────────────────────────────────────────────
const double squat_torsoLimit  =  85;
const double squat_kneeBottom  = 120;
const double squat_kneeTooHigh = 135;
const double squat_kneeUp      = 155;

// ── GOBLET SQUAT ─────────────────────────────────────────────────────────────
const double goblet_torsoLimit  = 80;
const double goblet_kneeBottom  = 105;
const double goblet_kneeTooHigh = 110;
const double goblet_kneeUp      = 155;

// ── PRESS MILITAR CON MANCUERNAS (de FRENTE, sentado, ambos brazos) ──────────
// Mide el ángulo del CODO (hombro-codo-muñeca) de cada brazo. De frente y
// sentado, ML Kit ve los dos brazos completos y detecta estable.
// VALORES REALES medidos por Marcos:
//   - Abajo (mancuernas en hombros): 40-55°
//   - Arriba (brazos estirados): 135-165°
//   - En medio (subiendo, no completó): 56-134°
//   - Muy abajo (bajó demasiado, riesgo hombro): < 39°
const double press_codoAbajo    =  55; // ← AJUSTA: codo <= este = posición baja (hombros). Tus 40-55
const double press_codoArriba   = 145; // ← AJUSTA: codo >= este = brazos estirados arriba (cuenta). Tus 145-165
const double press_codoMuyAbajo =  39; // ← AJUSTA: codo < este = bajó demasiado (riesgo hombro)
const double press_codoNoSube   = 145; // ← AJUSTA: si solo llega a menos de esto y baja = no estiró arriba
// Error de espalda arqueada hacia atrás (inclinación del torso vs vertical):
const double press_espaldaInclinacion = 22; // ← AJUSTA: inclinación > este (grados) = cuida espalda
// MUÑECAS MUY ABIERTAS (riesgo de hombro/manguito rotador). La apertura normal
// cambia según la altura: arriba los brazos van juntos (X chico), abajo/medio
// están más abiertos (X grande). Por eso hay un umbral por zona. Valores REALES
// de Marcos (X = ancho muñecas / ancho hombros):
//   Abajo (reposo):   normal 1.70-2.20 → peligro si X > 2.20
//   Medio camino:     normal 2.00-2.40 → peligro si X > 2.40
//   Arriba (estirado):normal 1.00-1.65 → peligro si X > 1.65
const double press_aperturaAbajo  = 2.20; // ← AJUSTA: abajo, X > este = muy abierto
const double press_aperturaMedio  = 2.40; // ← AJUSTA: medio, X > este = muy abierto
const double press_aperturaArriba = 1.80; // ← AJUSTA: arriba, X > este = muy abierto
const double press_confMin = 0.8; // ← AJUSTA: confianza mínima de los puntos del brazo

// ── ELEVACIONES LATERALES (de FRENTE, de pie) ────────────────────────────────
// Mide la ALTURA del codo respecto al hombro (no depende de la muñeca, que la
// mancuerna podría tapar). Pero SÍ usa la muñeca para ver si el brazo está
// estirado (ángulo del codo).
//   - Abajo: codo cerca de la cadera (brazos pegados al cuerpo)
//   - Arriba correcto: codo al nivel del hombro
//   - Error: codo MÁS arriba del hombro (manguito rotador)
// ÁNGULO DEL HOMBRO (cadera-hombro-codo) — lo que se ve en pantalla:
//   Brazos abajo (reposo): ángulo CHICO (~5-15°)
//   Brazos arriba al hombro (correcto): ángulo MEDIO (~45-55°)
//   Brazos MÁS arriba (peligro): ángulo > 55° = manguito rotador
// Valores reales medidos por Marcos. Con un poco de margen.
const double elev_anguloAbajo   =  30; // ← AJUSTA: ángulo < este = brazos abajo (reposo)
const double elev_anguloArriba  =  85; // ← AJUSTA: ángulo >= este = brazos arriba (cuenta la rep). Tus 45-55 con margen
const double elev_anguloMuyAlto =  100; // ← AJUSTA: ángulo > este = subió demasiado (manguito rotador)
const double elev_codoDoblado    = 140; // ← AJUSTA: codo < este = brazo doblado (mala forma)
const double elev_confMin = 0.7; // ← AJUSTA: confianza mínima de los puntos del brazo
// Confianza MÁS ALTA para detectar "brazo doblado". Si el fondo se parece a la
// piel y la muñeca no se ve clara, NO marca el error (mejor callar que fallar).
const double elev_codoConfMin = 0.8; // ← AJUSTA: sube a 0.85 si sigue fallando con fondos así

// ── ESTADO DEL BRAZO (genérico para curl y elevaciones) ──────────────────────
enum EstadoBrazo { arriba, abajo, medio, desconocido }

// ── ERRORES DE CADA EJERCICIO NUEVO ──────────────────────────────────────────
enum ErrorPress {
  ninguno,
  espalda,        // arquea la espalda hacia atrás (riesgo lumbar)
  bajoMucho,      // baja demasiado las mancuernas (riesgo hombro/manguito)
  noSube,         // no estira los brazos arriba (rango incompleto)
  asimetrico,     // un brazo más arriba que el otro (descompensación)
  munecasAbiertas, // arriba con muñecas muy abiertas (riesgo manguito rotador)
}

enum ErrorElevacion {
  ninguno,
  codoMuyAlto,    // sube más arriba del hombro (riesgo manguito rotador)
  brazoDoblado,   // brazo doblado, muñeca colgando (mala forma)
}

// ════════════════════════════════════════════════════════════════════════════
class AngleCalculator {
  static int _frameCount = 0;
  static BodySide bodySide = BodySide.izquierdo;

  // Suavizado del ángulo del codo en el curl (evita saltos de ML Kit de perfil)
  static final List<double> _curlBuffer = [];

  static double angleBetween(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final double abX = a.x - b.x, abY = a.y - b.y;
    final double cbX = c.x - b.x, cbY = c.y - b.y;
    final double dot = abX * cbX + abY * cbY;
    final double mAB = sqrt(abX * abX + abY * abY);
    final double mCB = sqrt(cbX * cbX + cbY * cbY);
    if (mAB == 0 || mCB == 0) return 0;
    return acos((dot / (mAB * mCB)).clamp(-1.0, 1.0)) * (180 / pi);
  }

  // Inclinación del torso respecto a la VERTICAL, en grados.
  // Parado recto (hombro justo encima de cadera) ≈ 0°. Si te inclinas o
  // curvas hacia adelante/atrás, el valor sube. No depende del lado.
  static double _inclinacionTorso(PoseLandmark sho, PoseLandmark hip) {
    final double dx = (sho.x - hip.x).abs();
    final double dy = (sho.y - hip.y).abs();
    if (dy == 0) return 90;
    return atan(dx / dy) * (180 / pi);
  }

  // Elige automáticamente el brazo (izq/der) mejor detectado por ML Kit.
  // De pie de perfil/frente, el brazo más visible gana. Devuelve los 4 puntos.
  static _BrazoElegido _mejorBrazo(Map<PoseLandmarkType, PoseLandmark> lm) {
    final shoL = lm[PoseLandmarkType.leftShoulder];
    final elbL = lm[PoseLandmarkType.leftElbow];
    final wriL = lm[PoseLandmarkType.leftWrist];
    final hipL = lm[PoseLandmarkType.leftHip];
    final shoR = lm[PoseLandmarkType.rightShoulder];
    final elbR = lm[PoseLandmarkType.rightElbow];
    final wriR = lm[PoseLandmarkType.rightWrist];
    final hipR = lm[PoseLandmarkType.rightHip];

    double conf(PoseLandmark? s, PoseLandmark? e, PoseLandmark? w) {
      final cs = s?.likelihood ?? 0;
      final ce = e?.likelihood ?? 0;
      final cw = w?.likelihood ?? 0;
      return (cs + ce * 2 + cw) / 4; // doble peso al codo
    }
    final confL = conf(shoL, elbL, wriL);
    final confR = conf(shoR, elbR, wriR);
    final bool usarIzq = confL >= confR;

    return _BrazoElegido(
      sho: usarIzq ? shoL : shoR,
      elb: usarIzq ? elbL : elbR,
      wri: usarIzq ? wriL : wriR,
      hip: usarIzq ? hipL : hipR,
      knee: lm[usarIzq ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee],
      conf: usarIzq ? confL : confR,
    );
  }

  // Reinicia el suavizado (llamar al empezar una serie nueva)
  static void resetCurl() {
    _curlBuffer.clear();
    _pressBufferIzq.clear();
    _pressBufferDer.clear();
    _elevCodoBuffer.clear();
  }

  // Buffers de suavizado para cada brazo en el press
  static final List<double> _pressBufferIzq = [];
  static final List<double> _pressBufferDer = [];

  // Buffer de suavizado del codo en elevaciones (evita falso "brazo doblado")
  static final List<double> _elevCodoBuffer = [];

  static PoseAngles? extract(Pose pose, {ModoMedicion modo = ModoMedicion.piernas}) {
    _frameCount++;
    final bool log = _frameCount % 30 == 0;
    final lm = pose.landmarks;

    // ════════════════════════════════════════════════════════════════════════
    // PRESS MILITAR — de frente, sentado. Ángulo del codo (ambos brazos) + espalda.
    // ════════════════════════════════════════════════════════════════════════
    if (modo == ModoMedicion.press) {
      return _extractPress(lm, log);
    }

    // ════════════════════════════════════════════════════════════════════════
    // ELEVACIONES LATERALES — de frente, de pie. Altura del codo + brazo estirado.
    // ════════════════════════════════════════════════════════════════════════
    if (modo == ModoMedicion.elevacion) {
      return _extractElevacion(_mejorBrazo(lm), log);
    }

    // ════════════════════════════════════════════════════════════════════════
    // CAMINO PIERNAS — SENTADILLA / GOBLET (intacto, igual que siempre)
    // ════════════════════════════════════════════════════════════════════════
    final isLeft = bodySide == BodySide.izquierdo;
    final ear  = lm[isLeft ? PoseLandmarkType.leftEar       : PoseLandmarkType.rightEar];
    final sho  = lm[isLeft ? PoseLandmarkType.leftShoulder  : PoseLandmarkType.rightShoulder];
    final elb  = lm[isLeft ? PoseLandmarkType.leftElbow     : PoseLandmarkType.rightElbow];
    final wri  = lm[isLeft ? PoseLandmarkType.leftWrist     : PoseLandmarkType.rightWrist];
    final hip  = lm[isLeft ? PoseLandmarkType.leftHip       : PoseLandmarkType.rightHip];
    final kne  = lm[isLeft ? PoseLandmarkType.leftKnee      : PoseLandmarkType.rightKnee];
    final ank  = lm[isLeft ? PoseLandmarkType.leftAnkle     : PoseLandmarkType.rightAnkle];
    final nose = lm[PoseLandmarkType.nose];

    if (hip == null || kne == null) return null;
    if (hip.likelihood < 0.2 || kne.likelihood < 0.2) return null;

    double torsoSquat = 0;
    String src = '?';
    if (ear != null && ear.likelihood > 0.25) {
      torsoSquat = angleBetween(ear, hip, kne); src = 'OJA';
    } else if (nose != null && nose.likelihood > 0.25) {
      torsoSquat = angleBetween(nose, hip, kne); src = 'NAR';
    } else if (sho != null && sho.likelihood > 0.2) {
      torsoSquat = angleBetween(sho, hip, kne); src = 'HOM';
    }

    double torsoStd = (sho != null && sho.likelihood > 0.2)
        ? angleBetween(sho, hip, kne) : torsoSquat;

    double knee = (ank != null && ank.likelihood > 0.2)
        ? angleBetween(hip, kne, ank) : 0;

    double elbowAngle = 0;
    bool wristUp = false;
    if (sho != null && elb != null && wri != null &&
        sho.likelihood > 0.2 && elb.likelihood > 0.2 && wri.likelihood > 0.2) {
      elbowAngle = angleBetween(sho, elb, wri);
      wristUp = wri.y < elb.y;
    }

    if (log) {
      debugPrint('BIOSMART [$src] torsoSq=${torsoSquat.round()}° '
          'std=${torsoStd.round()}° rod=${knee.round()}° codo=${elbowAngle.round()}°');
    }

    return PoseAngles(
      torsoSquat: torsoSquat,
      torso:      torsoStd,
      hip:        torsoStd,
      knee:       knee,
      elbow:      elbowAngle,
      wristAboveElbow: wristUp,
    );
  }

  // ── PRESS MILITAR CON MANCUERNAS ────────────────────────────────────────────
  // De frente, sentado, ambos brazos. Mide el ángulo del codo de cada brazo,
  // los promedia (suavizado) y cuenta cuando AMBOS llegan arriba.
  static PoseAngles? _extractPress(Map<PoseLandmarkType, PoseLandmark> lm, bool log) {
    final shoL = lm[PoseLandmarkType.leftShoulder];
    final elbL = lm[PoseLandmarkType.leftElbow];
    final wriL = lm[PoseLandmarkType.leftWrist];
    final shoR = lm[PoseLandmarkType.rightShoulder];
    final elbR = lm[PoseLandmarkType.rightElbow];
    final wriR = lm[PoseLandmarkType.rightWrist];
    final hipL = lm[PoseLandmarkType.leftHip];
    final hipR = lm[PoseLandmarkType.rightHip];

    // Necesitamos al menos un brazo completo
    final bool izqOk = shoL != null && elbL != null && wriL != null &&
        elbL.likelihood > press_confMin && wriL.likelihood > press_confMin;
    final bool derOk = shoR != null && elbR != null && wriR != null &&
        elbR.likelihood > press_confMin && wriR.likelihood > press_confMin;

    if (!izqOk && !derOk) {
      return const PoseAngles(
        torsoSquat: 0, torso: 0, hip: 0, knee: 0, elbow: 0,
        wristAboveElbow: false, estadoBrazo: EstadoBrazo.desconocido,
      );
    }

    // Ángulo del codo de cada brazo (suavizado por brazo)
    double? codoIzq, codoDer;
    if (izqOk) {
      final c = angleBetween(shoL, elbL, wriL);
      _pressBufferIzq.add(c);
      if (_pressBufferIzq.length > 5) _pressBufferIzq.removeAt(0);
      codoIzq = _pressBufferIzq.reduce((a, b) => a + b) / _pressBufferIzq.length;
    }
    if (derOk) {
      final c = angleBetween(shoR, elbR, wriR);
      _pressBufferDer.add(c);
      if (_pressBufferDer.length > 5) _pressBufferDer.removeAt(0);
      codoDer = _pressBufferDer.reduce((a, b) => a + b) / _pressBufferDer.length;
    }

    // Ángulo representativo: promedio de los brazos disponibles (lo que se ve en pantalla)
    final List<double> codos = [if (codoIzq != null) codoIzq, if (codoDer != null) codoDer];
    final double codo = codos.reduce((a, b) => a + b) / codos.length;

    // Estado para contar:
    //   arriba = brazos estirados arriba (codo >= 155) → cuenta
    //   abajo  = mancuernas en los hombros (codo <= 95)
    //   medio  = subiendo o bajando
    EstadoBrazo estado;
    if (codo >= press_codoArriba) {
      estado = EstadoBrazo.arriba;   // estirado arriba (cuenta)
    } else if (codo <= press_codoAbajo) {
      estado = EstadoBrazo.abajo;    // mancuernas en hombros (inicio)
    } else {
      estado = EstadoBrazo.medio;    // subiendo/bajando
    }

    // ── ERRORES ──────────────────────────────────────────────────────────────
    ErrorPress errorPress = ErrorPress.ninguno;

    // Calcular SIEMPRE la apertura de las muñecas (para mostrar en pantalla).
    // aperturaMunecas = cuántas veces más anchas están las muñecas vs los hombros.
    //   ~1.0 = muñecas igual de anchas que los hombros (rectas, bien)
    //   >1.35 = muñecas mucho más abiertas (riesgo manguito rotador)
    double aperturaMunecas = 0;
    if (shoL != null && shoR != null && wriL != null && wriR != null &&
        wriL.likelihood > press_confMin && wriR.likelihood > press_confMin) {
      final double anchoHombros = (shoL.x - shoR.x).abs();
      final double anchoMunecas = (wriL.x - wriR.x).abs();
      if (anchoHombros > 0.01) {
        aperturaMunecas = anchoMunecas / anchoHombros;
      }
    }

    // 1) MUÑECAS MUY ABIERTAS (riesgo de hombro/manguito rotador).
    //    El umbral depende de la zona: arriba los brazos van juntos (X chico),
    //    abajo/medio están más abiertos. Usamos el umbral de cada zona.
    double umbralApertura;
    if (estado == EstadoBrazo.arriba) {
      umbralApertura = press_aperturaArriba;
    } else if (estado == EstadoBrazo.abajo) {
      umbralApertura = press_aperturaAbajo;
    } else {
      umbralApertura = press_aperturaMedio;
    }
    if (aperturaMunecas > umbralApertura) {
      errorPress = ErrorPress.munecasAbiertas;
    }

    // 2) Asimetría: un brazo mucho más arriba que el otro (>40° de diferencia)
    if (codoIzq != null && codoDer != null && errorPress == ErrorPress.ninguno) {
      if ((codoIzq - codoDer).abs() > 40) {
        errorPress = ErrorPress.asimetrico;
      }
    }

    // 3) ESPALDA arqueada hacia atrás (inclinación del torso vs vertical)
    double inclinacion = 0;
    final sho = izqOk ? shoL : shoR;
    final hip = (hipL != null && hipL.likelihood > 0.2)
        ? hipL
        : (hipR != null && hipR.likelihood > 0.2 ? hipR : null);
    if (sho != null && hip != null && sho.likelihood > 0.2) {
      inclinacion = _inclinacionTorso(sho, hip);
      if (inclinacion > press_espaldaInclinacion) {
        errorPress = ErrorPress.espalda; // prioridad lumbar
      }
    }

    if (log) {
      debugPrint('BIOSMART [PRESS] codo=${codo.round()}° estado=${estado.name} '
          'izq=${codoIzq?.round()} der=${codoDer?.round()} incl=${inclinacion.round()}° '
          'apertura=${aperturaMunecas.toStringAsFixed(2)} err=${errorPress.name}');
    }

    return PoseAngles(
      torsoSquat: inclinacion,
      torso: inclinacion,
      hip: inclinacion,
      knee: 0,
      elbow: codo,
      wristAboveElbow: false,
      estadoBrazo: estado,
      codoVsHombroFrac: aperturaMunecas,  // apertura para mostrar en pantalla
      errorPress: errorPress,
    );
  }

  // ── ELEVACIONES LATERALES ──────────────────────────────────────────────────
  static PoseAngles? _extractElevacion(_BrazoElegido b, bool log) {
    final sho = b.sho, elb = b.elb, wri = b.wri, hip = b.hip;
    if (sho == null || elb == null) return null;
    if (b.conf < elev_confMin) {
      return const PoseAngles(
        torsoSquat: 0, torso: 0, hip: 0, knee: 0, elbow: 0,
        wristAboveElbow: false, estadoBrazo: EstadoBrazo.desconocido,
      );
    }

    // ── ÁNGULO DEL HOMBRO (cadera-hombro-codo) ──────────────────────────────
    // Es el ángulo que se ve en pantalla. Mide cuánto se separa el brazo del
    // cuerpo: brazo abajo (pegado) = ángulo chico (5-15°); brazo a la altura
    // del hombro = ángulo medio (45-55°). Funciona en cámara frontal o trasera.
    double anguloHombro = 0;
    if (hip != null && hip.likelihood > 0.2) {
      anguloHombro = angleBetween(hip, sho, elb);
    } else {
      // Sin cadera no podemos medir bien; devolvemos desconocido
      return const PoseAngles(
        torsoSquat: 0, torso: 0, hip: 0, knee: 0, elbow: 0,
        wristAboveElbow: false, estadoBrazo: EstadoBrazo.desconocido,
      );
    }

    // El valor que mostramos en pantalla (el ángulo del hombro)
    final double codoVsHombro = anguloHombro;

    EstadoBrazo estado;
    if (anguloHombro < elev_anguloAbajo) {
      estado = EstadoBrazo.abajo;    // ángulo chico = brazos abajo (reposo)
    } else if (anguloHombro >= elev_anguloArriba) {
      estado = EstadoBrazo.arriba;   // ángulo grande = brazos elevados al hombro
    } else {
      estado = EstadoBrazo.medio;    // subiendo
    }

    // Errores
    ErrorElevacion errorElev = ErrorElevacion.ninguno;
    // 1) Subió DEMASIADO (más arriba del hombro) = manguito rotador
    if (anguloHombro > elev_anguloMuyAlto) {
      errorElev = ErrorElevacion.codoMuyAlto;
    }
    // 2) Brazo doblado (codo < umbral) = mala forma.
    //    Solo si la muñeca Y el codo son MUY confiables (evita falso positivo
    //    cuando el fondo se parece a la piel y ML Kit pierde la muñeca).
    double codoAng = 0;
    if (wri != null && elb != null &&
        wri.likelihood > elev_codoConfMin && elb.likelihood > elev_codoConfMin) {
      final double codoCrudo = angleBetween(sho, elb, wri);
      // Suavizado: promedio de los últimos 5 frames para que un frame malo no
      // dispare el error por culpa del fondo.
      _elevCodoBuffer.add(codoCrudo);
      if (_elevCodoBuffer.length > 5) _elevCodoBuffer.removeAt(0);
      codoAng = _elevCodoBuffer.reduce((a, b) => a + b) / _elevCodoBuffer.length;

      if (codoAng > 10 && codoAng < elev_codoDoblado && errorElev == ErrorElevacion.ninguno) {
        errorElev = ErrorElevacion.brazoDoblado;
      }
    } else {
      // Muñeca poco confiable (fondo parecido a la piel): no marcamos doblado,
      // mejor no avisar que avisar mal. Limpiamos el buffer.
      _elevCodoBuffer.clear();
    }

    if (log) {
      debugPrint('BIOSMART [ELEV] codoVsHom=${codoVsHombro.toStringAsFixed(2)} '
          'estado=${estado.name} codoAng=${codoAng.round()}° '
          'err=${errorElev.name} conf=${b.conf.toStringAsFixed(2)}');
    }

    return PoseAngles(
      torsoSquat: 0,
      torso: 0,
      hip: 0,
      knee: 0,
      elbow: codoAng,
      wristAboveElbow: false,
      estadoBrazo: estado,
      codoVsHombroFrac: codoVsHombro,
      errorElevacion: errorElev,
    );
  }

  // ── Textos de error (para guardar en 'razon') ─────────────────────────────
  static String razonErrorPress(ErrorPress e) {
    switch (e) {
      case ErrorPress.espalda:
        return 'Cuida la espalda, no la arquees hacia atrás (riesgo lumbar)';
      case ErrorPress.bajoMucho:
        return 'Codos muy abiertos a la altura del hombro (riesgo de manguito rotador)';
      case ErrorPress.noSube:
        return 'No estiraste los brazos arriba (rango incompleto)';
      case ErrorPress.asimetrico:
        return 'Un brazo más arriba que el otro (sube parejo)';
      case ErrorPress.munecasAbiertas:
        return 'Brazos muy abiertos (presión en hombro, codo y muñeca - manguito rotador)';
      case ErrorPress.ninguno:
        return '';
    }
  }

  static bool esErrorDeLesionPress(ErrorPress e) {
    return e == ErrorPress.espalda || e == ErrorPress.bajoMucho ||
           e == ErrorPress.munecasAbiertas;
  }

  static String razonErrorElevacion(ErrorElevacion e) {
    switch (e) {
      case ErrorElevacion.codoMuyAlto:
        return 'Subiste más arriba del hombro (riesgo de manguito rotador)';
      case ErrorElevacion.brazoDoblado:
        return 'Brazo doblado, estíralo (mantén el codo casi recto)';
      case ErrorElevacion.ninguno:
        return '';
    }
  }

  static bool esErrorDeLesionElevacion(ErrorElevacion e) {
    return e == ErrorElevacion.codoMuyAlto;
  }
}

// Brazo elegido por confianza (uso interno)
class _BrazoElegido {
  final PoseLandmark? sho, elb, wri, hip, knee;
  final double conf;
  _BrazoElegido({this.sho, this.elb, this.wri, this.hip, this.knee, required this.conf});
}

class PoseAngles {
  final double torsoSquat;
  final double torso;
  final double hip;
  final double knee;
  final double elbow;
  final bool wristAboveElbow;
  final EstadoBrazo estadoBrazo;        // estado del brazo (press y elevaciones)
  final double codoVsHombroFrac;        // altura del codo (elevaciones)
  final ErrorPress errorPress;          // error del press militar
  final ErrorElevacion errorElevacion;  // error de las elevaciones

  double get hipSquat   => torsoSquat;
  double get torsoAngle => torso;
  double get leftElbow  => elbow;
  double get rightElbow => elbow;
  double get leftKnee   => knee;
  double get rightKnee  => knee;
  double get leftHip    => hip;
  double get rightHip   => hip;
  bool get leftWristAboveElbow  => wristAboveElbow;
  bool get rightWristAboveElbow => wristAboveElbow;

  const PoseAngles({
    required this.torsoSquat,
    required this.torso,
    required this.hip,
    required this.knee,
    required this.elbow,
    required this.wristAboveElbow,
    this.estadoBrazo = EstadoBrazo.desconocido,
    this.codoVsHombroFrac = 0,
    this.errorPress = ErrorPress.ninguno,
    this.errorElevacion = ErrorElevacion.ninguno,
  });

  Map<String, dynamic> toJson(String ejercicio) => {
    'ejercicio': ejercicio,
    'angulos_clave': {
      'rodilla':     knee.round(),
      'cadera':      hip.round(),
      'torso_squat': torsoSquat.round(),
      'codo':        elbow.round(),
    },
  };
}