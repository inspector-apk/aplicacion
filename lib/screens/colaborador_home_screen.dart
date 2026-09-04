import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/bogota_localidades.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/session_service.dart';
import '../services/solicitud_service.dart';
import '../services/ubicacion_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/bogota_map.dart';
import '../widgets/imagen_referencia_thumb.dart';
import '../widgets/map_bottom_panel.dart';
import '../widgets/map_top_bar.dart';
import '../widgets/solicitud_info_row.dart';
import 'home_screen.dart';
import 'responder_solicitud_screen.dart';
import 'splash_screen.dart';

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
  late Usuario _usuario = widget.usuario;
  List<Solicitud> _pendientes = [];
  List<Solicitud> _enCurso = [];
  bool _cargandoInicial = true;
  int? _procesandoId;
  Timer? _actualizacionPeriodica;
  Timer? _envioUbicacion;
  Timer? _cronometroBloqueo;

  // Puntos "de ambiente": no son colaboradores reales, solo para que el
  // mapa nunca se vea vacío, como los carros de Uber/Didi.
  late final List<LatLng> _anclasDecorativas;

  @override
  void initState() {
    super.initState();
    _anclasDecorativas = anclasDecorativasColaboradores();

    if (_usuario.estaBloqueado) {
      _iniciarCronometroBloqueo();
      return; // mientras está bloqueado no carga datos ni envía ubicación
    }

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
    _cronometroBloqueo?.cancel();
    UbicacionService.desconectar(widget.usuario.alias);
    super.dispose();
  }

  void _iniciarCronometroBloqueo() {
    _cronometroBloqueo?.cancel();
    _cronometroBloqueo = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_usuario.estaBloqueado) {
        _cronometroBloqueo?.cancel();
        // Ya se cumplió el bloqueo: recarga esta pantalla desde cero
        // como si acabara de entrar (arranca el mapa, timers, etc.).
        Navigator.of(context).pushReplacement(
          AppRoutes.fade(ColaboradorHomeScreen(usuario: _usuario)),
        );
        return;
      }
      setState(() {}); // solo para refrescar el conteo regresivo
    });
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
    if (enviada == true) {
      await _cargarDatos();
      _mostrarMensaje(
          '¡Ganaste ${formatearPesos(gananciaColaborador(solicitud.valorTotal))} '
          '(simulado)! Transferido a tu cuenta bancaria configurada.');
    }
  }

  Future<void> _cancelarAceptada(Solicitud solicitud) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar esta solicitud?'),
        content: const Text(
          'Ya la habías aceptado. Si la cancelas ahora, volverá a estar '
          'disponible para otros colaboradores y tu cuenta se bloqueará '
          'automáticamente durante 5 minutos: no podrás aceptar nuevas '
          'solicitudes durante ese tiempo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, cancelar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesandoId = solicitud.id);
    try {
      await SolicitudService.cancelarComoColaborador(
        solicitudId: solicitud.id!,
        colaboradorAlias: widget.usuario.alias,
      );
      final actualizado =
          await AuthService.bloquearPorCancelacion(widget.usuario.id!);
      SessionService.instance.iniciarSesion(actualizado);
      if (!mounted) return;
      setState(() => _usuario = actualizado);
      _iniciarCronometroBloqueo();
    } on SolicitudException catch (e) {
      _mostrarMensaje(e.mensaje);
      if (mounted) setState(() => _procesandoId = null);
    } catch (_) {
      _mostrarMensaje(
          'No se pudo conectar con el servidor. Revisa tu conexión.');
      if (mounted) setState(() => _procesandoId = null);
    }
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

  void _cerrarSesion() {
    SessionService.instance.cerrarSesion();
    Navigator.of(context).pushAndRemoveUntil(
      AppRoutes.fade(const SplashScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_usuario.estaBloqueado) {
      return _PantallaBloqueada(
        restante: _usuario.tiempoRestanteBloqueo,
        onCerrarSesion: _cerrarSesion,
      );
    }

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
                  onCancelar: _cancelarAceptada,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Se muestra en vez del mapa mientras la cuenta está bloqueada (el
/// colaborador canceló una solicitud que ya había aceptado).
class _PantallaBloqueada extends StatefulWidget {
  final Duration restante;
  final VoidCallback onCerrarSesion;
  const _PantallaBloqueada({required this.restante, required this.onCerrarSesion});

  @override
  State<_PantallaBloqueada> createState() => _PantallaBloqueadaState();
}

class _PantallaBloqueadaState extends State<_PantallaBloqueada> {
  @override
  Widget build(BuildContext context) {
    final minutos = widget.restante.inMinutes.toString().padLeft(2, '0');
    final segundos = (widget.restante.inSeconds % 60).toString().padLeft(2, '0');
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_outlined,
                    color: AppColors.error, size: 56),
                const SizedBox(height: 20),
                const Text(
                  'Cuenta bloqueada temporalmente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cancelaste una solicitud que ya habías aceptado. No '
                  'puedes aceptar nuevas solicitudes mientras dura el '
                  'bloqueo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
                ),
                const SizedBox(height: 24),
                Text(
                  '$minutos:$segundos',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 28),
                OutlineActionButton(
                  label: 'CERRAR SESIÓN',
                  onPressed: widget.onCerrarSesion,
                ),
              ],
            ),
          ),
        ),
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
  final ValueChanged<Solicitud> onCancelar;

  const _ListaSolicitudes({
    required this.pendientes,
    required this.enCurso,
    required this.procesandoId,
    required this.onAceptar,
    required this.onResponder,
    required this.onCancelar,
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
                vistaPrevia: false,
                accionLabel: 'RESPONDER',
                onAccion: () => onResponder(s),
                onCancelar: () => onCancelar(s),
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
          const SizedBox(height: 4),
          if (pendientes.isNotEmpty)
            const Text(
              'Solo se ve un adelanto: al aceptar verás la dirección '
              'exacta, la descripción completa y la imagen de referencia '
              '(si tiene).',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
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
                vistaPrevia: true,
                accionLabel: 'ACEPTAR',
                onAccion: () => onAceptar(s),
                onCancelar: null,
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

  /// true para las "Solicitudes disponibles" (todavía no aceptadas):
  /// solo muestra un adelanto, sin dirección exacta, descripción
  /// completa ni imagen de referencia — eso se revela al aceptar.
  final bool vistaPrevia;

  final String accionLabel;
  final VoidCallback onAccion;
  final VoidCallback? onCancelar;

  const _SolicitudCard({
    required this.solicitud,
    required this.cargando,
    required this.vistaPrevia,
    required this.accionLabel,
    required this.onAccion,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final ganancia = gananciaColaborador(solicitud.valorTotal);

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
              icono: Icons.category_outlined, texto: solicitud.categoria.etiqueta),
          SolicitudInfoRow(
              icono: Icons.checklist_outlined, texto: solicitud.tiposEtiqueta),
          SolicitudInfoRow(
              icono: Icons.bolt_outlined, texto: solicitud.urgencia.etiqueta),
          SolicitudInfoRow(
              icono: Icons.place_outlined, texto: solicitud.localidad),
          if (vistaPrevia)
            SolicitudInfoRow(
                icono: Icons.notes_outlined, texto: _adelanto(solicitud.descripcion))
          else ...[
            if (solicitud.direccion.isNotEmpty)
              SolicitudInfoRow(
                  icono: Icons.location_on_outlined, texto: solicitud.direccion),
            SolicitudInfoRow(
                icono: Icons.notes_outlined, texto: solicitud.descripcion),
            if (solicitud.metodoPago.isNotEmpty)
              SolicitudInfoRow(
                  icono: Icons.check_circle_outline,
                  texto: 'Pagado (simulado) · ${solicitud.metodoPago}'),
            if (solicitud.imagenReferenciaBase64 != null) ...[
              const SizedBox(height: 8),
              ImagenReferenciaThumb(
                  imagenBase64: solicitud.imagenReferenciaBase64!),
            ],
          ],
          SolicitudInfoRow(
              icono: Icons.payments_outlined,
              texto: 'Vas a ganar: ${formatearPesos(ganancia)}'),
          const SizedBox(height: 10),
          PrimaryButton(
            label: accionLabel,
            isLoading: cargando,
            onPressed: onAccion,
          ),
          if (onCancelar != null) ...[
            const SizedBox(height: 8),
            OutlineActionButton(
              label: 'CANCELAR SOLICITUD',
              onPressed: cargando ? null : onCancelar,
            ),
          ],
        ],
      ),
    );
  }

  String _adelanto(String descripcion) {
    const limite = 60;
    if (descripcion.length <= limite) return descripcion;
    return '${descripcion.substring(0, limite)}…';
  }
}
