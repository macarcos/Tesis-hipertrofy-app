// ============================================================
// lib/screens/usuario/mi_entrenador_screen.dart
// Lado USUARIO: conectarse con entrenador por código O por QR + chat
// + opción para DESCONECTARSE del entrenador.
// ============================================================
import 'package:flutter/material.dart';
import '../../services/entrenador_service.dart';
import '../shared/chat_screen.dart';
import '../entrenador/escanear_qr_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class MiEntrenadorScreen extends StatefulWidget {
  const MiEntrenadorScreen({super.key});

  @override
  State<MiEntrenadorScreen> createState() => _MiEntrenadorScreenState();
}

class _MiEntrenadorScreenState extends State<MiEntrenadorScreen> {
  final _servicio = EntrenadorService();
  final _codigoCtrl = TextEditingController();

  Map<String, dynamic>? _entrenador;
  bool _cargando = true;
  bool _conectando = false;
  bool _desconectando = false;
  int _noLeidos = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final ent = await _servicio.miEntrenador();
    final noLeidos = await _servicio.misMensajesNoLeidos();
    if (mounted) setState(() {
      _entrenador = ent;
      _noLeidos = noLeidos;
      _cargando = false;
    });
  }

  Future<void> _conectar() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty) { _msg('Ingresa el código'); return; }
    await _conectarConCodigo(codigo);
  }

  // Lógica de conexión reutilizable (la usa tanto el botón manual como el QR)
  Future<void> _conectarConCodigo(String codigo) async {
    setState(() => _conectando = true);
    final error = await _servicio.conectarConCodigo(codigo);
    if (mounted) setState(() => _conectando = false);

    if (error != null) {
      _msg(error);
    } else {
      _msg('¡Conectado con tu entrenador!', exito: true);
      _codigoCtrl.clear();
      _cargar();
    }
  }

  // Abrir la cámara para escanear el QR del entrenador
  Future<void> _escanearQr() async {
    final codigoLeido = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const EscanearQrScreen()),
    );

    // Si el usuario escaneó algo, intentar conectar con ese código
    if (codigoLeido != null && codigoLeido.isNotEmpty) {
      await _conectarConCodigo(codigoLeido);
    }
  }

  // Desconectarse del entrenador (con confirmación)
  Future<void> _desconectar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _gris,
        title: const Text('Desconectar entrenador',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Seguro que quieres desconectarte de tu entrenador? '
          'Dejará de ver tus sesiones. Podrás volver a conectarte '
          'con su código cuando quieras.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _desconectando = true);
    final error = await _servicio.desconectarDeEntrenador();
    if (!mounted) return;
    setState(() => _desconectando = false);

    if (error != null) {
      _msg(error);
    } else {
      _msg('Te desconectaste del entrenador', exito: true);
      setState(() => _entrenador = null); // ya no tiene entrenador
      _cargar();
    }
  }

  void _msg(String m, {bool exito = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: exito ? Colors.green[700] : Colors.red[700]),
      );

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mi Entrenador', style: TextStyle(color: Colors.white)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _amarillo))
          : _entrenador == null
              ? _sinEntrenador()
              : _conEntrenador(),
    );
  }

  // Si NO tiene entrenador: pedir código O escanear QR
  Widget _sinEntrenador() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.fitness_center, color: _amarillo, size: 60),
          const SizedBox(height: 20),
          const Text('Conéctate con tu entrenador',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Pídele su código de 6 dígitos e ingrésalo aquí, '
              'o escanea su código QR.',
              style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          TextField(
            controller: _codigoCtrl,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
                color: Colors.white, fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'ABC123',
              hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
              filled: true,
              fillColor: _gris,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _amarillo,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _conectando ? null : _conectar,
              child: _conectando
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('Conectar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),

          // ── Separador "O" ──
          const SizedBox(height: 24),
          const Row(children: [
            Expanded(child: Divider(color: Colors.grey)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('O', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: Divider(color: Colors.grey)),
          ]),
          const SizedBox(height: 24),

          // ── Botón ESCANEAR QR (abre la cámara) ──
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _amarillo, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.qr_code_scanner, color: _amarillo),
              label: const Text('Escanear código QR',
                  style: TextStyle(color: _amarillo, fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _conectando ? null : _escanearQr,
            ),
          ),
        ],
      ),
    );
  }

  // Si YA tiene entrenador: mostrarlo + botón de chat + desconectar
  Widget _conEntrenador() {
    final nombre = '${_entrenador!['nombre'] ?? ''} ${_entrenador!['apellido'] ?? ''}';
    final email = _entrenador!['correo'] ?? '';
    final iniciales = (_entrenador!['nombre']?.toString() ?? 'E')[0];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _gris,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _amarillo.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _amarillo,
                  child: Text(iniciales.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tu entrenador',
                          style: TextStyle(color: _amarillo, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(nombre.trim(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _amarillo,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.chat_bubble),
              label: Text(
                  _noLeidos > 0
                      ? 'Enviar mensaje ($_noLeidos nuevo${_noLeidos > 1 ? 's' : ''})'
                      : 'Enviar mensaje',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    otroId: _entrenador!['id'],
                    otroNombre: nombre.trim(),
                  ),
                ));
                _cargar(); // refrescar al volver del chat
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── Botón DESCONECTAR entrenador ──
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _desconectando
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2))
                  : const Icon(Icons.link_off, color: Colors.redAccent),
              label: Text(_desconectando ? 'Desconectando...' : 'Desconectar entrenador',
                  style: const TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: _desconectando ? null : _desconectar,
            ),
          ),
        ],
      ),
    );
  }
}