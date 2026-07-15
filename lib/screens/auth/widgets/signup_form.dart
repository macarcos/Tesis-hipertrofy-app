// ============================================================
// lib/screens/widgets/signup_form.dart
// Registro: Nombre + Apellido + Correo + Contraseña + rol
// OTP de 6 dígitos + Google. Amarillo y negro.
// CON validaciones de entrada (nombres solo letras, correo válido, etc.)
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/validaciones.dart';

const _amarillo = Color(0xFFFFD600);
const _gris = Color(0xFF1A1A1A);

class SignUpForm extends StatefulWidget {
  const SignUpForm({super.key});

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _isLoading = false;
  bool _isCodeSent = false;
  String _rol = 'usuario';

  Future<void> _signUp() async {
    final nombre = _nombreCtrl.text.trim();
    final apellido = _apellidoCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    // ── VALIDACIONES DE ENTRADA ───────────────────────────────────────────
    final errNombre = Validaciones.nombre(nombre, campo: 'nombre');
    if (errNombre != null) { _msg(errNombre); return; }

    final errApellido = Validaciones.nombre(apellido, campo: 'apellido');
    if (errApellido != null) { _msg(errApellido); return; }

    final errEmail = Validaciones.email(email);
    if (errEmail != null) { _msg(errEmail); return; }

    final errPass = Validaciones.password(pass);
    if (errPass != null) { _msg(errPass); return; }

    if (pass != pass2) {
      _msg('Las contraseñas no coinciden');
      return;
    }

    try {
      setState(() => _isLoading = true);
      final res = await _supabase.auth.signUp(
        email: email,
        password: pass,
        data: {
          'first_name': nombre,
          'last_name': apellido,
          'rol': _rol,
        },
      );

      // Detectar correo YA registrado:
      // Con "Confirm email" activo, Supabase NO da error si el correo existe,
      // sino que devuelve un usuario con la lista de identities VACÍA.
      final identities = res.user?.identities;
      if (identities != null && identities.isEmpty) {
        if (mounted) {
          _msg('Este correo ya está registrado. Inicia sesión.');
          setState(() => _isLoading = false);
        }
        return;
      }

      if (mounted) {
        setState(() => _isCodeSent = true);
        _msg('Código enviado. Revisa tu correo.', exito: true);
      }
    } on AuthException catch (e) {
      _msg(_traducir(e.message));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final codigo = _otpCtrl.text.trim();
    if (codigo.length != 6) {
      _msg('El código tiene 6 dígitos');
      return;
    }
    try {
      setState(() => _isLoading = true);
      await _supabase.auth.verifyOTP(
        email: _emailCtrl.text.trim(),
        token: codigo,
        type: OtpType.signup,
      );
      if (mounted) _msg('¡Cuenta verificada con éxito!', exito: true);
      // El AuthGate detecta la sesión y enruta solo
    } on AuthException catch (e) {
      _msg('Código incorrecto: ${e.message}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.biosmart://login-callback/',
      );
    } catch (e) {
      _msg('Error con Google: $e');
    }
  }

  void _msg(String m, {bool exito = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: exito ? Colors.green[700] : Colors.red[700]),
      );

  String _traducir(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Este correo ya está registrado.';
    }
    if (m.contains('invalid email')) return 'El correo no es válido.';
    return msg;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(
            _isCodeSent ? Icons.mark_email_read : Icons.person_add_alt_1,
            size: 60, color: _amarillo,
          ),
          const SizedBox(height: 20),

          if (!_isCodeSent) ...[
            _label('NOMBRE'),
            // Solo permite letras y espacios mientras escribe
            _input(_nombreCtrl, 'Marcos', soloLetras: true, maxLen: 40),
            const SizedBox(height: 14),
            _label('APELLIDO'),
            _input(_apellidoCtrl, 'García', soloLetras: true, maxLen: 40),
            const SizedBox(height: 14),
            _label('CORREO ELECTRÓNICO'),
            _input(_emailCtrl, 'marcos@correo.com',
                tipo: TextInputType.emailAddress, soloEmail: true, maxLen: 100),
            const SizedBox(height: 14),
            _label('CONTRASEÑA'),
            _input(_passCtrl, 'Mínimo 6 caracteres', oculto: true, maxLen: 72),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Debe incluir al menos 1 mayúscula y 1 número',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            const SizedBox(height: 14),
            _label('CONFIRMAR CONTRASEÑA'),
            _input(_pass2Ctrl, 'Repite tu contraseña', oculto: true, maxLen: 72),
            const SizedBox(height: 18),

            _label('TIPO DE CUENTA'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _tarjetaRol('Usuario', Icons.person, 'usuario')),
                const SizedBox(width: 12),
                Expanded(child: _tarjetaRol('Entrenador', Icons.fitness_center, 'entrenador')),
              ],
            ),
            const SizedBox(height: 24),

            _botonAmarillo('Crear mi cuenta  →', _isLoading ? null : _signUp),
            const SizedBox(height: 20),

            const Row(children: [
              Expanded(child: Divider(color: Colors.grey)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('O', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: Colors.grey)),
            ]),
            const SizedBox(height: 20),

            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.g_mobiledata, size: 34, color: Colors.white),
                label: const Text('Continuar con Google',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: _signInWithGoogle,
              ),
            ),
          ] else ...[
            const Text('Ingresa el código de 6 dígitos que enviamos a tu correo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70)),
            const SizedBox(height: 24),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              // Solo números en el código
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.bold),
              decoration: _dec('••••••').copyWith(counterText: ''),
            ),
            const SizedBox(height: 18),
            _botonAmarillo('Verificar Código', _isLoading ? null : _verifyOtp),
            TextButton(
              onPressed: () => setState(() => _isCodeSent = false),
              child: const Text('Volver e intentar con otro correo',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(color: _amarillo)),
          ],
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
      );

  Widget _input(TextEditingController c, String hint,
      {bool oculto = false, TextInputType? tipo, bool soloLetras = false,
       bool soloEmail = false, int? maxLen}) {
    // Filtros de entrada: bloquean caracteres inválidos MIENTRAS se escribe
    final List<TextInputFormatter> filtros = [];
    if (soloLetras) {
      // Solo letras (con tildes/ñ) y espacios; bloquea <, >, símbolos, números
      filtros.add(FilteringTextInputFormatter.allow(
          RegExp(r"[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]")));
    }
    if (soloEmail) {
      // Solo caracteres válidos en un correo (bloquea <>{}#$ etc.)
      filtros.add(FilteringTextInputFormatter.allow(
          RegExp(r'[a-zA-Z0-9@._%+\-]')));
    }
    if (maxLen != null) {
      filtros.add(LengthLimitingTextInputFormatter(maxLen));
    }
    return TextField(
      controller: c,
      obscureText: oculto,
      keyboardType: tipo,
      inputFormatters: filtros.isEmpty ? null : filtros,
      style: const TextStyle(color: Colors.white),
      decoration: _dec(hint),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: _gris,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _amarillo, width: 1.5)),
      );

  Widget _botonAmarillo(String texto, VoidCallback? onTap) => SizedBox(
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _amarillo,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onTap,
          child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _tarjetaRol(String titulo, IconData icono, String valor) {
    final sel = _rol == valor;
    return GestureDetector(
      onTap: () => setState(() => _rol = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: sel ? _amarillo.withOpacity(0.12) : _gris,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _amarillo : Colors.transparent, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icono, color: sel ? _amarillo : Colors.white54, size: 26),
            const SizedBox(height: 6),
            Text(titulo,
                style: TextStyle(
                    color: sel ? _amarillo : Colors.white70, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}