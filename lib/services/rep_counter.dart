import 'angle_calculator.dart';

enum ExercisePhase {
  esperandoBajar,
  bajando,
  enFondo,
  esperandoSubir,
  subiendo,
}

enum ExerciseType { sentadilla, gobletSquat, pressMilitar, elevacionLateral }

const int _holdMs = 2000;

class RepResult {
  final bool isValid;
  final String reason;
  final int timestamp;
  final int anguloTronco;  // ángulo de tronco/espalda en esta rep (0 si no aplica)
  final int anguloRodilla; // ángulo de rodilla/codo principal en esta rep (0 si no aplica)
  RepResult({
    required this.isValid,
    required this.reason,
    required this.timestamp,
    this.anguloTronco = 0,
    this.anguloRodilla = 0,
  });
}

class RepCounter {
  final ExerciseType exercise;

  ExercisePhase _phase = ExercisePhase.esperandoBajar;

  final List<RepResult> reps = [];
  final List<Map<String, int>> errorTimestamps = [];
  final List<String> _errorsThisRep = [];

  int? _repStartMs;
  int? _fondoStartMs;
  bool _subioPronto = false;

  double _minTorsoThisRep = 999;
  double _minKneeThisRep  = 999;

  // Curl / elevaciones: seguimiento de ángulos durante la rep
  double _maxCodoThisRep = 0;    // codo más estirado en la rep (para "no estira")
  double _minCodoThisRep = 999;  // codo más doblado en la rep

  RepCounter({required this.exercise});

  int get totalReps   => reps.length;
  int get validReps   => reps.where((r) => r.isValid).length;
  int get invalidReps => reps.where((r) => !r.isValid).length;

  RepCounterResult process(PoseAngles a, int currentMs) {
    switch (exercise) {
      case ExerciseType.sentadilla:       return _sentadilla(a, currentMs);
      case ExerciseType.gobletSquat:      return _gobletSquat(a, currentMs);
      case ExerciseType.pressMilitar:     return _press(a, currentMs);
      case ExerciseType.elevacionLateral: return _elevacion(a, currentMs);
    }
  }

  // ── SENTADILLA GUIADA (intacta) ────────────────────────────────────────────
  RepCounterResult _sentadilla(PoseAngles a, int ms) {
    final knee  = a.knee;
    final torso = a.torsoSquat;
    final bool torsoValido = torso > 10;
    final bool kneeValido  = knee  > 10;

    if (torsoValido && torso < _minTorsoThisRep) _minTorsoThisRep = torso;
    if (kneeValido  && knee  < _minKneeThisRep)  _minKneeThisRep  = knee;

    String? warning;
    if (torsoValido && torso < squat_torsoLimit) {
      warning = '⚠️ Torso muy adelante (${torso.round()}°)';
    } else if (_phase == ExercisePhase.enFondo && kneeValido && knee > squat_kneeTooHigh) {
      warning = '⚠️ Baja más — rodilla (${knee.round()}°)';
    }

    switch (_phase) {
      case ExercisePhase.esperandoBajar:
        if (kneeValido && knee < squat_kneeUp) {
          _phase = ExercisePhase.bajando;
          _repStartMs = ms;
          _minTorsoThisRep = 999;
          _minKneeThisRep  = 999;
        }
        return RepCounterResult(phase: 'Baje', shouldCallAI: false, liveWarning: warning);

      case ExercisePhase.bajando:
        if (kneeValido && knee < squat_kneeBottom) {
          _phase = ExercisePhase.enFondo;
          _fondoStartMs = ms;
          _subioPronto = false;
          return RepCounterResult(phase: 'Fondo — mantén', shouldCallAI: false,
              liveWarning: warning, holdSecondsLeft: 2);
        }
        if (kneeValido && knee > squat_kneeUp && _repStartMs != null) {
          _errorsThisRep.add('No bajó suficiente (${_minKneeThisRep.round()}°) — fondo no alcanzado');
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Bajando...', shouldCallAI: false, liveWarning: warning);

      case ExercisePhase.enFondo:
        final elapsed = ms - (_fondoStartMs ?? ms);
        final secondsLeft = ((_holdMs - elapsed) / 1000).ceil().clamp(0, 2);
        if (kneeValido && knee > squat_kneeBottom + 15) {
          _subioPronto = true;
          _phase = ExercisePhase.subiendo;
          _errorsThisRep.add('Subió muy rápido — mantén 2 segundos abajo');
          return RepCounterResult(phase: 'Subiendo...', shouldCallAI: false, liveWarning: warning);
        }
        if (elapsed >= _holdMs) {
          _phase = ExercisePhase.esperandoSubir;
          return RepCounterResult(phase: 'Suba', shouldCallAI: false,
              liveWarning: warning, voice: 'Suba');
        }
        String? cv;
        if (elapsed < 200)                          cv = '2';
        else if (elapsed >= 1000 && elapsed < 1200) cv = '1';
        return RepCounterResult(phase: '$secondsLeft...', shouldCallAI: false,
            liveWarning: warning, holdSecondsLeft: secondsLeft, voice: cv);

      case ExercisePhase.esperandoSubir:
      case ExercisePhase.subiendo:
        if (kneeValido && knee > squat_kneeUp) {
          if (_minTorsoThisRep < squat_torsoLimit) {
            _errorsThisRep.add('Espalda muy inclinada (${_minTorsoThisRep.round()}°) — riesgo lumbar');
          }
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Subiendo...', shouldCallAI: false, liveWarning: warning);
    }
  }

  // ── GOBLET SQUAT (intacta) ─────────────────────────────────────────────────
  RepCounterResult _gobletSquat(PoseAngles a, int ms) {
    final knee  = a.knee;
    final torso = a.torsoSquat;
    final bool torsoValido = torso > 10;
    final bool kneeValido  = knee  > 10;

    if (torsoValido && torso < _minTorsoThisRep) _minTorsoThisRep = torso;
    if (kneeValido  && knee  < _minKneeThisRep)  _minKneeThisRep  = knee;

    String? warning;
    if (torsoValido && torso < goblet_torsoLimit) {
      warning = '⚠️ Torso muy adelante (${torso.round()}°)';
    } else if (_phase == ExercisePhase.enFondo && kneeValido && knee > goblet_kneeTooHigh) {
      warning = '⚠️ Baja más — rodilla (${knee.round()}°)';
    }

    switch (_phase) {
      case ExercisePhase.esperandoBajar:
        if (kneeValido && knee < goblet_kneeUp) {
          _phase = ExercisePhase.bajando;
          _repStartMs = ms;
          _minTorsoThisRep = 999;
          _minKneeThisRep  = 999;
        }
        return RepCounterResult(phase: 'Baje', shouldCallAI: false, liveWarning: warning);

      case ExercisePhase.bajando:
        if (kneeValido && knee < goblet_kneeBottom) {
          _phase = ExercisePhase.enFondo;
          _fondoStartMs = ms;
          _subioPronto = false;
          return RepCounterResult(phase: 'Fondo — mantén', shouldCallAI: false,
              liveWarning: warning, holdSecondsLeft: 2);
        }
        if (kneeValido && knee > goblet_kneeUp && _repStartMs != null) {
          _errorsThisRep.add('No bajó suficiente (${_minKneeThisRep.round()}°) — fondo no alcanzado');
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Bajando...', shouldCallAI: false, liveWarning: warning);

      case ExercisePhase.enFondo:
        final elapsed = ms - (_fondoStartMs ?? ms);
        final secondsLeft = ((_holdMs - elapsed) / 1000).ceil().clamp(0, 2);
        if (kneeValido && knee > goblet_kneeBottom + 15) {
          _subioPronto = true;
          _phase = ExercisePhase.subiendo;
          _errorsThisRep.add('Subió muy rápido — mantén 2 segundos abajo');
          return RepCounterResult(phase: 'Subiendo...', shouldCallAI: false, liveWarning: warning);
        }
        if (elapsed >= _holdMs) {
          _phase = ExercisePhase.esperandoSubir;
          return RepCounterResult(phase: 'Suba', shouldCallAI: false,
              liveWarning: warning, voice: 'Suba');
        }
        String? cv;
        if (elapsed < 200)                          cv = '2';
        else if (elapsed >= 1000 && elapsed < 1200) cv = '1';
        return RepCounterResult(phase: '$secondsLeft...', shouldCallAI: false,
            liveWarning: warning, holdSecondsLeft: secondsLeft, voice: cv);

      case ExercisePhase.esperandoSubir:
      case ExercisePhase.subiendo:
        if (kneeValido && knee > goblet_kneeUp) {
          if (_minTorsoThisRep < goblet_torsoLimit) {
            _errorsThisRep.add('Espalda muy inclinada (${_minTorsoThisRep.round()}°) — riesgo lumbar');
          }
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Subiendo...', shouldCallAI: false, liveWarning: warning);
    }
  }

  // ── CURL MARTILLO (de perfil) ──────────────────────────────────────────────
  // Cuenta: brazo estirado (abajo) → dobla (arriba) → mantener 2s → estira = 1 rep.
  // Usamos a.estadoBrazo (arriba=doblado, abajo=estirado) y a.elbow (ángulo codo).
  // ── PRESS MILITAR (de frente, sentado, ambos brazos) ───────────────────────
  // Cuenta: mancuernas en hombros (codo ~90°) → subir estirando (codo ~160°)
  // → mantener 2s arriba → bajar a hombros = 1 repetición.
  // En el press: ARRIBA = codo estirado (grande); ABAJO = codo doblado (chico).
  RepCounterResult _press(PoseAngles a, int ms) {
    final estado = a.estadoBrazo;
    final codo   = a.elbow;
    final err    = a.errorPress;

    // Rastreamos el codo MÁXIMO (¿llegó a estirar arriba?) y MÍNIMO de la rep
    if (codo > 10 && codo > _maxCodoThisRep) _maxCodoThisRep = codo;
    if (codo > 10 && codo < _minCodoThisRep) _minCodoThisRep = codo;

    // Registrar error de postura (espalda / bajó mucho / asimetría)
    if (err != ErrorPress.ninguno) {
      final razon = AngleCalculator.razonErrorPress(err);
      if (!_errorsThisRep.contains(razon)) _errorsThisRep.add(razon);
    }

    String? warning;
    if (err == ErrorPress.espalda) {
      warning = '⚠️ No arquees la espalda';
    } else if (err == ErrorPress.bajoMucho) {
      warning = '⚠️ Codos muy abiertos — cuida el hombro';
    } else if (err == ErrorPress.asimetrico) {
      warning = '⚠️ Sube parejo ambos brazos';
    } else if (err == ErrorPress.munecasAbiertas) {
      warning = '⚠️ Cierra las muñecas — cuida el hombro';
    }

    switch (_phase) {
      // Esperando empezar: debe estar ABAJO (mancuernas en hombros)
      case ExercisePhase.esperandoBajar:
        if (estado == EstadoBrazo.abajo) {
          _phase = ExercisePhase.bajando; // "bajando" = fase de subir el peso
          _repStartMs = ms;
          _maxCodoThisRep = 0;
          _minCodoThisRep = 999;
        }
        return RepCounterResult(phase: 'Suba', shouldCallAI: false, liveWarning: warning);

      // Subiendo el peso (estirando los brazos hacia arriba)
      case ExercisePhase.bajando:
        if (estado == EstadoBrazo.arriba) {
          _phase = ExercisePhase.enFondo;
          _fondoStartMs = ms;
          return RepCounterResult(phase: 'Arriba — mantén', shouldCallAI: false,
              liveWarning: warning, holdSecondsLeft: 2);
        }
        // Solo marcamos "no estiró" si DE VERDAD ya subió a la zona MEDIA
        // (codo salió de abajo, intentó subir) y luego volvió abajo sin completar.
        if (estado == EstadoBrazo.abajo &&
            _maxCodoThisRep > press_codoAbajo + 25 &&
            _maxCodoThisRep < press_codoNoSube) {
          _errorsThisRep.add('No estiró los brazos arriba (${_maxCodoThisRep.round()}°)');
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Suba', shouldCallAI: false, liveWarning: warning);

      // Arriba (estirado), mantener 2 segundos
      case ExercisePhase.enFondo:
        final elapsed = ms - (_fondoStartMs ?? ms);
        final secondsLeft = ((_holdMs - elapsed) / 1000).ceil().clamp(0, 2);
        if (estado == EstadoBrazo.abajo) {
          _phase = ExercisePhase.subiendo;
          _errorsThisRep.add('Bajó muy rápido — mantén 2 segundos arriba');
          return RepCounterResult(phase: 'Bajando...', shouldCallAI: false, liveWarning: warning);
        }
        if (elapsed >= _holdMs) {
          _phase = ExercisePhase.esperandoSubir;
          return RepCounterResult(phase: 'Baje', shouldCallAI: false,
              liveWarning: warning, voice: 'Baje');
        }
        String? cv;
        if (elapsed < 200)                          cv = '2';
        else if (elapsed >= 1000 && elapsed < 1200) cv = '1';
        return RepCounterResult(phase: '$secondsLeft...', shouldCallAI: false,
            liveWarning: warning, holdSecondsLeft: secondsLeft, voice: cv);

      // Bajando el peso a los hombros → al llegar abajo cuenta la rep
      case ExercisePhase.esperandoSubir:
      case ExercisePhase.subiendo:
        if (estado == EstadoBrazo.abajo) {
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Bajando...', shouldCallAI: false, liveWarning: warning);
    }
  }

  // ── ELEVACIONES LATERALES (de frente) ──────────────────────────────────────
  // Cuenta: brazos abajo → suben al nivel del hombro → mantener 2s → bajan = 1 rep.
  // Usamos a.estadoBrazo (altura del codo) y a.errorElevacion.
  RepCounterResult _elevacion(PoseAngles a, int ms) {
    final estado = a.estadoBrazo;
    final err    = a.errorElevacion;
    final angulo = a.codoVsHombroFrac; // el ángulo del hombro

    // Seguimos el ángulo MÁXIMO alcanzado en la subida (para "no subió")
    if (angulo > _maxCodoThisRep) _maxCodoThisRep = angulo;

    if (err != ErrorElevacion.ninguno) {
      final razon = AngleCalculator.razonErrorElevacion(err);
      if (!_errorsThisRep.contains(razon)) _errorsThisRep.add(razon);
    }

    String? warning;
    if (err == ErrorElevacion.codoMuyAlto) {
      warning = '⚠️ Muy arriba — riesgo de hombro';
    } else if (err == ErrorElevacion.brazoDoblado) {
      warning = '⚠️ Estira el brazo';
    }

    switch (_phase) {
      // Esperando abajo (reposo). Cuando empieza a subir, arranca la rep.
      case ExercisePhase.esperandoBajar:
        if (estado == EstadoBrazo.abajo) {
          return RepCounterResult(phase: 'Suba', shouldCallAI: false, liveWarning: warning);
        }
        // Empezó a subir (medio o arriba)
        _phase = ExercisePhase.bajando; // "bajando" = subiendo los brazos
        _repStartMs = ms;
        _maxCodoThisRep = angulo;
        return RepCounterResult(phase: 'Suba', shouldCallAI: false, liveWarning: warning);

      // Subiendo los brazos. Esperamos que llegue ARRIBA (ángulo correcto).
      case ExercisePhase.bajando:
        if (estado == EstadoBrazo.arriba) {
          _phase = ExercisePhase.enFondo;
          _fondoStartMs = ms;
          return RepCounterResult(phase: 'Arriba — mantén', shouldCallAI: false,
              liveWarning: warning, holdSecondsLeft: 2);
        }
        // Si volvió ABAJO sin haber llegado arriba → no subió suficiente
        if (estado == EstadoBrazo.abajo) {
          _errorsThisRep.add('No subió suficiente (${_maxCodoThisRep.round()}°) — sube hasta el hombro');
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Suba más...', shouldCallAI: false, liveWarning: warning);

      // Arriba (ángulo correcto), mantener 2 segundos
      case ExercisePhase.enFondo:
        final elapsed = ms - (_fondoStartMs ?? ms);
        final secondsLeft = ((_holdMs - elapsed) / 1000).ceil().clamp(0, 2);
        // Si baja antes de tiempo → bajó muy rápido
        if (estado == EstadoBrazo.abajo || estado == EstadoBrazo.medio) {
          _phase = ExercisePhase.subiendo;
          _errorsThisRep.add('Bajó muy rápido — mantén 2 segundos arriba');
          return RepCounterResult(phase: 'Bajando...', shouldCallAI: false, liveWarning: warning);
        }
        if (elapsed >= _holdMs) {
          _phase = ExercisePhase.esperandoSubir;
          return RepCounterResult(phase: 'Baje', shouldCallAI: false,
              liveWarning: warning, voice: 'Baje');
        }
        String? cv;
        if (elapsed < 200)                          cv = '2';
        else if (elapsed >= 1000 && elapsed < 1200) cv = '1';
        return RepCounterResult(phase: '$secondsLeft...', shouldCallAI: false,
            liveWarning: warning, holdSecondsLeft: secondsLeft, voice: cv);

      // Bajando los brazos → al llegar abajo cuenta la rep
      case ExercisePhase.esperandoSubir:
      case ExercisePhase.subiendo:
        if (estado == EstadoBrazo.abajo) {
          return _finishRep(ms);
        }
        return RepCounterResult(phase: 'Baje del todo...', shouldCallAI: false, liveWarning: warning);
    }
  }

  // ── Finalizar rep ──────────────────────────────────────────────────────────
  RepCounterResult _finishRep(int ms) {
    final isValid = _errorsThisRep.isEmpty;
    final errors  = List<String>.from(_errorsThisRep);

    // Guardar los ángulos representativos de esta rep según el ejercicio:
    //   piernas (sentadilla/goblet): tronco mínimo y rodilla mínima
    //   brazos (press/elevación): ángulo principal del codo/hombro
    int aTronco = 0;
    int aRodilla = 0;
    if (exercise == ExerciseType.sentadilla || exercise == ExerciseType.gobletSquat) {
      aTronco  = (_minTorsoThisRep < 900) ? _minTorsoThisRep.round() : 0;
      aRodilla = (_minKneeThisRep < 900) ? _minKneeThisRep.round() : 0;
    } else if (exercise == ExerciseType.pressMilitar) {
      // En press: guardamos el codo máximo (qué tan arriba llegó)
      aRodilla = (_maxCodoThisRep > 0) ? _maxCodoThisRep.round() : 0;
    } else if (exercise == ExerciseType.elevacionLateral) {
      // En elevaciones: guardamos el ángulo del hombro máximo
      aRodilla = (_maxCodoThisRep > 0) ? _maxCodoThisRep.round() : 0;
    }

    reps.add(RepResult(
      isValid: isValid,
      reason: errors.join(' · '),
      timestamp: ms,
      anguloTronco: aTronco,
      anguloRodilla: aRodilla,
    ));

    if (!isValid && _repStartMs != null) {
      errorTimestamps.add({'inicio': _repStartMs!, 'fin': ms});
    }

    _errorsThisRep.clear();
    _phase            = ExercisePhase.esperandoBajar;
    _repStartMs       = null;
    _fondoStartMs     = null;
    _subioPronto      = false;
    _minTorsoThisRep  = 999;
    _minKneeThisRep   = 999;
    _maxCodoThisRep   = 0;
    _minCodoThisRep   = 999;

    return RepCounterResult(
      phase: 'Rep completada',
      shouldCallAI: false,
      repCompleted: true,
      lastRepValid: isValid,
      lastRepErrors: errors,
    );
  }

  String get summary =>
      'Completaste $totalReps reps · $validReps válidas · $invalidReps no válidas';
}

class RepCounterResult {
  final String phase;
  final bool shouldCallAI;
  final bool repCompleted;
  final bool? lastRepValid;
  final List<String> lastRepErrors;
  final String? liveWarning;
  final String? voice;
  final int? holdSecondsLeft;

  RepCounterResult({
    required this.phase,
    required this.shouldCallAI,
    this.repCompleted = false,
    this.lastRepValid,
    this.lastRepErrors = const [],
    this.liveWarning,
    this.voice,
    this.holdSecondsLeft,
  });
}