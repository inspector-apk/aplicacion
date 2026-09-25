import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../services/location_service.dart';
import '../widgets/app_buttons.dart';
import 'splash_screen.dart';

/// Primera pantalla que ve el usuario: solicita el permiso de ubicación
/// antes de poder llegar a Login/Registro, para poder centrar el mapa
/// de Bogotá y las solicitudes cercanas más adelante.
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _cargando = false;

  Future<void> _continuar() async {
    setState(() => _cargando = true);
    try {
      await LocationService.solicitarPermiso();
    } finally {
      _irASplash();
    }
  }

  void _omitir() {
    if (_cargando) return;
    _irASplash();
  }

  void _irASplash() {
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(AppRoutes.fade(const SplashScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 1.4),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.accentText,
                  size: 46,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Activa tu ubicación',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Inspector usa tu ubicación para mostrarte el mapa y '
                'conectar solicitudes cercanas en Bogotá. Puedes '
                'cambiar este permiso luego desde los ajustes de tu '
                'dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 4),
              PrimaryButton(
                label: 'PERMITIR UBICACIÓN',
                isLoading: _cargando,
                onPressed: _continuar,
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _cargando ? null : _omitir,
                child: const Text(
                  'Ahora no',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
