import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/admin_service.dart';
import '../services/session_service.dart';
import 'splash_screen.dart';

/// Panel de administrador: usuarios y solicitudes, con búsqueda, filtros
/// y herramientas de soporte (cambiar rol, desactivar 2FA, quitar
/// bloqueos) además de eliminar. Los usuarios se leen/editan de la base
/// de datos local; las solicitudes, del backend compartido.
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

  final _busquedaUsuariosCtrl = TextEditingController();
  final _busquedaSolicitudesCtrl = TextEditingController();
  EstadoSolicitud? _filtroEstado;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _busquedaUsuariosCtrl.addListener(() => setState(() {}));
    _busquedaSolicitudesCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _busquedaUsuariosCtrl.dispose();
    _busquedaSolicitudesCtrl.dispose();
    super.dispose();
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

  Future<bool> _confirmar(String titulo, String mensaje,
      {String textoBoton = 'Eliminar', Color? colorBoton}) async {
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
            child: Text(textoBoton,
                style: TextStyle(color: colorBoton ?? AppColors.error)),
          ),
        ],
      ),
    );
    return confirmar ?? false;
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _eliminarUsuario(Usuario u) async {
    if (u.id == widget.usuario.id) {
      _mostrarMensaje('No puedes eliminar tu propia cuenta de admin');
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

  Future<void> _cambiarRol(Usuario u) async {
    if (u.id == widget.usuario.id) {
      _mostrarMensaje('No puedes cambiar el rol de tu propia cuenta de admin');
      return;
    }
    final nuevoRol = await showDialog<RolUsuario>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Cambiar rol de "${u.alias}"'),
        children: [
          for (final r in [
            RolUsuario.cliente,
            RolUsuario.colaborador,
            RolUsuario.administrador,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(_rolLabelEstatico(r)),
            ),
        ],
      ),
    );
    if (nuevoRol == null || nuevoRol == u.rol) return;
    await AdminService.cambiarRol(u.id!, nuevoRol);
    _mostrarMensaje('Rol de "${u.alias}" actualizado');
    await _cargarDatos();
  }

  Future<void> _desactivar2fa(Usuario u) async {
    final ok = await _confirmar(
      'Desactivar verificación en dos pasos',
      '¿Desactivar el 2FA de "${u.alias}"? Úsalo solo si la persona '
          'perdió su app autenticadora y tampoco tiene acceso a su correo '
          'para la recuperación normal.',
      textoBoton: 'Desactivar',
      colorBoton: AppColors.error,
    );
    if (!ok) return;
    await AdminService.desactivarDosFactor(u.id!);
    _mostrarMensaje('2FA de "${u.alias}" desactivado');
    await _cargarDatos();
  }

  Future<void> _quitarBloqueo(Usuario u) async {
    await AdminService.quitarBloqueo(u.id!);
    _mostrarMensaje('Bloqueo de "${u.alias}" levantado');
    await _cargarDatos();
  }

  Future<void> _suspender(Usuario u) async {
    final ok = await _confirmar(
      'Suspender cuenta',
      '¿Suspender la cuenta de "${u.alias}"? No podrá iniciar sesión '
          'hasta que le quites la suspensión.',
      textoBoton: 'Suspender',
      colorBoton: AppColors.error,
    );
    if (!ok) return;
    await AdminService.suspenderUsuario(u.id!);
    _mostrarMensaje('Cuenta de "${u.alias}" suspendida');
    await _cargarDatos();
  }

  Future<void> _verDetalle(Usuario u) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(u.alias),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilaDetalle('Nombre', u.nombre),
              _FilaDetalle('Edad', '${u.edad}'),
              _FilaDetalle('Correo', u.correo),
              _FilaDetalle('Rol', _rolLabelEstatico(u.rol)),
              _FilaDetalle('Registrado', u.fechaRegistro),
              _FilaDetalle('Verificación en dos pasos',
                  u.totpHabilitado ? 'Activa' : 'Desactivada'),
              _FilaDetalle(
                  'Estado de la cuenta', u.estaBloqueado ? 'Bloqueada/suspendida' : 'Activa'),
              if (u.ocupacion != null || u.localidadTrabajo != null)
                _FilaDetalle('Perfil de colaborador',
                    [u.ocupacion, u.localidadTrabajo].whereType<String>().join(' · ')),
              if (u.bancoFicticio != null || u.numeroCuentaFicticia != null)
                _FilaDetalle('Cuenta bancaria (ficticia)',
                    [u.bancoFicticio, u.numeroCuentaFicticia].whereType<String>().join(' · ')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editarDatos(Usuario u) async {
    final nombreCtrl = TextEditingController(text: u.nombre);
    final edadCtrl = TextEditingController(text: '${u.edad}');
    final correoCtrl = TextEditingController(text: u.correo);
    String? error;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Editar datos de "${u.alias}"'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                ),
                TextField(
                  controller: edadCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Edad'),
                ),
                TextField(
                  controller: correoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                final edad = int.tryParse(edadCtrl.text.trim());
                if (nombreCtrl.text.trim().isEmpty ||
                    correoCtrl.text.trim().isEmpty ||
                    edad == null) {
                  setStateDialog(() => error = 'Completa todos los campos correctamente.');
                  return;
                }
                final resultado = await AdminService.actualizarDatosUsuario(
                  u.id!,
                  nombre: nombreCtrl.text.trim(),
                  edad: edad,
                  correo: correoCtrl.text.trim(),
                );
                if (resultado != null) {
                  setStateDialog(() => error = resultado);
                  return;
                }
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardar == true) await _cargarDatos();
  }

  Future<void> _resetearContrasena(Usuario u) async {
    final contrasenaCtrl = TextEditingController();
    String? error;

    final hecho = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Restablecer contraseña de "${u.alias}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Úsalo solo como soporte, cuando la persona no puede '
                'recuperarla por correo. Avísale la contraseña nueva por '
                'otro canal seguro.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contrasenaCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña nueva'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                if (contrasenaCtrl.text.length < 6) {
                  setStateDialog(() => error = 'Mínimo 6 caracteres.');
                  return;
                }
                final resultado = await AdminService.resetearContrasenaUsuario(
                    u.id!, contrasenaCtrl.text);
                if (resultado != null) {
                  setStateDialog(() => error = resultado);
                  return;
                }
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Restablecer'),
            ),
          ],
        ),
      ),
    );
    if (hecho == true) _mostrarMensaje('Contraseña de "${u.alias}" restablecida');
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

  List<Usuario> get _usuariosFiltrados {
    final texto = _busquedaUsuariosCtrl.text.trim().toLowerCase();
    if (texto.isEmpty) return _usuarios;
    return _usuarios.where((u) {
      return u.alias.toLowerCase().contains(texto) ||
          u.nombre.toLowerCase().contains(texto) ||
          u.correo.toLowerCase().contains(texto);
    }).toList();
  }

  List<Solicitud> get _solicitudesFiltradas {
    final texto = _busquedaSolicitudesCtrl.text.trim().toLowerCase();
    return _solicitudes.where((s) {
      if (_filtroEstado != null && s.estado != _filtroEstado) return false;
      if (texto.isEmpty) return true;
      return s.clienteAlias.toLowerCase().contains(texto) ||
          (s.colaboradorAlias ?? '').toLowerCase().contains(texto) ||
          s.descripcion.toLowerCase().contains(texto) ||
          s.localidad.toLowerCase().contains(texto);
    }).toList();
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
                  Column(
                    children: [
                      _ResumenUsuarios(usuarios: _usuarios),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: TextField(
                          controller: _busquedaUsuariosCtrl,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 20),
                            hintText: 'Buscar por alias, nombre o correo',
                            isDense: true,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ListaUsuarios(
                          usuarios: _usuariosFiltrados,
                          adminId: widget.usuario.id,
                          onEliminar: _eliminarUsuario,
                          onCambiarRol: _cambiarRol,
                          onDesactivar2fa: _desactivar2fa,
                          onQuitarBloqueo: _quitarBloqueo,
                          onSuspender: _suspender,
                          onVerDetalle: _verDetalle,
                          onEditarDatos: _editarDatos,
                          onResetearContrasena: _resetearContrasena,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.desktop_windows_outlined,
                                  size: 15, color: AppColors.textMuted),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'También puedes ver y gestionar solicitudes desde un computador en /admin',
                                  style: TextStyle(
                                      color: AppColors.textMuted, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: TextField(
                          controller: _busquedaSolicitudesCtrl,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 20),
                            hintText: 'Buscar por alias, localidad o descripción',
                            isDense: true,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: SizedBox(
                          height: 32,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _FiltroEstadoChip(
                                label: 'Todas',
                                seleccionado: _filtroEstado == null,
                                onTap: () => setState(() => _filtroEstado = null),
                              ),
                              const SizedBox(width: 8),
                              for (final e in EstadoSolicitud.values) ...[
                                _FiltroEstadoChip(
                                  label: e.etiqueta,
                                  seleccionado: _filtroEstado == e,
                                  onTap: () => setState(() => _filtroEstado = e),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ListaSolicitudes(
                          todasLasSolicitudes: _solicitudes,
                          solicitudes: _solicitudesFiltradas,
                          onEliminar: _eliminarSolicitud,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

String _rolLabelEstatico(RolUsuario? rol) {
  switch (rol) {
    case RolUsuario.colaborador:
      return 'Colaborador';
    case RolUsuario.cliente:
      return 'Cliente';
    case RolUsuario.administrador:
      return 'Administrador';
    case null:
      return 'Sin rol';
  }
}

class _FilaDetalle extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaDetalle(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4)),
          const SizedBox(height: 2),
          Text(valor.isEmpty ? '—' : valor,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5)),
        ],
      ),
    );
  }
}

/// Resumen rápido de cuántos usuarios hay por rol.
class _ResumenUsuarios extends StatelessWidget {
  final List<Usuario> usuarios;
  const _ResumenUsuarios({required this.usuarios});

  @override
  Widget build(BuildContext context) {
    final clientes =
        usuarios.where((u) => u.rol == RolUsuario.cliente).length;
    final colaboradores =
        usuarios.where((u) => u.rol == RolUsuario.colaborador).length;
    final bloqueados = usuarios.where((u) => u.estaBloqueado).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: _EstadisticaCard(valor: '$clientes', etiqueta: 'Clientes')),
          const SizedBox(width: 10),
          Expanded(
              child: _EstadisticaCard(
                  valor: '$colaboradores', etiqueta: 'Colaboradores')),
          const SizedBox(width: 10),
          Expanded(
              child: _EstadisticaCard(
                  valor: '$bloqueados',
                  etiqueta: 'Bloqueados',
                  colorValor: bloqueados > 0 ? AppColors.error : null)),
        ],
      ),
    );
  }
}

class _EstadisticaCard extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final Color? colorValor;
  const _EstadisticaCard(
      {required this.valor, required this.etiqueta, this.colorValor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(valor,
              style: TextStyle(
                  color: colorValor ?? AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
          const SizedBox(height: 2),
          Text(etiqueta,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _FiltroEstadoChip extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final VoidCallback onTap;
  const _FiltroEstadoChip(
      {required this.label, required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: seleccionado,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent.withOpacity(0.2),
      backgroundColor: AppColors.surfaceVariant,
      side: BorderSide(
          color: seleccionado ? AppColors.accent : AppColors.border),
      labelStyle: TextStyle(
          color: seleccionado ? AppColors.accent : AppColors.textSecondary),
    );
  }
}

class _ListaUsuarios extends StatelessWidget {
  final List<Usuario> usuarios;
  final int? adminId;
  final ValueChanged<Usuario> onEliminar;
  final ValueChanged<Usuario> onCambiarRol;
  final ValueChanged<Usuario> onDesactivar2fa;
  final ValueChanged<Usuario> onQuitarBloqueo;
  final ValueChanged<Usuario> onSuspender;
  final ValueChanged<Usuario> onVerDetalle;
  final ValueChanged<Usuario> onEditarDatos;
  final ValueChanged<Usuario> onResetearContrasena;

  const _ListaUsuarios({
    required this.usuarios,
    required this.adminId,
    required this.onEliminar,
    required this.onCambiarRol,
    required this.onDesactivar2fa,
    required this.onQuitarBloqueo,
    required this.onSuspender,
    required this.onVerDetalle,
    required this.onEditarDatos,
    required this.onResetearContrasena,
  });

  @override
  Widget build(BuildContext context) {
    if (usuarios.isEmpty) {
      return const Center(
        child: Text('Sin usuarios que coincidan',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: usuarios.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final u = usuarios[i];
        final esUnoMismo = u.id == adminId;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: u.estaBloqueado ? AppColors.error : AppColors.border),
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
                  _Badge(texto: _rolLabelEstatico(u.rol)),
                  if (!esUnoMismo)
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
              if (u.estaBloqueado)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Bloqueado por cancelar una solicitud aceptada',
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AccionMenor(
                    icono: Icons.visibility_outlined,
                    texto: 'Ver detalle',
                    onTap: () => onVerDetalle(u),
                  ),
                  _AccionMenor(
                    icono: Icons.edit_outlined,
                    texto: 'Editar datos',
                    onTap: () => onEditarDatos(u),
                  ),
                  if (!esUnoMismo) ...[
                    _AccionMenor(
                      icono: Icons.swap_horiz,
                      texto: 'Cambiar rol',
                      onTap: () => onCambiarRol(u),
                    ),
                    _AccionMenor(
                      icono: Icons.password_outlined,
                      texto: 'Restablecer contraseña',
                      onTap: () => onResetearContrasena(u),
                    ),
                    if (u.totpHabilitado)
                      _AccionMenor(
                        icono: Icons.lock_open_outlined,
                        texto: 'Desactivar 2FA',
                        onTap: () => onDesactivar2fa(u),
                      ),
                    if (u.estaBloqueado)
                      _AccionMenor(
                        icono: Icons.lock_clock_outlined,
                        texto: 'Quitar bloqueo',
                        onTap: () => onQuitarBloqueo(u),
                      )
                    else
                      _AccionMenor(
                        icono: Icons.block_outlined,
                        texto: 'Suspender cuenta',
                        onTap: () => onSuspender(u),
                      ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccionMenor extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  const _AccionMenor(
      {required this.icono, required this.texto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(texto,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _ListaSolicitudes extends StatelessWidget {
  final List<Solicitud> todasLasSolicitudes;
  final List<Solicitud> solicitudes;
  final ValueChanged<Solicitud> onEliminar;
  const _ListaSolicitudes({
    required this.todasLasSolicitudes,
    required this.solicitudes,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    // El resumen de comisiones siempre se calcula sobre TODAS las
    // solicitudes, no sobre las filtradas por la búsqueda.
    final completadas = todasLasSolicitudes
        .where((s) => s.estado == EstadoSolicitud.completada);
    final comisionTotal = completadas.fold<int>(
        0, (suma, s) => suma + comisionPlataforma(s.valorTotal));

    if (solicitudes.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ResumenComisiones(
                comisionTotal: comisionTotal, cantidad: completadas.length),
          ),
          const Expanded(
            child: Center(
              child: Text('Sin solicitudes que coincidan',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: solicitudes.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _ResumenComisiones(
              comisionTotal: comisionTotal, cantidad: completadas.length);
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
                '${s.categoria.etiqueta} · ${s.urgencia.etiqueta} · Valor de '
                'referencia (ficticio): ${formatearPesos(s.valorTotal)}',
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

class _ResumenComisiones extends StatelessWidget {
  final int comisionTotal;
  final int cantidad;
  const _ResumenComisiones({required this.comisionTotal, required this.cantidad});

  @override
  Widget build(BuildContext context) {
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
                color: Colors.black, fontWeight: FontWeight.w800, fontSize: 24),
          ),
          const SizedBox(height: 2),
          Text('De $cantidad solicitudes completadas',
              style: const TextStyle(color: Colors.black87, fontSize: 11.5)),
        ],
      ),
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
