import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/bogota_localidades.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/content_moderation_service.dart';
import '../services/solicitud_service.dart';
import '../services/ubicacion_service.dart';
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

  Categoria _categoria = Categoria.personal;
  final Set<TipoSolicitud> _tipos = {TipoSolicitud.texto};
  String? _localidad;
  final _descripcionCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  Timer? _actualizacionPeriodica;
  Timer? _actualizacionColaboradores;
  List<ColaboradorCercano> _colaboradoresCercanos = [];

  // Puntos "de ambiente": no son colaboradores reales, solo para que el
  // mapa nunca se vea vacío, como los carros de Uber/Didi.
  late final List<LatLng> _anclasDecorativas;

  @override
  void initState() {
    super.initState();
    _anclasDecorativas = anclasDecorativasColaboradores();
    _cargarSolicitudActiva();
    // Sin websockets, refrescamos cada pocos segundos para simular
    // tiempo real (ej. cuando un colaborador acepta la solicitud).
    _actualizacionPeriodica =
        Timer.periodic(const Duration(seconds: 6), (_) => _cargarSolicitudActiva());

    // Colaboradores disponibles cerca, como los carros de Uber/Didi.
    _cargarColaboradoresCercanos();
    _actualizacionColaboradores = Timer.periodic(
        const Duration(seconds: 15), (_) => _cargarColaboradoresCercanos());
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _direccionCtrl.dispose();
    _actualizacionPeriodica?.cancel();
    _actualizacionColaboradores?.cancel();
    super.dispose();
  }

  Future<void> _cargarColaboradoresCercanos() async {
    try {
      final colaboradores = await UbicacionService.colaboradoresCercanos();
      if (!mounted) return;
      setState(() => _colaboradoresCercanos = colaboradores);
    } catch (_) {
      // Sin conexión momentánea: se reintenta en el próximo ciclo.
    }
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

  void _alternarTipo(TipoSolicitud t) {
    setState(() {
      if (_tipos.contains(t)) {
        if (_tipos.length > 1) _tipos.remove(t); // siempre queda ≥1 elegido
      } else {
        _tipos.add(t);
      }
    });
  }

  Future<void> _enviarSolicitud() async {
    if (_tipos.isEmpty) {
      _mostrarMensaje('Elige al menos un tipo de contenido');
      return;
    }
    if (_localidad == null) {
      _mostrarMensaje('Selecciona la localidad');
      return;
    }
    if (_direccionCtrl.text.trim().isEmpty) {
      _mostrarMensaje('Escribe la dirección exacta');
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
      // Orden estable (texto, imagen, audio, video) sin importar el
      // orden en que se hayan marcado los chips.
      final tiposOrdenados = TipoSolicitud.values
          .where((t) => _tipos.contains(t))
          .toList();
      await SolicitudService.crearSolicitud(
        clienteAlias: widget.usuario.alias,
        tipos: tiposOrdenados,
        categoria: _categoria,
        descripcion: _descripcionCtrl.text,
        localidad: _localidad!,
        direccion: _direccionCtrl.text,
      );
      _descripcionCtrl.clear();
      _direccionCtrl.clear();
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
          tipos: solicitud.tipos,
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

    final marcadores = [
      if (_solicitudActiva != null)
        buildPinMarker(
          punto: kLocalidadesBogota[_solicitudActiva!.localidad] ??
              kBogotaCenter,
        ),
      // Solo se muestran mientras no hay una solicitud activa (como en
      // Uber: ves los carros disponibles antes de pedir el viaje).
      if (_solicitudActiva == null) ...[
        ..._colaboradoresCercanos
            .map((c) => buildColaboradorMarker(punto: c.punto)),
        // De ambiente: no son colaboradores reales, solo para que el
        // mapa nunca se vea vacío.
        ...conVariacionAleatoria(_anclasDecorativas)
            .map((p) => buildColaboradorMarker(punto: p)),
      ],
    ];

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
                      categoria: _categoria,
                      tipos: _tipos,
                      localidad: _localidad,
                      descripcionCtrl: _descripcionCtrl,
                      direccionCtrl: _direccionCtrl,
                      cargando: _enviando,
                      onCategoriaChanged: (c) =>
                          setState(() => _categoria = c),
                      onTipoToggle: _alternarTipo,
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
  final Categoria categoria;
  final Set<TipoSolicitud> tipos;
  final String? localidad;
  final TextEditingController descripcionCtrl;
  final TextEditingController direccionCtrl;
  final bool cargando;
  final ValueChanged<Categoria> onCategoriaChanged;
  final ValueChanged<TipoSolicitud> onTipoToggle;
  final ValueChanged<String?> onLocalidadChanged;
  final VoidCallback onEnviar;

  const _PanelFormulario({
    required this.categoria,
    required this.tipos,
    required this.localidad,
    required this.descripcionCtrl,
    required this.direccionCtrl,
    required this.cargando,
    required this.onCategoriaChanged,
    required this.onTipoToggle,
    required this.onLocalidadChanged,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final valorTotal = calcularValorTotal(categoria, tipos);

    return MapBottomPanel(
      child: SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Para qué es tu solicitud?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: Categoria.values.map((c) {
              final esUltimo = c == Categoria.values.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: esUltimo ? 0 : 8),
                  child: _CategoriaChip(
                    label: c.etiqueta,
                    seleccionado: categoria == c,
                    onTap: () => onCategoriaChanged(c),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
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
            'Puedes elegir varios (ej. imagen y audio a la vez).',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: TipoSolicitud.values.map((t) {
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 40 - 10) / 2,
                child: _TipoChip(
                  label: t.etiqueta,
                  icon: _iconoDeTipo(t),
                  precio: formatearPesos(precioDe(categoria, t)),
                  seleccionado: tipos.contains(t),
                  onTap: () => onTipoToggle(t),
                ),
              );
            }).toList(),
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
          const SizedBox(height: 14),
          TextField(
            controller: direccionCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Dirección exacta',
              helperText: 'Calle/carrera y número donde debe ir el colaborador',
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sell_outlined, color: AppColors.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Valor de referencia (ficticio): ${formatearPesos(valorTotal)}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
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

  IconData _iconoDeTipo(TipoSolicitud t) {
    switch (t) {
      case TipoSolicitud.texto:
        return Icons.description_outlined;
      case TipoSolicitud.imagen:
        return Icons.image_outlined;
      case TipoSolicitud.audio:
        return Icons.mic_outlined;
      case TipoSolicitud.video:
        return Icons.videocam_outlined;
    }
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
              icono: Icons.category_outlined, texto: solicitud.categoria.etiqueta),
          SolicitudInfoRow(
              icono: Icons.checklist_outlined, texto: solicitud.tiposEtiqueta),
          SolicitudInfoRow(
              icono: Icons.place_outlined, texto: solicitud.localidad),
          if (solicitud.direccion.isNotEmpty)
            SolicitudInfoRow(
                icono: Icons.location_on_outlined, texto: solicitud.direccion),
          SolicitudInfoRow(
              icono: Icons.notes_outlined, texto: solicitud.descripcion),
          SolicitudInfoRow(
              icono: Icons.sell_outlined,
              texto:
                  'Valor de referencia (ficticio): ${formatearPesos(solicitud.valorTotal)}'),
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

class _CategoriaChip extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final VoidCallback onTap;

  const _CategoriaChip({
    required this.label,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado ? AppColors.accent : AppColors.border,
            width: seleccionado ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: seleccionado ? AppColors.accent : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String precio;
  final bool seleccionado;
  final VoidCallback onTap;

  const _TipoChip({
    required this.label,
    required this.icon,
    required this.precio,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
            Icon(
              seleccionado ? Icons.check_circle : icon,
              color: seleccionado ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: seleccionado ? AppColors.accent : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              precio,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
