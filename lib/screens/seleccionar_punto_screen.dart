import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_colors.dart';
import '../widgets/app_buttons.dart';
import '../widgets/bogota_map.dart';

/// Pantalla para que el Cliente marque el punto EXACTO de su solicitud
/// tocando el mapa — en vez de depender solo del centro de la localidad.
/// El Colaborador después ve ese mismo punto (no una aproximación).
class SeleccionarPuntoScreen extends StatefulWidget {
  final LatLng centroInicial;
  final LatLng? puntoInicial;

  const SeleccionarPuntoScreen({
    super.key,
    required this.centroInicial,
    this.puntoInicial,
  });

  @override
  State<SeleccionarPuntoScreen> createState() => _SeleccionarPuntoScreenState();
}

class _SeleccionarPuntoScreenState extends State<SeleccionarPuntoScreen> {
  late LatLng? _punto = widget.puntoInicial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marcar el punto exacto')),
      body: Stack(
        children: [
          Positioned.fill(
            child: BogotaMap(
              centro: widget.puntoInicial ?? widget.centroInicial,
              zoom: 15,
              onTap: (punto) => setState(() => _punto = punto),
              marcadores: [
                if (_punto != null) buildPinMarker(punto: _punto!),
              ],
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Toca el mapa donde quieres que vaya el colaborador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: PrimaryButton(
              label: _punto == null ? 'TOCA EL MAPA PRIMERO' : 'USAR ESTE PUNTO',
              onPressed: _punto == null
                  ? null
                  : () => Navigator.of(context).pop(_punto),
            ),
          ),
        ],
      ),
    );
  }
}
