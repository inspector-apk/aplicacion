import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/admin_service.dart';
import '../services/session_service.dart';
import 'splash_screen.dart';

/// Panel de administrador: usuarios y solicitudes, con opción de
/// eliminarlos. Todo se lee y se borra directamente de la base de datos
/// local.
class AdminPanelScreen extends StatefulWidget {
  final Usuario usuario;
  const AdminPanelScreen({super.key, required this.usuario});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<Usuario> _usuarios = [];
  List<Solicitud> _solicitudes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final usuarios = await AdminService.todosLosUsuarios();
    List<Solicitud> solicitudes = [];
    try {
      solicitudes = await AdminService.todasLasSolicitudes();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No se pudieron cargar las solicitudes (sin conexión al backend)'),
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      _usuarios = usuarios;
      _solicitudes = solicitudes;
      _cargando = false;
    });
  }

  void _cerrarSesion() {
    SessionService.instance.cerrarSesion();
    Navigator.of(context).pushAndRemoveUntil(
      AppRoutes.fade(const SplashScreen()),
      (route) => false,
    );
  }

  Future<bool> _confirmar(String titulo, String mensaje) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Eliminar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return confirmar ?? false;
  }

  Future<void> _eliminarUsuario(Usuario u) async {
    if (u.id == widget.usuario.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No puedes eliminar tu propia cuenta de admin')),
      );
      return;
    }
    final ok = await _confirmar(
      'Eliminar usuario',
      '¿Seguro que quieres eliminar a "${u.alias}"? Esto borra su cuenta '
          'por completo y no se puede deshacer.',
    );
    if (!ok) return;
    await AdminService.eliminarUsuario(u.id!);
    await _cargarDatos();
  }

  Future<void> _eliminarSolicitud(Solicitud s) async {
    final ok = await _confirmar(
      'Eliminar solicitud',
      '¿Seguro que quieres eliminar esta solicitud? No se puede deshacer.',
    );
    if (!ok) return;
    await AdminService.eliminarSolicitud(s.id!);
    await _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel de administrador'),
          actions: [
            IconButton(
              onPressed: _cargarDatos,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
            IconButton(
              onPressed: _cerrarSesion,
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: 'Usuarios (${_usuarios.length})'),
              Tab(text: 'Solicitudes (${_solicitudes.length})'),
            ],
          ),
        ),
        body: _cargando
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
            : TabBarView(
                children: [
                  _ListaUsuarios(
                    usuarios: _usuarios,
                    onEliminar: _eliminarUsuario,
                  ),
                  _ListaSolicitudes(
                    solicitudes: _solicitudes,
                    onEliminar: _eliminarSolicitud,
                  ),
                ],
              ),
      ),
    );
  }
}

class _ListaUsuarios extends StatelessWidget {
  final List<Usuario> usuarios;
  final ValueChanged<Usuario> onEliminar;
  const _ListaUsuarios({required this.usuarios, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    if (usuarios.isEmpty) {
      return const Center(
        child: Text('Sin usuarios registrados',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: usuarios.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final u = usuarios[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      u.alias,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _Badge(texto: _rolLabel(u.rol)),
                  IconButton(
                    onPressed: () => onEliminar(u),
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error, size: 20),
                    tooltip: 'Eliminar usuario',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('${u.nombre} · ${u.edad} años',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
              Text(u.correo,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5)),
              if (u.ocupacion != null || u.localidadTrabajo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (u.ocupacion != null) u.ocupacion,
                      if (u.localidadTrabajo != null) u.localidadTrabajo,
                    ].join(' · '),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _rolLabel(RolUsuario? rol) {
    switch (rol) {
      case RolUsuario.colaborador:
        return 'Colaborador';
      case RolUsuario.cliente:
        return 'Cliente';
      case RolUsuario.administrador:
        return 'Admin';
      case null:
        return 'Sin rol';
    }
  }
}

class _ListaSolicitudes extends StatelessWidget {
  final List<Solicitud> solicitudes;
  final ValueChanged<Solicitud> onEliminar;
  const _ListaSolicitudes({
    required this.solicitudes,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    if (solicitudes.isEmpty) {
      return const Center(
        child: Text('Sin solicitudes creadas',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    final completadas =
        solicitudes.where((s) => s.estado == EstadoSolicitud.completada);
    final comisionTotal = completadas.fold<int>(
        0, (suma, s) => suma + comisionPlataforma(s.valorTotal));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: solicitudes.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentDim],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Comisiones de la plataforma (simuladas, 10%)',
                    style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5)),
                const SizedBox(height: 6),
                Text(
                  formatearPesos(comisionTotal),
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 24),
                ),
                const SizedBox(height: 2),
                Text('De ${completadas.length} solicitudes completadas',
                    style: const TextStyle(color: Colors.black87, fontSize: 11.5)),
              ],
            ),
          );
        }
        final s = solicitudes[i - 1];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.tiposEtiqueta} · ${s.localidad}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  _Badge(texto: s.estado.etiqueta),
                  IconButton(
                    onPressed: () => onEliminar(s),
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error, size: 20),
                    tooltip: 'Eliminar solicitud',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(s.descripcion,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5)),
              if (s.direccion.isNotEmpty)
                Text(s.direccion,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11.5)),
              const SizedBox(height: 6),
              Text(
                'Cliente: ${s.clienteAlias}'
                '${s.colaboradorAlias != null ? ' · Colaborador: ${s.colaboradorAlias}' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              Text(
                'Solicitado: ${s.fechaCreacion}'
                '${s.respuestaFecha != null ? ' · Respondido: ${s.respuestaFecha}' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              Text(
                '${s.categoria.etiqueta} · Valor de referencia (ficticio): '
                '${formatearPesos(s.valorTotal)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              if (s.metodoPago.isNotEmpty)
                Text(
                  'Pago (simulado): ${s.metodoPago} · Ref: ${s.referenciaPago}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              if (s.imagenReferenciaBase64 != null)
                const Text(
                  'Incluye imagen de referencia del cliente',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String texto;
  const _Badge({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
