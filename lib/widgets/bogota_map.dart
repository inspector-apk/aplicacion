import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_colors.dart';
import '../core/bogota_localidades.dart';

/// Mapa de Bogotá reutilizable (estilo Uber/inDrive: mapa a pantalla
/// completa detrás, con contenido superpuesto encima). Usa mosaicos de
/// OpenStreetMap, así que necesita conexión a internet para verse; los
/// datos de la app (usuarios, solicitudes) siguen siendo 100% locales.
class BogotaMap extends StatelessWidget {
  final List<Marker> marcadores;
  final LatLng? centro;
  final double zoom;

  const BogotaMap({
    super.key,
    this.marcadores = const [],
    this.centro,
    this.zoom = 12,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: centro ?? kBogotaCenter,
        initialZoom: zoom,
        minZoom: 10,
        maxZoom: 17,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.inspector.inspector',
        ),
        MarkerLayer(markers: marcadores),
      ],
    );
  }
}

Marker buildPinMarker({
  required LatLng punto,
  Color color = AppColors.accent,
  IconData icon = Icons.location_on,
}) {
  return Marker(
    point: punto,
    width: 42,
    height: 42,
    child: Icon(icon, color: color, size: 38),
  );
}

/// Colaborador disponible en el mapa, al estilo de los carros de
/// Uber/Didi — pero con la lupa de "Inspector" en vez de un vehículo,
/// dentro de una placa dorada como el resto de la identidad de la app.
Marker buildColaboradorMarker({required LatLng punto}) {
  return Marker(
    point: punto,
    width: 34,
    height: 34,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.background, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.5),
            blurRadius: 6,
          ),
        ],
      ),
      child: const Icon(Icons.travel_explore, color: Colors.black, size: 19),
    ),
  );
}
