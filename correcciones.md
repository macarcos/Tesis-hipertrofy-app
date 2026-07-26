# Revisión del proyecto — correcciones.md

> Documento generado a partir de una revisión de solo lectura de todo `lib/` (40 archivos, ~11.300 líneas) y `test/`. **No se modificó ningún archivo de código.** Aquí solo se documentan errores, código duplicado, código muerto y mejoras sugeridas para que se decidan y apliquen manualmente.

---

## 0. Resumen de prioridades (lo más importante primero)

1. **`test/widget_test.dart` está roto** — referencia una clase `MyApp` que no existe en el proyecto (la app real se llama `BioSmartApp`). El test no compila. Ver sección 1.1.
2. **Feature de seguridad incompleta en `angle_calculator.dart`**: la detección de "codo bajó demasiado" en press militar (`ErrorPress.bajoMucho`) tiene toda la infraestructura (constante, enum, texto de aviso) pero **nunca se activa** — el usuario nunca recibe ese aviso de riesgo de hombro. Ver 1.3.
3. **Contraseña: el máximo real (20 caracteres) contradice el máximo documentado (72)**, y la regla de "1 mayúscula + 1 número" que se muestra en la UI **no se valida realmente**. Ver 1.2 y 1.5.
4. **Posible pérdida de datos** en `OfflineStore.guardarPendiente`: si falla solo la copia del video, se pierde toda la sesión de entrenamiento (reps, errores, todo), no solo el video. Ver 1.6.
5. **Bug real de `RangeError`** en `mi_entrenador_screen.dart:240` si el nombre del entrenador es cadena vacía (no `null`). Ver 1.8.
6. **`chat_screen.dart`**: único flujo de escritura async del proyecto sin chequeo de `mounted` — puede lanzar `setState() called after dispose()`. Ver 1.9.
7. **Duplicación masiva de la paleta de colores** (`_amarillo/_negro/_gris`) copiada literalmente en ~20 archivos en vez de reutilizar `kAmarillo/kNegro/kGris` de `main.dart`. Ver 2.1.
8. **Duplicación grande entre `results_screen.dart` y `detalle_sesion_screen.dart`**: comparten más del 40% de su lógica de generación/descarga/compartición de PDF, casi copiada y pegada. Ver 2.2.
9. **Duplicación algorítmica en `rep_counter.dart`**: `_sentadilla` y `_gobletSquat` son básicamente el mismo algoritmo con distintas constantes. Ver 2.3.
10. **Manejo de errores silencioso generalizado**: 19 bloques `catch (_) {}` vacíos repartidos en 11 archivos, y varios servicios (`EntrenadorService`, `SessionService`) devuelven listas/valores vacíos ante *cualquier* error, indistinguible de "no hay datos". Dificulta diagnosticar fallos reales en producción. Ver 2.5 y 3.

---

## 1. Errores y bugs potenciales

### 1.1 `test/widget_test.dart`
- El test hace `pumpWidget(const MyApp())`, pero en `lib/main.dart` la clase se llama `BioSmartApp`. La clase `MyApp` no existe en ningún lugar del proyecto (verificado). Es el test de contador por defecto que genera Flutter al crear el proyecto y nunca se actualizó — **no compila, no corre**. Debería reescribirse para probar `BioSmartApp` o eliminarse si no aporta valor.

### 1.2 `lib/services/validaciones.dart`
- **Líneas ~35-40**: el comentario dice "máximo 72 (límite de bcrypt que usa Supabase)" pero el código rechaza contraseñas de más de **20** caracteres. Contraseñas de 21-72 caracteres, válidas según el propio diseño documentado, son rechazadas.
- **Líneas ~36-41**: `Validaciones.password` no exige mayúscula ni número, pese a que la UI (`signup_form.dart`, `recuperar_screen.dart`) muestra el texto *"Debe incluir al menos 1 mayúscula y 1 número"*. Una contraseña como `"abcdef"` pasa la validación sin problema — o falta el regex de complejidad, o sobra el texto de ayuda.
- **`limpiarTexto()`**: definida pero nunca llamada desde ningún lugar de `lib/` — código muerto (ver también sección 3).

### 1.3 `lib/services/angle_calculator.dart`
- Existe la constante `press_codoMuyAbajo`, el valor de enum `ErrorPress.bajoMucho`, su texto en `razonErrorPress` y su uso en `esErrorDeLesionPress`, pero **en ningún lugar de `_extractPress` se asigna `errorPress = ErrorPress.bajoMucho`**. Es una rama de detección de riesgo de hombro que nunca se dispara. Lo mismo aplica a `ErrorPress.noSube` (nunca asignado directamente; el mensaje equivalente en `rep_counter.dart` se agrega como string suelto en vez de vía el enum).
- Getters `wristAboveElbow`/`wristUp` se calculan pero ningún consumidor los lee — cómputo desperdiciado.
- `_BrazoElegido.knee` se asigna en `_mejorBrazo` pero nunca se lee en `_extractElevacion`.

### 1.4 `lib/main.dart`
- El primer `Supabase.initialize` tiene `.timeout(3s)`, pero el segundo intento dentro del `catch` (fallback) **no tiene ningún timeout**. Si ese segundo intento se cuelga (DNS lento, red inestable), el arranque "instantáneo" que promete el comentario del archivo deja de serlo.
- `dotenv.load(fileName: ".env")` no está envuelto en try/catch. Si el `.env` no se empaqueta correctamente en un build, esto lanza una excepción no capturada y la app crashea antes de llegar al try/catch de Supabase.

### 1.5 Contraseñas: tres implementaciones distintas de la misma regla
- `nueva_password_screen.dart` no usa `Validaciones.password`; implementa su propia regla mínima (`pass.length < 6`), sin tope máximo y sin los mismos `TextInputFormatter` que usan los otros formularios de contraseña.
- Resultado: `login_form.dart`/`signup_form.dart` (vía `Validaciones.password`), `recuperar_screen.dart` (también vía `Validaciones.password`) y `nueva_password_screen.dart` (regla propia) tienen tres criterios de validación de contraseña ligeramente distintos conviviendo en la misma app.

### 1.6 `lib/services/offline_store.dart`
- `guardarPendiente`: todo el trabajo (incluyendo los datos de reps/errores, que no dependen del video) está dentro de un único `try`. Si `orig.copy(videoLocal)` lanza (p. ej. disco lleno), la función retorna `null` y **se pierde el registro completo del entrenamiento**, no solo el video. Debería separarse: guardar el JSON siempre, y tratar el fallo de copia de video como no crítico.
- `leerPendientes()` ordena comparando strings ISO8601 directamente en vez de parsear a `DateTime` — funciona hoy porque el formato es lexicográficamente ordenable, pero es frágil ante cualquier cambio de formato.

### 1.7 `lib/services/sync_service.dart`
- Variable `total` declarada y nunca usada (el bucle usa `pendientes.length` directamente).
- El `.timeout()` sobre `R2Service.subirVideo` no cancela la operación subyacente: si expira, la función sigue sin video, pero la subida HTTP interna puede seguir corriendo en segundo plano sin control.
- No hay límite de reintentos: un pendiente corrupto (JSON con campos faltantes) podría reintentarse indefinidamente sin poder eliminarse ni notificar al usuario.

### 1.8 `lib/screens/usuario/mi_entrenador_screen.dart`
- **Línea ~240**:
  ```dart
  final iniciales = (_entrenador!['nombre']?.toString() ?? 'E')[0];
  ```
  Si `_entrenador!['nombre']` es una cadena **vacía** `''` (no `null`), el operador `??` no se activa (`''` no es `null`), y `''[0]` lanza `RangeError: Index out of range` en tiempo de ejecución. Comparar con `entrenador_perfil_screen.dart`, que sí hace `_nombre.isNotEmpty ? _nombre[0] : 'E'` correctamente.
- `_conectarConCodigo` y `_desconectar` llaman a los servicios sin `try/catch`. Si el servicio lanza una excepción (en vez de devolver un string de error), el `setState` que apaga el spinner (`_conectando`/`_desconectando`) nunca se ejecuta y el botón queda bloqueado en estado "cargando" indefinidamente.

### 1.9 `lib/screens/shared/chat_screen.dart`
- **`_enviar()`**: tras los `await _servicio.enviarMensajeConEjercicio(...)` / `await _servicio.enviarMensaje(...)`, se llaman varios `setState(...)` y `await _cargar()` **sin comprobar `mounted`**. Si el usuario cierra la pantalla de chat justo mientras el mensaje se está enviando, esto lanza `setState() called after dispose()`. Es el único archivo del lote de pantallas sin esta protección en un flujo de escritura.
- `_irAlMensaje`: calcula la posición de scroll con `(indice / _mensajes.length) * maxScrollExtent`, asumiendo que todos los mensajes miden lo mismo en pantalla. Con burbujas de distinta altura (texto largo, tarjetas de ejercicio adjunto), el salto puede quedar bastante desviado del mensaje real.

### 1.10 `lib/screens/usuario/progreso_screen.dart`
- `(_prog['eficienciaPorDia'] as List?)?.cast<double>()`: si el backend llega a enviar una lista de `int` en vez de `double` (algo común al deserializar JSON de Supabase), `.cast<double>()` lanza `CastError` en vez de convertir. Más seguro: `.map((e) => (e as num).toDouble()).toList()`.

### 1.11 `lib/screens/usuario/camera_screen.dart`
- `dispose()` llama a `FlutterScreenRecording.stopRecordScreen` sin `await` (porque `dispose()` es síncrono) dentro de un `try{}catch(_){}`. Si el usuario sale por el botón atrás del sistema (no por el botón "X" que sí hace `await` correctamente), la grabación de pantalla puede quedar corriendo un instante sin garantía de haberse detenido antes de destruir el widget. No hay `PopScope`/`WillPopScope` que intercepte el back del sistema para forzar la limpieza async.
- `_initCamera`: el `catch` solo hace `debugPrint`. Si falla (permiso denegado, cámara ocupada), `_isReady` nunca pasa a `true` y la pantalla se queda en "Iniciando sensores..." indefinidamente, sin mensaje de error ni forma de reintentar/salir.
- Hay una condición en la UI que siempre es verdadera porque cubre los 4 valores posibles del enum `ScreenState` — código muerto/redundante, se puede simplificar.

### 1.12 `lib/services/session_service.dart`
- `hora_inicio` y `hora_fin` se graban ambos como `DateTime.now()` en el mismo insert — quedan prácticamente idénticos (diferencia de milisegundos), por lo que **no reflejan la duración real** del entrenamiento pese a existir dos columnas separadas para eso.

### 1.13 `lib/services/entrenador_service.dart`
- `misUsuarios()`: por cada usuario conectado llama `await contarNoLeidos(u['id'])` **secuencialmente dentro de un for**, en vez de una query agregada o `Future.wait` en paralelo. Con muchos usuarios, esto escala mal en latencia (N+1).
- `conversacionCon`: construye el filtro `.or(...)` por interpolación de string en vez de builders tipados de Supabase — frágil si `otroId` no está garantizado como UUID válido.
- `enviarMensaje`/`enviarMensajeConEjercicio`: asumen que **cualquier** excepción del insert significa "estás bloqueado", cuando podría ser cualquier otro error (red, validación, RLS por otro motivo). El mensaje mostrado al usuario puede ser incorrecto en esos casos.

### 1.14 `lib/services/pdf_service.dart`
- El parámetro `errores` se declara y se reenvía en cadena por varios métodos (`_construir`, `generarBytes`, `descargar`, `compartir`) pero **nunca se lee** dentro de `_construir` — aparenta usar los errores de la sesión en el PDF, pero no lo hace.
- `descargar()` asume ruta hardcodeada de Android (`/storage/emulated/0/Download`); en Android 10+ con scoped storage o en iOS siempre cae al fallback por `catch` en vez de detectar la plataforma explícitamente.

### 1.15 Otros puntos menores
- `escanear_qr_screen.dart`: el ícono de linterna es estático y no refleja si el flash está realmente encendido/apagado (no hay listener sobre `_controller.torchState`).
- `entrenador_main_screen.dart`: cada tap en la barra inferior recarga datos aunque se toque la pestaña ya activa (parece intencional según comentario, pero implica una consulta de red extra innecesaria en ese caso).
- `elegir_rol_screen.dart`: la detección de "usuario borrado" se basa en `msg.contains('users')`, un chequeo muy amplio — cualquier error de Supabase/Postgrest que mencione "users" en cualquier contexto dispararía un cierre de sesión inesperado.
- `signup_form.dart`: `_signUp()` y `_verifyOtp()` solo capturan `AuthException`. Un error de red (`SocketException`, timeout, `PostgrestException`) no muestra ningún mensaje al usuario — el spinner simplemente se apaga sin explicación.
- Patrón repetido en `login_form.dart`, `signup_form.dart`, `recuperar_screen.dart`, `nueva_password_screen.dart`: los bloques `catch` llaman a `_msg(...)` (que usa `ScaffoldMessenger.of(context)`) sin comprobar `mounted` primero, aunque el `finally` sí lo comprueba para el `setState`. Riesgo de excepción sobre `BuildContext` desmontado si el usuario navega hacia atrás mientras la petición está en curso.

---

## 2. Código duplicado

### 2.1 Paleta de colores redeclarada en ~20 archivos (la duplicación más extendida del proyecto)
`lib/main.dart` ya define `kAmarillo`, `kNegro`, `kGris` como constantes globales inyectadas en el `ThemeData`. Sin embargo, prácticamente **todos** los archivos de `lib/screens/` y `pdf_service.dart` vuelven a declarar sus propias constantes privadas idénticas:
```dart
const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);
```
No existe ningún archivo central de tema/constantes (`lib/theme.dart`, `lib/constants.dart`, etc.). Cualquier cambio de paleta de marca hoy requiere editar ~20 archivos manualmente en vez de uno solo.

### 2.2 Duplicación grande de lógica de PDF entre `results_screen.dart` y `detalle_sesion_screen.dart`
Ambos archivos duplican casi al pie de la letra: `_generarDocumento`, `_previsualizarPdf`, `_descargarPdf(Guardado)`, `_compartirPdf` — generar bytes con `PdfService.generarBytes`, subir con `R2Service`, actualizar `SessionService().actualizarPdfUrl`, manejo de `mounted`/SnackBars de error. También duplican: `_formatoTiempo` (idéntico), el widget de "rep tile" (`_RepTile` vs `_repTile()`), y el widget de diagnóstico médico (`_MedicalReportCard` vs `_diagnostico()`, uno tipado y otro con `Map` crudo). Es la duplicación de mayor riesgo: un bug corregido en un archivo puede no propagarse al otro.

### 2.3 `lib/services/rep_counter.dart`
- `_sentadilla` y `_gobletSquat` son prácticamente el mismo algoritmo de máquina de estados; solo cambian las constantes (`squat_*` vs `goblet_*`).
- El bloque de cuenta regresiva de voz (`if (elapsed < 200) cv = '2'; else if (elapsed >= 1000 && elapsed < 1200) cv = '1';` y el cálculo de `secondsLeft`) se repite **4 veces**, una por variante de ejercicio.
- `_minCodoThisRep` y `_subioPronto` se actualizan en varios puntos pero nunca se leen — variables de estado muertas.

### 2.4 Patrón "tarjeta de sesión / stat pill" repetido en 5 archivos
`_StatPill` (results_screen.dart), `_pill` (detalle_sesion_screen.dart), `_tarjeta` (progreso_screen.dart), `_statCard` (home_screen.dart) y `_chip` (historial_screen.dart) son variantes casi idénticas de "tarjeta con número + etiqueta". Del mismo modo, `_historialTile`/`_sesionTile`/`_tile`/`_tilePendiente` en `home_screen.dart`, `progreso_screen.dart` y `historial_screen.dart` son cuatro variantes de "tarjeta de sesión con nombre, %, fecha".

### 2.5 Diálogo de confirmación reimplementado en al menos 7 lugares
El mismo `AlertDialog` (fondo gris, título blanco, botón "Cancelar" en gris claro, botón de acción en rojo) se reimplementa inline en: `entrenador_usuario_screen.dart` (x2), `entrenador_bloqueados_screen.dart`, `historial_screen.dart`, `perfil_screen.dart` (x2), `mi_entrenador_screen.dart` y `detalle_sesion_screen.dart` — pese a que `entrenador_perfil_screen.dart` ya tiene un helper `_confirmar` reutilizable que ilustra cómo unificarlo.

### 2.6 Formularios de auth (`login_form.dart`, `signup_form.dart`, `recuperar_screen.dart`, `nueva_password_screen.dart`)
Los cuatro repiten: helpers `_label`/`_dec` (decoración de `TextField`), el botón grande amarillo con spinner de carga, y la URL de redirect hardcodeada `'io.supabase.biosmart://login-callback/'` (repetida igual en `login_form.dart` y `signup_form.dart`).

### 2.7 Otras duplicaciones puntuales
- `_msg()` (helper de SnackBar) idéntico en `historial_screen.dart` y `mi_entrenador_screen.dart`.
- `SessionService.sesionPorId` duplica exactamente `EntrenadorService.sesionPorId` (misma query, mismo catch).
- `R2Service.subirVideo` y `subirPdf` repiten casi el mismo flujo (pedir URL firmada → PUT → comprobar status → loguear); factorizable en un helper común.
- `AiCoachService.getMedicalReport` y `getReporteCompleto` arman prácticamente el mismo `http.post` (misma URL, mismos headers, body casi igual).
- `entrenador_usuarios_screen.dart` y `entrenador_bloqueados_screen.dart` calculan `nombre`/`email`/`inicial` y arman el "tile de usuario" (Container + ListTile + CircleAvatar) de forma casi literal repetida.
- `SessionService` tiene 3 métodos (`obtenerHistorial`, `obtenerSesionesDeHoy`, `obtenerTodoElHistorial`) con el mismo query base variando solo filtro/orden/límite.
- El patrón de suavizado "agregar a buffer, recortar a 5, promediar" se repite 3 veces casi idéntico en `angle_calculator.dart`.

---

## 3. Código muerto / sin uso

- **`test/widget_test.dart`**: referencia `MyApp`, clase inexistente (ver 1.1).
- **`Validaciones.limpiarTexto()`** (`validaciones.dart`): no se llama desde ningún lugar del proyecto.
- **`AiCoachService.analyzeLive()`** y la clase **`LiveFeedback`** (incl. `fromJson`) en `ai_coach_service.dart`: no se llaman desde ninguna pantalla (el feedback en vivo real viene de `angle_calculator`/`rep_counter`).
- **`_estudiosCientificos`** en `ai_coach_service.dart`: constante de ~13 líneas nunca referenciada.
- **`ErrorPress.bajoMucho`** y **`ErrorPress.noSube`** en `angle_calculator.dart`: enums nunca asignados (ver 1.3 — más que "muertos", son una feature a medio implementar).
- **Getters de `PoseAngles`** en `angle_calculator.dart`: `hipSquat`, `torsoAngle`, `leftElbow`, `rightElbow`, `leftKnee`, `rightKnee`, `leftHip`, `rightHip`, `leftWristAboveElbow`, `rightWristAboveElbow` — ninguno se usa fuera de la propia clase. `toJson()` tampoco se llama desde ningún lado.
- **`_BrazoElegido.knee`** en `angle_calculator.dart`: se asigna pero nunca se lee.
- **`_minCodoThisRep`** y **`_subioPronto`** en `rep_counter.dart`: se actualizan pero nunca se leen.
- **`_messenger`** (campo `ScaffoldMessengerState?`) en `results_screen.dart`: se declara y se asigna en `didChangeDependencies`, pero nunca se usa después — el archivo sigue usando `ScaffoldMessenger.of(context)` directamente en cada callback.
- **Parámetro `errores`** en `pdf_service.dart`: se reenvía por 4 métodos pero nunca se lee dentro de `_construir` (ver 1.14).
- **`total`** en `sync_service.dart`: variable declarada y nunca usada.

---

## 4. Mejoras estructurales (no son bugs, pero valen la pena)

- **`camera_screen.dart` (1785 líneas)**: mezcla en una sola clase control de cámara, procesamiento de imagen YUV→NV21 con curva gamma manual (~95 líneas de álgebra de píxeles), auto-ajuste de exposición, TTS, conteo de repeticiones y toda la UI. Buen candidato para extraer el procesamiento de imagen a una clase/servicio independiente (`ImageEnhancer`) testeable sin depender de widgets. También tiene numerosos "magic numbers" de tiempo (800, 300, 500, 1500, 5000 ms, etc.) sin nombre.
- **`pdf_service.dart` (628 líneas)**: ~25 métodos estáticos privados de construcción de widgets del PDF en una sola clase ("god class" de presentación). Podría dividirse por hoja/sección para legibilidad.
- **`results_screen.dart`**: `_procesarYGuardar` es un método de ~110 líneas que orquesta detección de internet, subida de video, llamada IA, guardado en Supabase y guardado offline, todo mezclado con `setState`. Sería más testeable como un controlador independiente de la UI.
- **`angle_calculator.dart`**: `extract()` mezcla 3 modos de medición completamente distintos (piernas/press/elevación) en un solo método estático con muchos umbrales "mágicos" documentados solo por comentarios `// ← AJUSTA`. Más mantenible como estrategias separadas por ejercicio.
- **Manejo de errores silencioso generalizado**: 19 bloques `catch (_) {}` vacíos en 11 archivos (`elegir_rol_screen.dart`, `entrenador_perfil_screen.dart`, `entrenador_inicio_screen.dart`, `historial_screen.dart`, `entrenador_service.dart`, `session_service.dart`, `camera_screen.dart`, `main.dart`, `sync_service.dart`, `detalle_sesion_screen.dart`, `ai_coach_service.dart`). Combinado con servicios que devuelven `[]`/`null` ante cualquier error, hace indistinguible "no hay datos" de "falló la red", tanto para el usuario como para quien tenga que depurar un reporte de bug en producción.
- **`backend_config.dart`**: la URL de Supabase está hardcodeada; el comentario aclara que es información pública por diseño (no es un problema de seguridad), pero por consistencia con el resto de configuración (que sí vive en `.env`) podría moverse también ahí.
- **`login_form.dart`**: tras un login exitoso, tanto `AuthGate` como el propio `login_form` consultan `perfiles.cuenta_bloqueada` de forma redundante, lo que puede causar un parpadeo de navegación. No es un bug funcional (ambas verificaciones actúan como red de seguridad), pero es lógica duplicada que podría centralizarse en un solo lugar.
- **`main_screen.dart` (usuario)**: usa `IndexedStack` con las 3 pantallas mantenidas vivas permanentemente, por lo que `HomeScreen`/`ProgresoScreen` solo cargan datos una vez en `initState` y no se refrescan al cambiar de pestaña. Puede mostrar datos desactualizados tras entrenar si el usuario navega directo a "Progreso".
- **`fecha_helper.dart`**: `formatear()` no maneja explícitamente fechas futuras (diferencia de días negativa); no crashea, pero el comportamiento no está documentado.

---

## 5. Notas finales

- No se encontraron secretos ni credenciales expuestas en el repositorio: `.env` está correctamente listado en `.gitignore` y no está trackeado por git.
- No se ejecutó `flutter analyze` como parte de esta revisión; se recomienda correrlo aparte para capturar warnings del linter (`flutter_lints`) que complementen este documento.
- Todos los hallazgos anteriores son observacionales — **no se aplicó ningún cambio de código** como parte de esta revisión.
