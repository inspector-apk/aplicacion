import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/bogota_localidades.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/location_service.dart';
import '../services/solicitud_service.dart';
import '../services/ubicacion_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/bogota_map.dart';
import '../widgets/map_bottom_panel.dart';
import '../widgets/map_top_bar.dart';
import '../widgets/solicitud_info_row.dart';
import 'home_screen.dart';
import 'responder_solicitud_screen.dart';

/// Pantalla principal del rol Colaborador: mapa de Bogotá con las
/// solicitudes disponibles (como el conductor viendo viajes en Uber),
/// más las que ya aceptó y tiene en curso.
class ColaboradorHomeScreen extends StatefulWidget {
  final Usuario usuario;
  const ColaboradorHomeScreen({super.key, required this.usuario});

  @override
  State<ColaboradorHomeScreen> createState() => _ColaboradorHomeScreenState();
}

class _ColaboradorHomeScreenState extends State<ColaboradorHomeScreen> {
  List<Solicitud> _pendientes = [];
  List<Solicitud> _enCurso = [];
  bool _cargandoInicial = true;
  int? _procesandoId;
  Timer? _actualizacionPeriodica;
  Timer? _envioUbicacion;

  // Puntos "de ambiente": no son colaboradores reales, solo para que el
  // mapa nunca se vea vacío, como los carros de Uber/Didi.
  late final List<LatLng> _anclasDecorativas;

  @override
  void initState() {
    super.initState();
    _anclasDecorativas = anclasDecorativasColaboradores();
    _cargarDatos();
    // Sin websockets, refrescamos cada pocos segundos: es lo que hace
    // que una solicitud "desaparezca" para los demás colaboradores en
    // cuanto alguien más la acepta primero.
    _actualizacionPeriodica =
        Timer.periodic(const Duration(seconds: 6), (_) => _cargarDatos());

    // Mientras esta pantalla está abierta el colaborador cuenta como
    // "disponible": se envía su posición aproximada cada 15s para que
    // los clientes lo vean en el mapa, como los carros de Uber/Didi.
    _enviarUbicacionPropia();
    _envioUbicacion =
        Timer.periodic(const Duration(seconds: 15), (_) => _enviarUbicacionPropia());
  }

  @override
  void dispose() {
    _actualizacionPeriodica?.cancel();
    _envioUbicacion?.cancel();
    UbicacionService.desconectar(widget.usuario.alias);
    super.dispose();
  }

  Future<void> _enviarUbicacionPropia() async {
    try {
      if (!await LocationService.tienePermisoConcedido()) return;
      final posicion = await Geolocator.getCurrentPosition();
      await UbicacionService.enviarUbicacion(
        colaboradorAlias: widget.usuario.alias,
        latitud: posicion.latitude,
        longitud: posicion.longitude,
      );
    } catch (_) {
      // Sin ubicación disponible en este ciclo: no es crítico, no
      // afecta el resto de la pantalla.
    }
  }

  Future<void> _cargarDatos() async {
    try {
      final pendientes = await SolicitudService.solicitudesPendientes();
      final enCurso = await SolicitudService.solicitudesEnCursoDeColaborador(
        widget.usuario.alias,
      );
      if (!mounted) return;
      setState(() {
        _pendientes = pendientes;
        _enCurso = enCurso;
        _cargandoInicial = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoInicial = false);
    }
  }

  Future<void> _aceptar(Solicitud solicitud) async {
    setState(() => _procesandoId = solicitud.id);
    try {
      await SolicitudService.aceptarSolicitud(
        solicitudId: solicitud.id!,
        colaboradorAlias: widget.usuario.alias,
      );
      await _cargarDatos();
    } on SolicitudException catch (e) {
      _mostrarMensaje(e.mensaje);
      await _cargarDatos();
    } catch (_) {
      _mostrarMensaje(
          'No se pudo conectar con el servidor. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _responder(Solicitud solicitud) async {
    final enviada = await Navigator.of(context).push<bool>(
      AppRoutes.slide(
        ResponderSolicitudScreen(solicitud: solicitud, usuario: widget.usuario),
      ),
    );
    if (enviada == true) await _cargarDatos();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _abrirPerfil() {
    Navigator.of(context)
        .push(AppRoutes.slide(HomeScreen(usuario: widget.usuario)));
  }

  @override
  Widget build(BuildContext context) {
    final marcadores = [
      ..._pendientes.map((s) => buildPinMarker(
            punto: kLocalidadesBogota[s.localidad] ?? kBogotaCenter,
          )),
      ..._enCurso.map((s) => buildPinMarker(
            punto: kLocalidadesBogota[s.localidad] ?? kBogotaCenter,
            color: AppColors.success,
            icon: Icons.directions_walk_rounded,
          )),
      // De ambiente: no son colaboradores reales, solo para que el mapa
      // nunca se vea vacío, como los carros de Uber/Didi.
      ...conVariacionAleatoria(_anclasDecorativas)
          .map((p) => buildColaboradorMarker(punto: p)),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: BogotaMap(marcadores: marcadores)),
          MapTopBar(alias: widget.usuario.alias, onPerfil: _abrirPerfil),
          if (!_cargandoInicial)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MapBottomPanel(
                maxHeightFraction: 0.55,
                child: _ListaSolicitudes(
                  pendientes: _pendientes,
                  enCurso: _enCurso,
                  procesandoId: _procesandoId,
                  onAceptar: _aceptar,
                  onResponder: _responder,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListaSolicitudes extends StatelessWidget {
  final List<Solicitud> pendientes;
  final List<Solicitud> enCurso;
  final int? procesandoId;
  final ValueChanged<Solicitud> onAceptar;
  final ValueChanged<Solicitud> onResponder;

  const _ListaSolicitudes({
    required this.pendientes,
    required this.enCurso,
    required this.procesandoId,
    required this.onAceptar,
    required this.onResponder,
  });

  @override
  Widget build(BuildContext context) {
    if (pendientes.isEmpty && enCurso.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.map_outlined, color: AppColors.textMuted, size: 32),
            SizedBox(height: 10),
            Text(
              'No hay solicitudes por ahora',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enCurso.isNotEmpty) ...[
            const Text(
              'En curso',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...enCurso.map(
              (s) => _SolicitudCard(
                solicitud: s,
                cargando: procesandoId == s.id,
                accionLabel: 'RESPONDER',
                onAccion: () => onResponder(s),
              ),
            ),
            const SizedBox(height: 18),
          ],
          const Text(
            'Solicitudes disponibles',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (pendientes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No hay solicitudes pendientes en este momento',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...pendientes.map(
              (s) => _SolicitudCard(
                solicitud: s,
                cargando: procesandoId == s.id,
                accionLabel: 'ACEPTAR',
                onAccion: () => onAceptar(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _SolicitudCard extends StatelessWidget {
  final Solicitud solicitud;
  final bool cargando;
  final String accionLabel;
  final VoidCallback onAccion;

  const _SolicitudCard({
    required this.solicitud,
    required this.cargando,
    required this.accionLabel,
    required this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SolicitudInfoRow(
            icono: solicitud.tipo == TipoSolicitud.texto
                ? Icons.description_outlined
                : Icons.image_outlined,
            texto: solicitud.tipo.etiqueta,
          ),
          SolicitudInfoRow(
              icono: Icons.place_outlined, texto: solicitud.localidad),
          SolicitudInfoRow(
              icono: Icons.notes_outlined, texto: solicitud.descripcion),
          const SizedBox(height: 10),
          PrimaryButton(
            label: accionLabel,
            isLoading: cargando,
            onPressed: onAccion,
          ),
        ],
      ),
    );
  }
}
