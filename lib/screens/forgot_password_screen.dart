import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/email_verification_service.dart';
import '../widgets/app_buttons.dart';

enum _Paso { busqueda, verificarCorreo, restablecer }

/// Recuperación de contraseña: se identifica la cuenta por su alias o
/// nombre completo y LUEGO se verifica con un código enviado a su
/// correo — ya no es "sin verificar nada" como cuando las cuentas eran
/// 100% locales a un solo celular: ahora cualquier dispositivo puede
/// alcanzar cualquier cuenta, así que hace falta esa comprobación.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _busquedaCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  _Paso _paso = _Paso.busqueda;
  Usuario? _usuarioEncontrado;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _codigoCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarUsuario() async {
    if (_busquedaCtrl.text.trim().isEmpty) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuario =
          await AuthService.buscarParaRecuperacion(_busquedaCtrl.text);
      setState(() => _usuarioEncontrado = usuario);
      await _enviarCodigo();
    } on AuthException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() =>
          _error = 'No se pudo conectar con el servidor. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _enviarCodigo() async {
    setState(() => _error = null);
    try {
      await EmailVerificationService.enviarCodigo(_usuarioEncontrado!.correo);
      setState(() => _paso = _Paso.verificarCorreo);
    } on EmailVerificationException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo enviar el correo de verificación.');
    }
  }

  Future<void> _verificarCodigo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await EmailVerificationService.verificarCodigo(
        _usuarioEncontrado!.correo,
        _codigoCtrl.text,
      );
      setState(() => _paso = _Paso.restablecer);
    } on EmailVerificationException catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _restablecer() async {
    if (_nuevaCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña debe tener mínimo 6 caracteres')),
      );
      return;
    }
    if (_nuevaCtrl.text != _confirmarCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }

    setState(() => _cargando = true);
    try {
      await AuthService.restablecerContrasena(
        usuarioId: _usuarioEncontrado!.id!,
        nuevaContrasena: _nuevaCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada. Ya puedes iniciar sesión.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      setState(() =>
          _error = 'No se pudo actualizar la contraseña. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Oculta la mayor parte del correo antes de mostrarlo: "me***@gmail.com".
  String _correoOculto(String correo) {
    final partes = correo.split('@');
    if (partes.length != 2 || partes[0].length < 2) return correo;
    return '${partes[0].substring(0, 2)}***@${partes[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: switch (_paso) {
            _Paso.busqueda => _buildBusqueda(),
            _Paso.verificarCorreo => _buildVerificarCorreo(),
            _Paso.restablecer => _buildRestablecer(),
          },
        ),
      ),
    );
  }

  List<Widget> _buildBusqueda() {
    return [
      const Text(
        'Ingresa tu alias o tu nombre completo para verificar tu identidad.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _busquedaCtrl,
        decoration: const InputDecoration(
          labelText: 'Alias o nombre completo',
          hintText: 'Ej: Inspector_7K2QXR9L',
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
      ],
      const SizedBox(height: 20),
      PrimaryButton(
        label: 'BUSCAR CUENTA',
        isLoading: _cargando,
        onPressed: _buscarUsuario,
      ),
    ];
  }

  List<Widget> _buildVerificarCorreo() {
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cuenta encontrada: ${_usuarioEncontrado!.alias}\n'
                'Enviamos un código a ${_correoOculto(_usuarioEncontrado!.correo)}',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _codigoCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 22, letterSpacing: 6),
        decoration: const InputDecoration(counterText: '', hintText: '000000'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _cargando ? null : _enviarCodigo,
          child: const Text('Reenviar código',
              style: TextStyle(color: AppColors.accent, fontSize: 13)),
        ),
      ),
      const SizedBox(height: 8),
      PrimaryButton(
        label: 'VERIFICAR CÓDIGO',
        isLoading: _cargando,
        onPressed: _verificarCodigo,
      ),
    ];
  }

  List<Widget> _buildRestablecer() {
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Identidad verificada: ${_usuarioEncontrado!.alias}',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _nuevaCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Nueva contraseña',
          helperText: 'Mínimo 6 caracteres',
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _confirmarCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Confirmar nueva contraseña',
          helperText: 'Escribe la misma contraseña otra vez',
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
      ],
      const SizedBox(height: 20),
      PrimaryButton(
        label: 'RESTABLECER CONTRASEÑA',
        isLoading: _cargando,
        onPressed: _restablecer,
      ),
    ];
  }
}
