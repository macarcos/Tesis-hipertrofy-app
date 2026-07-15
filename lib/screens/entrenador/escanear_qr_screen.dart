// ============================================================
// lib/screens/escanear_qr_screen.dart
// Lado USUARIO: abre la cámara, escanea el QR del entrenador
// y devuelve el código leído (string) a la pantalla anterior.
// Usa el paquete mobile_scanner.
// ============================================================
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);

class EscanearQrScreen extends StatefulWidget {
  const EscanearQrScreen({super.key});

  @override
  State<EscanearQrScreen> createState() => _EscanearQrScreenState();
}

class _EscanearQrScreenState extends State<EscanearQrScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _yaDetectado = false; // evita leer el mismo QR mil veces

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _alDetectar(BarcodeCapture captura) {
    if (_yaDetectado) return;
    final codigos = captura.barcodes;
    if (codigos.isEmpty) return;

    final valor = codigos.first.rawValue;
    if (valor == null || valor.trim().isEmpty) return;

    _yaDetectado = true;
    // Devolver el código leído a la pantalla anterior (MiEntrenadorScreen)
    Navigator.pop(context, valor.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Escanear código', style: TextStyle(color: Colors.white)),
        actions: [
          // Botón para encender/apagar la linterna
          IconButton(
            icon: const Icon(Icons.flash_on, color: _amarillo),
            onPressed: () => _controller.toggleTorch(),
          ),
          // Botón para cambiar de cámara (frontal/trasera)
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: _amarillo),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // La cámara que escanea
          MobileScanner(
            controller: _controller,
            onDetect: _alDetectar,
          ),

          // Marco visual para guiar al usuario dónde apuntar
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: _amarillo, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),

          // Texto de ayuda abajo
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Apunta la cámara al código QR de tu entrenador',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}