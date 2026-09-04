import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/bogota_localidades.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/solicitud_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/solicitud_info_row.dart';
import 'ganancias_screen.dart';
import 'historial_solicitudes_screen.dart';
import 'role_selection_screen.dart';
import 'splash_screen.dart';
import 'two_factor_setup_screen.dart';

/// Bancos ficticios para el selector de cuenta bancaria del colaborador
/// (no representan entidades reales conectadas a la app).
const _kBancosFicticios = [
  'Banco Inspector',
  'Banco Andino (simulado)',
  'Banco Capital (simulado)',
  'Billetera Digital (simulado)',
];

class HomeScreen extends StatefulWidget {
  final Usuario usuario;
  const HomeScreen({super.key, required this.usuario});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Usuario _usuario = widget.usuario;
  Solicitud? _solicitudActiva;
  bool _cargandoSolicitud = false;
  bool _cargando2fa = false;
  bool _guardandoPerfil = false;

  late final _ocupacionCtrl = TextEditingController(text: _usuario.ocupacion);
  String? _localidadTrabajo;

  String? _bancoFicticio;
  late final _numeroCuentaCtrl =
      TextEditingController(text: _usuario.numeroCuentaFicticia);
  bool _guardandoCuenta = false;

  @override
  void initState() {
    super.initState();
    _localidadTrabajo = _usuario.localidadTrabajo;
    _bancoFicticio = _usuario.bancoFicticio;
    if (_usuario.rol == RolUsuario.cliente) {
      _cargarSolicitudActiva();
    }
  }

  @override
  void dispose() {
    _ocupacionCtrl.dispose();
    _numeroCuentaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarSolicitudActiva() async {
    setState(() => _cargandoSolicitud = true);
    try {
      final activa =
          await SolicitudService.solicitudActivaDeCliente(_usuario.alias);
      if (!mounted) return;
      setState(() => _solicitudActiva = activa);
    } catch (_) {
      // Sin conexión al backend: se muestra sin solicitud activa.
    } finally {
      if (mounted) setState(() => _cargandoSolicitud = false);
    }
  }

  String get _rolLabel {
    switch (_usuario.rol) {
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

  void _cerrarSesion(BuildContext context) {
    SessionService.instance.cerrarSesion();
    Navigator.of(context).pushAndRemoveUntil(
      AppRoutes.fade(const SplashScreen()),
      (route) => false,
    );
  }

  void _cambiarRol(BuildContext context) {
    Navigator.of(context).push(
      AppRoutes.slide(RoleSelectionScreen(usuario: _usuario)),
    );
  }

  Future<void> _activar2fa() async {
    final resultado = await Navigator.of(context).push<Usuario>(
      AppRoutes.slide(TwoFactorSetupScreen(usuario: _usuario)),
    );
    if (resultado != null && mounted) {
      setState(() => _usuario = resultado);
      SessionService.instance.iniciarSesion(resultado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verificación en dos pasos activada')),
      );
    }
  }

  Future<void> _desactivar2fa() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desactivar verificación en dos pasos'),
        content: const Text(
          '¿Seguro que quieres desactivarla? Tu cuenta quedará protegida '
          'solo con tu contraseña.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desactivar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _cargando2fa = true);
    final actualizado = await AuthService.desactivarDobleFactor(_usuario.id!);
    if (!mounted) return;
    setState(() {
      _usuario = actualizado;
      _cargando2fa = false;
    });
    SessionService.instance.iniciarSesion(actualizado);
  }

  Future<void> _guardarPerfilColaborador() async {
    setState(() => _guardandoPerfil = true);
    final actualizado = await AuthService.actualizarPerfilColaborador(
      usuarioId: _usuario.id!,
      ocupacion: _ocupacionCtrl.text.trim().isEmpty
          ? null
          : _ocupacionCtrl.text.trim(),
      localidadTrabajo: _localidadTrabajo,
    );
    if (!mounted) return;
    setState(() {
      _usuario = actualizado;
      _guardandoPerfil = false;
    });
    SessionService.instance.iniciarSesion(actualizado);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil actualizado')),
    );
  }

  Future<void> _guardarCuentaBancaria() async {
    if (_numeroCuentaCtrl.text.trim().isNotEmpty && _bancoFicticio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige un banco')),
      );
      return;
    }
    setState(() => _guardandoCuenta = true);
    final actualizado = await AuthService.actualizarCuentaBancaria(
      usuarioId: _usuario.id!,
      banco: _bancoFicticio,
      numeroCuenta: _numeroCuentaCtrl.text.trim().isEmpty
          ? null
          : _numeroCuentaCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _usuario = actualizado;
      _guardandoCuenta = false;
    });
    SessionService.instance.iniciarSesion(actualizado);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cuenta bancaria (ficticia) guardada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = _usuario;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Row(
                children: [
                  Image.asset(
                    'assets/icon/app_icon.png',
                    width: 44,
                    height: 44,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'INSPECTOR',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _cerrarSesion(context),
                    icon: const Icon(Icons.logout,
                        color: AppColors.textSecondary),
                    tooltip: 'Cerrar sesión',
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usuario.alias,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _rolLabel.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const Divider(height: 28, color: AppColors.border),
                    _InfoRow(label: 'Nombre', value: usuario.nombre),
                    _InfoRow(label: 'Correo', value: usuario.correo),
                    _InfoRow(label: 'Edad', value: usuario.edad.toString()),
                  ],
                ),
              ),
              if (usuario.rol == RolUsuario.cliente) ...[
                const SizedBox(height: 20),
                _SolicitudActivaCard(
                  solicitud: _solicitudActiva,
                  cargando: _cargandoSolicitud,
                ),
                const SizedBox(height: 12),
                OutlineActionButton(
                  label: 'VER HISTORIAL DE SOLICITUDES',
                  onPressed: () {
                    Navigator.of(context).push(AppRoutes.slide(
                      HistorialSolicitudesScreen(usuario: usuario),
                    ));
                  },
                ),
              ],
              if (usuario.rol == RolUsuario.colaborador) ...[
                const SizedBox(height: 20),
                _DatosProfesionalesCard(
                  ocupacionCtrl: _ocupacionCtrl,
                  localidadTrabajo: _localidadTrabajo,
                  cargando: _guardandoPerfil,
                  onLocalidadChanged: (l) =>
                      setState(() => _localidadTrabajo = l),
                  onGuardar: _guardarPerfilColaborador,
                ),
                const SizedBox(height: 20),
                _CuentaBancariaCard(
                  banco: _bancoFicticio,
                  numeroCuentaCtrl: _numeroCuentaCtrl,
                  cargando: _guardandoCuenta,
                  onBancoChanged: (b) => setState(() => _bancoFicticio = b),
                  onGuardar: _guardarCuentaBancaria,
                ),
                const SizedBox(height: 12),
                OutlineActionButton(
                  label: 'VER GANANCIAS',
                  onPressed: () {
                    Navigator.of(context).push(
                        AppRoutes.slide(GananciasScreen(usuario: usuario)));
                  },
                ),
              ],
              const SizedBox(height: 20),
              _SeguridadCard(
                habilitado: usuario.totpHabilitado,
                cargando: _cargando2fa,
                onActivar: _activar2fa,
                onDesactivar: _desactivar2fa,
              ),
              const SizedBox(height: 20),
              OutlineActionButton(
                label: 'CAMBIAR DE ROL',
                onPressed: () => _cambiarRol(context),
              ),
              const SizedBox(height: 32),
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'Todos tus datos se almacenan únicamente en este dispositivo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta al estilo Uber que muestra, en el perfil del Cliente, si hay
/// una solicitud activa y en qué va su estado.
class _SolicitudActivaCard extends StatelessWidget {
  final Solicitud? solicitud;
  final bool cargando;
  const _SolicitudActivaCard({required this.solicitud, required this.cargando});

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (solicitud == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'No tienes solicitudes activas en este momento.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    final s = solicitud!;
    final esPendiente = s.estado == EstadoSolicitud.pendiente;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                esPendiente
                    ? Icons.hourglass_top_rounded
                    : Icons.directions_walk_rounded,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                s.estado.etiqueta,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Divider(height: 22, color: AppColors.border),
          SolicitudInfoRow(icono: Icons.category_outlined, texto: s.categoria.etiqueta),
          SolicitudInfoRow(icono: Icons.checklist_outlined, texto: s.tiposEtiqueta),
          SolicitudInfoRow(icono: Icons.bolt_outlined, texto: s.urgencia.etiqueta),
          SolicitudInfoRow(icono: Icons.place_outlined, texto: s.localidad),
          if (s.direccion.isNotEmpty)
            SolicitudInfoRow(
                icono: Icons.location_on_outlined, texto: s.direccion),
          SolicitudInfoRow(icono: Icons.notes_outlined, texto: s.descripcion),
        ],
      ),
    );
  }
}

/// Tarjeta de "Seguridad" en el Perfil: estado de la verificación en dos
/// pasos (TOTP) y botón para activarla o desactivarla.
class _SeguridadCard extends StatelessWidget {
  final bool habilitado;
  final bool cargando;
  final VoidCallback onActivar;
  final VoidCallback onDesactivar;

  const _SeguridadCard({
    required this.habilitado,
    required this.cargando,
    required this.onActivar,
    required this.onDesactivar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                habilitado ? Icons.shield : Icons.shield_outlined,
                color: habilitado ? AppColors.success : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Verificación en dos pasos',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            habilitado
                ? 'Activada: además de tu contraseña, se pide un código de '
                    'tu app autenticadora al iniciar sesión.'
                : 'Desactivada: activa un código de tu app autenticadora '
                    '(Google Authenticator, Authy, etc.) como segundo factor.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          habilitado
              ? OutlineActionButton(
                  label: cargando ? 'DESACTIVANDO...' : 'DESACTIVAR',
                  onPressed: cargando ? null : onDesactivar,
                )
              : PrimaryButton(
                  label: 'ACTIVAR',
                  isLoading: cargando,
                  onPressed: onActivar,
                ),
        ],
      ),
    );
  }
}

/// Tarjeta opcional del Perfil de Colaborador: ocupación y localidad de
/// Bogotá donde prefiere trabajar, usada para completar su información.
class _DatosProfesionalesCard extends StatelessWidget {
  final TextEditingController ocupacionCtrl;
  final String? localidadTrabajo;
  final bool cargando;
  final ValueChanged<String?> onLocalidadChanged;
  final VoidCallback onGuardar;

  const _DatosProfesionalesCard({
    required this.ocupacionCtrl,
    required this.localidadTrabajo,
    required this.cargando,
    required this.onLocalidadChanged,
    required this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos profesionales',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Opcional: cuéntanos a qué te dedicas y en qué localidad '
            'prefieres trabajar.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ocupacionCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Ocupación',
              helperText: 'Ej: fotógrafo, redactor, investigador de campo',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: localidadTrabajo,
            dropdownColor: AppColors.surfaceVariant,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Localidad donde quiere trabajar',
              helperText: 'La localidad de Bogotá donde prefieres atender '
                  'solicitudes',
            ),
            items: kLocalidadesBogota.keys
                .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                .toList(),
            onChanged: onLocalidadChanged,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'GUARDAR',
            isLoading: cargando,
            onPressed: onGuardar,
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de "Cuenta bancaria" del Colaborador — FICTICIA: no hay
/// pasarela de pagos real ni transferencias de dinero de verdad, solo
/// se guarda para simular a dónde "llegaría" el pago al completar una
/// solicitud (ver `lib/screens/ganancias_screen.dart`).
class _CuentaBancariaCard extends StatelessWidget {
  final String? banco;
  final TextEditingController numeroCuentaCtrl;
  final bool cargando;
  final ValueChanged<String?> onBancoChanged;
  final VoidCallback onGuardar;

  const _CuentaBancariaCard({
    required this.banco,
    required this.numeroCuentaCtrl,
    required this.cargando,
    required this.onBancoChanged,
    required this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuenta bancaria (ficticia)',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'A esta cuenta simulada "llega" el pago cuando completas una '
            'solicitud — no hay dinero real ni transferencias de verdad.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: banco,
            dropdownColor: AppColors.surfaceVariant,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(labelText: 'Banco'),
            items: _kBancosFicticios
                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                .toList(),
            onChanged: onBancoChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: numeroCuentaCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Número de cuenta',
              helperText: 'Cualquier número: no se valida ni se conecta a '
                  'ningún banco real',
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'GUARDAR',
            isLoading: cargando,
            onPressed: onGuardar,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
