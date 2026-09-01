import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/role_navigation.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/email_verification_service.dart';
import '../services/session_service.dart';
import '../services/two_factor_service.dart';
import '../widgets/app_buttons.dart';
import 'role_selection_screen.dart';

/// Segundo paso del login cuando el usuario tiene la verificación en dos
/// pasos activada: pide el código de 6 dígitos de su app autenticadora.
/// La contraseña ya fue validada antes de llegar aquí.
class TwoFactorVerifyScreen extends StatefulWidget {
  final Usuario usuario;
  const TwoFactorVerifyScreen({super.key, required this.usuario});

  @override
  State<TwoFactorVerifyScreen> createState() => _TwoFactorVerifyScreenState();
}

class _TwoFactorVerifyScreenState extends State<TwoFactorVerifyScreen> {
  final _codigoCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  // ---- Recuperación por correo (si se perdió el código de la app) ----
  bool _mostrandoRecuperacion = false;
  bool _codigoRecuperacionEnviado = false;
  bool _enviandoRecuperacion = false;
  final _codigoRecuperacionCtrl = TextEditingController();

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _codigoRecuperacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar(Usuario usuario) async {
    SessionService.instance.iniciarSesion(usuario);
    if (!mounted) return;

    if (usuario.rol == null) {
      Navigator.of(context).pushReplacement(
        AppRoutes.fade(RoleSelectionScreen(usuario: usuario)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        AppRoutes.fade(pantallaPrincipalParaRol(usuario)),
      );
    }
  }

  Future<void> _verificar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final valido = TwoFactorService.verificarCodigo(
      widget.usuario.totpSecret!,
      _codigoCtrl.text,
    );

    if (!valido) {
      setState(() {
        _cargando = false;
        _error = 'Código incorrecto. Inténtalo de nuevo.';
      });
      return;
    }

    await _entrar(widget.usuario);
  }

  Future<void> _enviarCodigoRecuperacion() async {
    setState(() {
      _enviandoRecuperacion = true;
      _error = null;
    });
    try {
      await EmailVerificationService.enviarCodigo(widget.usuario.correo);
      if (!mounted) return;
      setState(() => _codigoRecuperacionEnviado = true);
    } on EmailVerificationException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error =
          'No se pudo enviar el correo. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _enviandoRecuperacion = false);
    }
  }

  Future<void> _verificarCodigoRecuperacion() async {
    setState(() {
      _enviandoRecuperacion = true;
      _error = null;
    });
    try {
      await EmailVerificationService.verificarCodigo(
        widget.usuario.correo,
        _codigoRecuperacionCtrl.text,
      );
      // El código del correo es correcto: desactivamos la verificación
      // en dos pasos de esta cuenta para dejarlo entrar. Podrá volver a
      // activarla (con un código nuevo) desde su perfil.
      final actualizado =
          await AuthService.desactivarDobleFactor(widget.usuario.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Verificación en dos pasos desactivada. Puedes volver a activarla desde tu perfil.'),
      ));
      await _entrar(actualizado);
    } on EmailVerificationException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() =>
          _error = 'No se pudo verificar el código. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _enviandoRecuperacion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en dos pasos')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Abre tu app autenticadora e ingresa el código de 6 '
                'dígitos de Inspector.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codigoCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'VERIFICAR',
                isLoading: _cargando,
                onPressed: _verificar,
              ),
              const SizedBox(height: 16),
              if (!_mostrandoRecuperacion)
                Center(
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _mostrandoRecuperacion = true),
                    child: const Text(
                      '¿Perdiste el código? Recuperar por correo',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ),
                )
              else
                _PanelRecuperacion(
                  codigoEnviado: _codigoRecuperacionEnviado,
                  enviando: _enviandoRecuperacion,
                  codigoCtrl: _codigoRecuperacionCtrl,
                  onEnviarCodigo: _enviarCodigoRecuperacion,
                  onVerificarCodigo: _verificarCodigoRecuperacion,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelRecuperacion extends StatelessWidget {
  final bool codigoEnviado;
  final bool enviando;
  final TextEditingController codigoCtrl;
  final VoidCallback onEnviarCodigo;
  final VoidCallback onVerificarCodigo;

  const _PanelRecuperacion({
    required this.codigoEnviado,
    required this.enviando,
    required this.codigoCtrl,
    required this.onEnviarCodigo,
    required this.onVerificarCodigo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recuperar acceso por correo',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5),
          ),
          const SizedBox(height: 6),
          Text(
            codigoEnviado
                ? 'Escribe el código de 6 dígitos que te enviamos a tu '
                    'correo registrado. Al verificarlo, se desactiva la '
                    'verificación en dos pasos de esta cuenta.'
                : 'Te enviaremos un código de 6 dígitos a tu correo '
                    'registrado para desactivar la verificación en dos '
                    'pasos y dejarte entrar.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (codigoEnviado) ...[
            TextField(
              controller: codigoCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 20, letterSpacing: 6),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
              ),
            ),
            const SizedBox(height: 8),
            OutlineActionButton(
              label: enviando ? 'VERIFICANDO...' : 'VERIFICAR Y DESACTIVAR 2FA',
              onPressed: enviando ? null : onVerificarCodigo,
            ),
            TextButton(
              onPressed: enviando ? null : onEnviarCodigo,
              child: const Text('Reenviar código',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          ] else
            OutlineActionButton(
              label: enviando ? 'ENVIANDO...' : 'ENVIAR CÓDIGO A MI CORREO',
              onPressed: enviando ? null : onEnviarCodigo,
            ),
        ],
      ),
    );
  }
}
