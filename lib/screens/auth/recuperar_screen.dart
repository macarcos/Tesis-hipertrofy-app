// ============================================================
// lib/screens/recuperar_screen.dart
// Recuperación por código de 6 dígitos (Supabase nativo)
// Paso 1: pedir correo -> Paso 2: código + nueva contraseña
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/validaciones.dart';

const _amarillo = Color(0xFFFFD600);
const _gris = Color(0xFF1A1A1A);

class RecuperarScreen extends StatefulWidget {
  const RecuperarScreen({super.key});

  @override
  State<RecuperarScreen> createState() => _RecuperarScreenState();
}

class _RecuperarScreenState extends State<RecuperarScreen> {
  final _supabase = Supabase.instance.client;
  final _emailCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  int _paso = 1;
  bool _cargando = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codigoCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _pedirCodigo() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _msg('Ingresa tu correo');
      return;
    }
    try {
      setState(() => _cargando = true);
      await _supabase.auth.resetPasswordForEmail(email);
      if (mounted) {
        _msg('Si el correo existe, recibirás un código.', exito: true);
        setState(() => _paso = 2);
      }
    } on AuthException catch (e) {
      _msg(e.message);
    } catch (_) {
      _msg('No se pudo enviar el código.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarPassword() async {
    final codigo = _codigoCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (codigo.length != 6) {
      _msg('El código tiene 6 dígitos');
      return;
    }

    // ── VALIDACIÓN DE CONTRASEÑA (misma regla que en el registro) ─────────
    final errPass = Validaciones.password(pass);
    if (errPass != null) {
      _msg(errPass);
      return;
    }

    if (pass != pass2) {
      _msg('Las contraseñas no coinciden');
      return;
    }

    try {
      setState(() => _cargando = true);
      // 1) Verificar el código (inicia sesión temporal)
      await _supabase.auth.verifyOTP(
        email: _emailCtrl.text.trim(),
        token: codigo,
        type: OtpType.recovery,
      );
      // 2) Actualizar la contraseña
      await _supabase.auth.updateUser(UserAttributes(password: pass));
      // 3) Cerrar sesión para entrar con la nueva
      await _supabase.auth.signOut();
      if (mounted) {
        _msg('Contraseña actualizada. Ya puedes iniciar sesión.', exito: true);
        await Future.delayed(const Duration(milliseconds: 1000));
        if (mounted) Navigator.pop(context);
      }
    } on AuthException catch (e) {
      _msg('Código inválido o expirado: ${e.message}');
    } catch (_) {
      _msg('No se pudo cambiar la contraseña.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _msg(String m, {bool exito = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: exito ? Colors.green[700] : Colors.red[700]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Recuperar contraseña', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.lock_reset, color: _amarillo, size: 64),
              const SizedBox(height: 20),
              if (_paso == 1) ..._pasoCorreo() else ..._pasoCodigo(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pasoCorreo() => [
        const Text('Ingresa tu correo y te enviaremos un código de 6 dígitos.',
            style: TextStyle(color: Colors.white70, fontSize: 15)),
        const SizedBox(height: 24),
        _label('CORREO ELECTRÓNICO'),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('usuario@correo.com'),
        ),
        const SizedBox(height: 28),
        _boton('Enviar código', _pedirCodigo),
      ];

  List<Widget> _pasoCodigo() => [
        Text('Ingresa el código enviado a ${_emailCtrl.text.trim()} y tu nueva contraseña.',
            style: const TextStyle(color: Colors.white70, fontSize: 15)),
        const SizedBox(height: 24),
        _label('CÓDIGO DE 6 DÍGITOS'),
        TextField(
          controller: _codigoCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.bold),
          decoration: _dec('••••••').copyWith(counterText: ''),
        ),
        const SizedBox(height: 16),
        _label('NUEVA CONTRASEÑA'),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('Mínimo 6 caracteres'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 4),
          child: Text(
            'Debe incluir al menos 1 mayúscula y 1 número',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        const SizedBox(height: 16),
        _label('CONFIRMAR CONTRASEÑA'),
        TextField(
          controller: _pass2Ctrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('Repite la contraseña'),
        ),
        const SizedBox(height: 26),
        _boton('Cambiar contraseña', _cambiarPassword),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _cargando ? null : _pedirCodigo,
            child: const Text('Reenviar código', style: TextStyle(color: Colors.white54)),
          ),
        ),
      ];

  Widget _boton(String texto, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _amarillo,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _cargando ? null : onTap,
          child: _cargando
              ? const SizedBox(
                  height: 22, width: 22,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: _gris,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _amarillo, width: 1.5)),
      );
}