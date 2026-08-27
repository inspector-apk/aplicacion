import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/bogota_localidades.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/content_moderation_service.dart';
import '../services/solicitud_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/bogota_map.dart';
import '../widgets/map_bottom_panel.dart';
import '../widgets/map_top_bar.dart';
import '../widgets/solicitud_info_row.dart';
import 'home_screen.dart';
import 'ver_respuesta_screen.dart';

/// Pantalla principal del rol Cliente: mapa de Bogotá con un panel
/// inferior, al estilo inDrive/Uber. Si no hay una solicitud activa
/// muestra el formulario para crear una; si ya hay una, muestra su
/// estado (como la pantalla de "buscando conductor" de Uber).
class ClienteHomeScreen extends StatefulWidget {
  final Usuario usuario;
  const ClienteHomeScreen({super.key, required this.usuario});

  @override
  State<ClienteHomeScreen> createState() => _ClienteHomeScreenState();
}

class _ClienteHomeScreenState extends State<ClienteHomeScreen> {
  Solicitud? _solicitudActiva;
  bool _cargandoInicial = true;
  bool _enviando = false;

  TipoSolicitud _tipo = TipoSolicitud.texto;
  String? _localidad;
  final _descripcionCtrl = TextEditingController();
  Timer? _actualizacionPeriodica;

  @override
  void initState() {
    super.initState();
    _cargarSolicitudActiva();
    // Sin websockets, refrescamos cada pocos segundos para simular
    // tiempo real (ej. cuando un colaborador acepta la solicitud).
    _actualizacionPeriodica =
        Timer.periodic(const Duration(seconds: 6), (_) => _cargarSolicitudActiva());
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _actualizacionPeriodica?.cancel();
    super.dispose();
  }

  Future<void> _cargarSolicitudActiva() async {
    try {
      final activa = await SolicitudService.solicitudActivaDeCliente(
          widget.usuario.alias);
      if (!mounted) return;
      setState(() {
        _solicitudActiva = activa;
        _cargandoInicial = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoInicial = false);
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_localidad == null) {
      _mostrarMensaje('Selecciona la localidad');
      return;
    }
    if (_descripcionCtrl.text.trim().isEmpty) {
      _mostrarMensaje('Describe lo que necesitas');
      return;
    }
    if (ContentModerationService.contieneContenidoProhibido(
        _descripcionCtrl.text)) {
      _mostrarMensaje(
          'Tu solicitud contiene contenido no permitido y no se puede enviar.');
      return;
    }

    setState(() => _enviando = true);
    try {
      await SolicitudService.crearSolicitud(
        clienteAlias: widget.usuario.alias,
        tipo: _tipo,
        descripcion: _descripcionCtrl.text,
        localidad: _localidad!,
      );
      _descripcionCtrl.clear();
      await _cargarSolicitudActiva();
    } on SolicitudException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje(
          'No se pudo conectar con el servidor. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _cancelarSolicitud() async {
    final id = _solicitudActiva?.id;
    if (id == null) return;
    setState(() => _enviando = true);
    try {
      await SolicitudService.cancelarSolicitud(
        solicitudId: id,
        clienteAlias: widget.usuario.alias,
      );
      await _cargarSolicitudActiva();
    } on SolicitudException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje(
          'No se pudo conectar con el servidor. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _verRespuesta() async {
    final solicitud = _solicitudActiva;
    if (solicitud?.id == null) return;
    await Navigator.of(context).push(
      AppRoutes.slide(
        VerRespuestaScreen(
          solicitudId: solicitud!.id!,
          clienteAlias: widget.usuario.alias,
        ),
      ),
    );
    // Al volver, la respuesta ya se consumió en el backend: refrescamos
    // para que el panel vuelva al formulario de una nueva solicitud.
    await _cargarSolicitudActiva();
  }

  void _abrirPerfil() {
    Navigator.of(context)
        .push(AppRoutes.slide(HomeScreen(usuario: widget.usuario)));
  }

  @override
  Widget build(BuildContext context) {
    final centro = _solicitudActiva != null
        ? kLocalidadesBogota[_solicitudActiva!.localidad]
        : (_localidad != null ? kLocalidadesBogota[_localidad] : null);

    final marcadores = _solicitudActiva != null
        ? [
            buildPinMarker(
              punto: kLocalidadesBogota[_solicitudActiva!.localidad] ??
                  kBogotaCenter,
            ),
          ]
        : <Marker>[];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: BogotaMap(centro: centro, marcadores: marcadores),
          ),
          MapTopBar(alias: widget.usuario.alias, onPerfil: _abrirPerfil),
          if (!_cargandoInicial)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _solicitudActiva != null
                  ? _PanelSeguimiento(
                      solicitud: _solicitudActiva!,
                      cargando: _enviando,
                      onCancelar: _cancelarSolicitud,
                      onVerRespuesta: _verRespuesta,
                    )
                  : _PanelFormulario(
                      tipo: _tipo,
                      localidad: _localidad,
                      descripcionCtrl: _descripcionCtrl,
                      cargando: _enviando,
                      onTipoChanged: (t) => setState(() => _tipo = t),
                      onLocalidadChanged: (l) =>
                          setState(() => _localidad = l),
                      onEnviar: _enviarSolicitud,
                    ),
            ),
        ],
      ),
    );
  }
}

class _PanelFormulario extends StatelessWidget {
  final TipoSolicitud tipo;
  final String? localidad;
  final TextEditingController descripcionCtrl;
  final bool cargando;
  final ValueChanged<TipoSolicitud> onTipoChanged;
  final ValueChanged<String?> onLocalidadChanged;
  final VoidCallback onEnviar;

  const _PanelFormulario({
    required this.tipo,
    required this.localidad,
    required this.descripcionCtrl,
    required this.cargando,
    required this.onTipoChanged,
    required this.onLocalidadChanged,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    return MapBottomPanel(
      child: SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Qué necesitas solicitar?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Elige si el colaborador debe traerte texto (un informe '
            'escrito) o una imagen del lugar.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TipoChip(
                  label: 'Texto',
                  icon: Icons.description_outlined,
                  seleccionado: tipo == TipoSolicitud.texto,
                  onTap: () => onTipoChanged(TipoSolicitud.texto),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TipoChip(
                  label: 'Imagen',
                  icon: Icons.image_outlined,
                  seleccionado: tipo == TipoSolicitud.imagen,
                  onTap: () => onTipoChanged(TipoSolicitud.imagen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: descripcionCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Describe lo que quieres solicitar',
              helperText: 'Sé específico: qué información o imagen '
                  'necesitas y de qué lugar exactamente',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: localidad,
            dropdownColor: AppColors.surfaceVariant,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Localidad donde se obtendrá la información',
              helperText: 'El colaborador que acepte tu solicitud irá a '
                  'esta localidad de Bogotá',
            ),
            items: kLocalidadesBogota.keys
                .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                .toList(),
            onChanged: onLocalidadChanged,
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'ENVIAR SOLICITUD',
            isLoading: cargando,
            onPressed: onEnviar,
          ),
        ],
        ),
      ),
    );
  }
}

class _PanelSeguimiento extends StatelessWidget {
  final Solicitud solicitud;
  final bool cargando;
  final VoidCallback onCancelar;
  final VoidCallback onVerRespuesta;

  const _PanelSeguimiento({
    required this.solicitud,
    required this.cargando,
    required this.onCancelar,
    required this.onVerRespuesta,
  });

  @override
  Widget build(BuildContext context) {
    final esPendiente = solicitud.estado == EstadoSolicitud.pendiente;
    final tieneRespuesta = solicitud.tieneRespuestaSinVer;

    return MapBottomPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tieneRespuesta
                      ? Icons.mark_email_unread_outlined
                      : esPendiente
                          ? Icons.hourglass_top_rounded
                          : Icons.directions_walk_rounded,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tieneRespuesta
                          ? '¡Tu colaborador respondió!'
                          : solicitud.estado.etiqueta,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      tieneRespuesta
                          ? 'Solo la podrás ver una vez'
                          : esPendiente
                              ? 'Estamos buscando un colaborador disponible'
                              : 'Un colaborador va a atender tu solicitud',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28, color: AppColors.border),
          SolicitudInfoRow(
              icono: Icons.category_outlined,
              texto: solicitud.tipo.etiqueta),
          SolicitudInfoRow(
              icono: Icons.place_outlined, texto: solicitud.localidad),
          SolicitudInfoRow(
              icono: Icons.notes_outlined, texto: solicitud.descripcion),
          const SizedBox(height: 16),
          if (tieneRespuesta)
            PrimaryButton(
              label: 'VER RESPUESTA (una sola vez)',
              onPressed: onVerRespuesta,
            )
          else if (esPendiente)
            OutlineActionButton(
              label: cargando ? 'CANCELANDO...' : 'CANCELAR SOLICITUD',
              onPressed: cargando ? null : onCancelar,
            ),
        ],
      ),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool seleccionado;
  final VoidCallback onTap;

  const _TipoChip({
    required this.label,
    required this.icon,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: seleccionado
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionado ? AppColors.accent : AppColors.border,
            width: seleccionado ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: seleccionado
                    ? AppColors.accent
                    : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: seleccionado
                    ? AppColors.accent
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
