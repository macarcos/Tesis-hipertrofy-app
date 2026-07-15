// ============================================================
// lib/screens/main_screen.dart
// Contenedor principal con la barra de abajo FIJA.
// Muestra un badge de mensajes sin leer sobre "Perfil".
// ============================================================
import 'package:flutter/material.dart';
import '../../services/entrenador_service.dart';
import 'home_screen.dart';
import 'progreso_screen.dart';
import 'perfil_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _gris = Color(0xFF1A1A1A);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _indice = 0;
  int _noLeidos = 0;
  final _servicio = EntrenadorService();

  final List<Widget> _pantallas = const [
    HomeScreen(),
    ProgresoScreen(),
    PerfilScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _cargarNoLeidos();
  }

  Future<void> _cargarNoLeidos() async {
    final n = await _servicio.misMensajesNoLeidos();
    if (mounted) setState(() => _noLeidos = n);
  }

  void _onTap(int i) {
    setState(() => _indice = i);
    // Al ir a Perfil, refrescamos el contador (puede que lea mensajes ahí)
    if (i == 2) {
      Future.delayed(const Duration(milliseconds: 500), _cargarNoLeidos);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: IndexedStack(
        index: _indice,
        children: _pantallas,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _gris,
        selectedItemColor: _amarillo,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        currentIndex: _indice,
        onTap: _onTap,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Panel'),
          const BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Progreso'),
          BottomNavigationBarItem(
            icon: _iconoConBadge(Icons.person, _noLeidos),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  // Ícono con una burbuja de número encima (si hay mensajes sin leer)
  Widget _iconoConBadge(IconData icono, int cantidad) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icono),
        if (cantidad > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _amarillo,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gris, width: 2),
              ),
              child: Text('$cantidad',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}