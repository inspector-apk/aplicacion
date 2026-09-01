import 'dart:math' as math;

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

final _rngDecorativo = math.Random();

/// Puntos de ambiente: NO representan colaboradores reales, son solo
/// para que el mapa nunca se vea vacío (como Uber/Didi, que siempre
/// muestran varios carros alrededor aunque ninguno esté cerca todavía).
/// Se eligen una vez por pantalla (anclas fijas repartidas por Bogotá)
/// y luego se les aplica una pequeña variación aleatoria cada vez que
/// se piden, para dar sensación de movimiento.
List<LatLng> anclasDecorativasColaboradores({int cantidad = 6}) {
  final centros = kLocalidadesBogota.values.toList()
    ..shuffle(_rngDecorativo);
  return centros.take(cantidad).toList();
}

List<LatLng> conVariacionAleatoria(List<LatLng> anclas) {
  return anclas.map((p) {
    final dLat = (_rngDecorativo.nextDouble() - 0.5) * 0.006;
    final dLng = (_rngDecorativo.nextDouble() - 0.5) * 0.006;
    return LatLng(p.latitude + dLat, p.longitude + dLng);
  }).toList();
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
