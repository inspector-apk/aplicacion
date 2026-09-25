import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/bogota_localidades.dart';
import '../core/precios.dart';
import '../core/sugerencias_descripcion.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/solicitud_service.dart';
import '../services/ubicacion_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/bogota_map.dart';
import '../widgets/map_bottom_panel.dart';
import '../widgets/map_top_bar.dart';
import '../widgets/imagen_referencia_thumb.dart';
import '../widgets/solicitud_info_row.dart';
import 'home_screen.dart';
import 'pago_ficticio_screen.dart';
import 'seleccionar_punto_screen.dart';
import 'ver_respuesta_screen.dart';

/// Pantalla principal del rol Cliente: mapa de Bogotá con un panel
/// inferior. Si no hay una solicitud activa muestra el formulario para
/// crear una; si ya hay una, muestra su estado y seguimiento.
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
  Urgencia _urgencia = Urgencia.dosDias;
  final Set<TipoSolicitud> _tipos = {TipoSolicitud.texto};
  String? _localidad;
  String? _opcion;
  File? _imagenReferencia;
  LatLng? _puntoExacto;
  String? _nombrePunto;
  Timer? _actualizacionPeriodica;
  Timer? _actualizacionColaboradores;
  List<ColaboradorCercano> _colaboradoresCercanos = [];

  // Puntos "de ambiente": no son colaboradores reales, solo para que el
  // mapa nunca se vea vacío.
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

    // Colaboradores disponibles cerca.
    _cargarColaboradoresCercanos();
    _actualizacionColaboradores = Timer.periodic(
        const Duration(seconds: 15), (_) => _cargarColaboradoresCercanos());
  }

  @override
  void dispose() {
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

  Future<void> _elegirImagenReferencia(ImageSource origen) async {
    final archivo = await ImagePicker().pickImage(
      source: origen,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (archivo == null) return;
    setState(() => _imagenReferencia = File(archivo.path));
  }

  void _quitarImagenReferencia() {
    setState(() => _imagenReferencia = null);
  }

  Future<void> _marcarPuntoEnElMapa() async {
    if (_localidad == null) {
      _mostrarMensaje('Selecciona primero la localidad');
      return;
    }
    final centroLocalidad = kLocalidadesBogota[_localidad] ?? kBogotaCenter;
    final elegido = await Navigator.of(context).push<PuntoSeleccionado>(
      AppRoutes.slide(
        SeleccionarPuntoScreen(
          centroInicial: centroLocalidad,
          puntoInicial: _puntoExacto,
          nombreInicial: _nombrePunto,
        ),
      ),
    );
    if (elegido == null) return;
    setState(() {
      _puntoExacto = elegido.punto;
      _nombrePunto = elegido.nombre;
    });
  }


  void _alternarTipo(TipoSolicitud t) {
    setState(() {
      if (_tipos.contains(t)) {
        if (_tipos.length > 1) _tipos.remove(t); // siempre queda ≥1 elegido
      } else {
        _tipos.add(t);
      }
      _revalidarOpcion();
    });
  }

  /// Si la opción elegida ya no aplica a la categoría o a los tipos de
  /// contenido actuales, se descarta para que el cliente vuelva a elegir.
  void _revalidarOpcion() {
    if (_opcion == null) return;
    final sigueVigente =
        opcionesPara(_categoria, _tipos).any((o) => o.texto == _opcion);
    if (!sigueVigente) _opcion = null;
  }

  Future<void> _enviarSolicitud() async {
    if (_tipos.isEmpty) {
      _mostrarMensaje('Elige al menos un tipo de contenido');
      return;
    }
    if (_opcion == null) {
      _mostrarMensaje('Elige qué debe hacer el colaborador (paso 3)');
      return;
    }
    if (_localidad == null) {
      _mostrarMensaje('Selecciona la localidad (paso 4)');
      return;
    }
    if (_puntoExacto == null) {
      _mostrarMensaje('Busca la dirección o marca el punto en el mapa (paso 4)');
      return;
    }

    // Antes de enviar, pasa por la pasarela de pago (simulada, sin
    // cobro real) — como haría una app de verdad.
    final resultadoPago = await Navigator.of(context).push<ResultadoPagoFicticio>(
      AppRoutes.slide(
        PagoFicticioScreen(
            categoria: _categoria, tipos: _tipos, urgencia: _urgencia),
      ),
    );
    if (resultadoPago == null) return; // canceló el pago

    setState(() => _enviando = true);
    try {
      // Orden estable (texto, imagen, audio, video) sin importar el
      // orden en que se hayan marcado los chips.
      final tiposOrdenados = TipoSolicitud.values
          .where((t) => _tipos.contains(t))
          .toList();
      String? imagenReferenciaBase64;
      if (_imagenReferencia != null) {
        imagenReferenciaBase64 =
            base64Encode(await _imagenReferencia!.readAsBytes());
      }
      await SolicitudService.crearSolicitud(
        clienteAlias: widget.usuario.alias,
        tipos: tiposOrdenados,
        categoria: _categoria,
        urgencia: _urgencia,
        descripcion: _opcion!,
        localidad: _localidad!,
        direccion: _nombrePunto ?? 'Punto marcado en el mapa',
        referenciaPago: resultadoPago.referencia,
        metodoPago: resultadoPago.metodo,
        imagenReferenciaBase64: imagenReferenciaBase64,
        puntoExacto: _puntoExacto,
      );
      setState(() {
        _opcion = null;
        _imagenReferencia = null;
        _puntoExacto = null;
        _nombrePunto = null;
      });
      await _cargarSolicitudActiva();
      if (mounted) {
        _mostrarMensaje('Pago simulado exitoso · Ref: ${resultadoPago.referencia}');
      }
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
        ? LatLng(_solicitudActiva!.latitud, _solicitudActiva!.longitud)
        : (_localidad != null ? kLocalidadesBogota[_localidad] : null);

    final marcadores = [
      if (_solicitudActiva != null)
        buildPinMarker(
          punto: LatLng(_solicitudActiva!.latitud, _solicitudActiva!.longitud),
        ),
      // Solo se muestran mientras no hay una solicitud activa: ves los
      // colaboradores disponibles antes de pedir la tuya.
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
                      urgencia: _urgencia,
                      tipos: _tipos,
                      localidad: _localidad,
                      opcion: _opcion,
                      imagenReferencia: _imagenReferencia,
                      puntoExacto: _puntoExacto,
                      nombrePunto: _nombrePunto,
                      cargando: _enviando,
                      onCategoriaChanged: (c) =>
                          setState(() {
                            _categoria = c;
                            _revalidarOpcion();
                          }),
                      onUrgenciaChanged: (u) => setState(() => _urgencia = u),
                      onTipoToggle: _alternarTipo,
                      onOpcionChanged: (o) => setState(() => _opcion = o),
                      onLocalidadChanged: (l) =>
                          setState(() => _localidad = l),
                      onElegirImagen: _elegirImagenReferencia,
                      onQuitarImagen: _quitarImagenReferencia,
                      onMarcarPunto: _marcarPuntoEnElMapa,
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
  final Urgencia urgencia;
  final Set<TipoSolicitud> tipos;
  final String? opcion;
  final String? localidad;
  final File? imagenReferencia;
  final LatLng? puntoExacto;
  final String? nombrePunto;
  final bool cargando;
  final ValueChanged<Categoria> onCategoriaChanged;
  final ValueChanged<Urgencia> onUrgenciaChanged;
  final ValueChanged<TipoSolicitud> onTipoToggle;
  final ValueChanged<String> onOpcionChanged;
  final ValueChanged<String?> onLocalidadChanged;
  final ValueChanged<ImageSource> onElegirImagen;
  final VoidCallback onQuitarImagen;
  final VoidCallback onMarcarPunto;
  final VoidCallback onEnviar;

  const _PanelFormulario({
    required this.categoria,
    required this.urgencia,
    required this.tipos,
    required this.opcion,
    required this.localidad,
    required this.imagenReferencia,
    required this.puntoExacto,
    required this.nombrePunto,
    required this.cargando,
    required this.onCategoriaChanged,
    required this.onUrgenciaChanged,
    required this.onTipoToggle,
    required this.onOpcionChanged,
    required this.onLocalidadChanged,
    required this.onElegirImagen,
    required this.onQuitarImagen,
    required this.onMarcarPunto,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final valorTotal = calcularValorTotal(categoria, tipos, urgencia);
    final opciones = opcionesPara(categoria, tipos);

    return MapBottomPanel(
      maxHeightFraction: 0.7,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nueva solicitud',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pide que un colaborador vaya a un lugar de Bogotá y te '
              'traiga la información. Solo eliges opciones: no hay que '
              'escribir nada.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            const _ComoFunciona(),
            const SizedBox(height: 22),

            // ---- Paso 1: tipo de servicio ----
            const _PasoTitulo(
              numero: 1,
              titulo: '¿Para qué es?',
              ayuda: 'Personal: tus asuntos · Comercial: locales y negocios · '
                  'Industrial: bodegas y plantas.',
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 24),

            // ---- Paso 2: qué le traen ----
            const _PasoTitulo(
              numero: 2,
              titulo: '¿Qué quieres que te traigan?',
              ayuda: 'Marca uno o varios. El colaborador deberá responder '
                  'con todo lo que elijas.',
            ),
            const SizedBox(height: 12),
            Row(
              children: TipoSolicitud.values.map((t) {
                final esUltimo = t == TipoSolicitud.values.last;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: esUltimo ? 0 : 8),
                    child: _TipoChip(
                      label: t.etiqueta,
                      icon: _iconoDeTipo(t),
                      precio: formatearPesos(precioDe(categoria, t)),
                      seleccionado: tipos.contains(t),
                      onTap: () => onTipoToggle(t),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ---- Paso 3: qué debe hacer ----
            const _PasoTitulo(
              numero: 3,
              titulo: '¿Qué debe hacer el colaborador?',
              ayuda: 'Elige una opción. Solo aparecen las que coinciden con '
                  'lo que ya elegiste arriba.',
            ),
            const SizedBox(height: 12),
            ...opciones.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OpcionTile(
                  texto: o.texto,
                  seleccionada: opcion == o.texto,
                  onTap: () => onOpcionChanged(o.texto),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---- Paso 4: dónde ----
            const _PasoTitulo(
              numero: 4,
              titulo: '¿Dónde?',
              ayuda: 'Elige la localidad y luego busca la dirección, el '
                  'conjunto o el edificio, o marca el punto en el mapa.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: localidad,
              dropdownColor: AppColors.surfaceVariant,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Localidad de Bogotá',
              ),
              items: kLocalidadesBogota.keys
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: onLocalidadChanged,
            ),
            const SizedBox(height: 10),
            if (puntoExacto != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nombrePunto != null
                            ? 'Ubicado: $nombrePunto'
                            : 'Punto exacto marcado en el mapa',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.success, fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: onMarcarPunto,
                      child: const Text('Cambiar',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  ],
                ),
              )
            else
              OutlineActionButton(
                label: 'BUSCAR DIRECCIÓN O MARCAR EN EL MAPA',
                onPressed: onMarcarPunto,
              ),
            const SizedBox(height: 14),
            const Text(
              'Foto de referencia (opcional)',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Ayuda al colaborador a reconocer el lugar o lo que buscas.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (imagenReferencia != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      imagenReferencia!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: onQuitarImagen,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlineActionButton(
                      label: 'CÁMARA',
                      onPressed: () => onElegirImagen(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlineActionButton(
                      label: 'GALERÍA',
                      onPressed: () => onElegirImagen(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),

            // ---- Paso 5: urgencia ----
            const _PasoTitulo(
              numero: 5,
              titulo: '¿Para cuándo la necesitas?',
              ayuda: 'Entre más rápido, más alto el valor.',
            ),
            const SizedBox(height: 12),
            Row(
              children: Urgencia.values.map((u) {
                final esUltimo = u == Urgencia.values.last;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: esUltimo ? 0 : 8),
                    child: _UrgenciaChip(
                      label: u.etiqueta,
                      multiplicador: multiplicadorDe(u),
                      seleccionada: urgencia == u,
                      onTap: () => onUrgenciaChanged(u),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ---- Resumen y envío ----
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sell_outlined,
                      color: AppColors.accentText, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Valor de referencia (ficticio): '
                      '${formatearPesos(valorTotal)}',
                      style: const TextStyle(
                        color: AppColors.accentText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'PAGAR Y ENVIAR SOLICITUD',
              isLoading: cargando,
              onPressed: onEnviar,
            ),
            const SizedBox(height: 10),
            const Text(
              'El pago es simulado: no se cobra dinero real. Al enviarla, un '
              'colaborador la acepta y te responde; verás su respuesta una '
              'sola vez.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
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

/// Opción de la lista de "qué debe hacer el colaborador" (selección única).
class _OpcionTile extends StatelessWidget {
  final String texto;
  final bool seleccionada;
  final VoidCallback onTap;

  const _OpcionTile({
    required this.texto,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: seleccionada
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionada ? AppColors.accent : AppColors.border,
            width: seleccionada ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              seleccionada ? Icons.radio_button_checked : Icons.radio_button_off,
              color: seleccionada ? AppColors.accentText : AppColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  color: seleccionada
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: seleccionada ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
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
                          : Icons.fact_check_outlined,
                  color: AppColors.onAccent,
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
              icono: Icons.bolt_outlined, texto: solicitud.urgencia.etiqueta),
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
          if (solicitud.metodoPago.isNotEmpty)
            SolicitudInfoRow(
                icono: Icons.check_circle_outline,
                texto:
                    'Pagado (simulado) · ${solicitud.metodoPago} · Ref: ${solicitud.referenciaPago}'),
          if (solicitud.imagenReferenciaBase64 != null) ...[
            const SizedBox(height: 12),
            ImagenReferenciaThumb(
                imagenBase64: solicitud.imagenReferenciaBase64!),
          ],
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
            color: seleccionado ? AppColors.accentText : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _UrgenciaChip extends StatelessWidget {
  final String label;
  final double multiplicador;
  final bool seleccionada;
  final VoidCallback onTap;

  const _UrgenciaChip({
    required this.label,
    required this.multiplicador,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final etiquetaRecargo =
        multiplicador == 1.0 ? 'Estándar' : '+${(((multiplicador - 1) * 100).round())}%';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: seleccionada
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionada ? AppColors.accent : AppColors.border,
            width: seleccionada ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              seleccionada ? Icons.check_circle : Icons.bolt_outlined,
              color: seleccionada ? AppColors.accentText : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: seleccionada ? AppColors.accentText : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              etiquetaRecargo,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 10),
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
              color: seleccionado ? AppColors.accentText : AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: seleccionado ? AppColors.accentText : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              precio,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título de cada paso del formulario: número + título + una línea que
/// explica qué se debe llenar.
class _PasoTitulo extends StatelessWidget {
  final int numero;
  final String titulo;
  final String ayuda;

  const _PasoTitulo({
    required this.numero,
    required this.titulo,
    required this.ayuda,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$numero',
            style: const TextStyle(
              color: AppColors.onAccent,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ayuda,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Resumen de 3 pasos de cómo funciona el servicio, en una sola franja.
class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona();

  @override
  Widget build(BuildContext context) {
    Widget paso(IconData icono, String texto) {
      return Expanded(
        child: Column(
          children: [
            Icon(icono, color: AppColors.accentText, size: 22),
            const SizedBox(height: 4),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      );
    }

    const flecha = Padding(
      padding: EdgeInsets.only(bottom: 18),
      child: Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          paso(Icons.edit_note, 'Llenas tu\nsolicitud'),
          flecha,
          paso(Icons.credit_card, 'Pagas\n(simulado)'),
          flecha,
          paso(Icons.directions_walk, 'Un colaborador\nva y te responde'),
        ],
      ),
    );
  }
}
