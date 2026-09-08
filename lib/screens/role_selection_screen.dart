import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/role_navigation.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';

/// Se muestra solo la primera vez que el usuario inicia sesión, o
/// mientras no haya seleccionado un rol. La elección se guarda en el
/// servidor y no se vuelve a preguntar en futuros inicios de sesión.
class RoleSelectionScreen extends StatefulWidget {
  final Usuario usuario;
  const RoleSelectionScreen({super.key, required this.usuario});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _cargando = false;

  Future<void> _seleccionar(RolUsuario rol) async {
    setState(() => _cargando = true);
    try {
      final actualizado = await AuthService.seleccionarRol(
        usuarioId: widget.usuario.id!,
        rol: rol,
      );
      SessionService.instance.iniciarSesion(actualizado);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        AppRoutes.fade(pantallaPrincipalParaRol(actualizado)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo conectar con el servidor. Revisa tu conexión.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text(
                'Bienvenido, ${widget.usuario.alias}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '¿Cómo deseas usar Inspector?',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 36),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _cargando,
                  child: Column(
                    children: [
                      _RoleCard(
                        emoji: '🔍',
                        titulo: 'SOY COLABORADOR',
                        descripcion: 'Reporta, documenta e inspecciona',
                        onTap: () => _seleccionar(RolUsuario.colaborador),
                      ),
                      const SizedBox(height: 20),
                      _RoleCard(
                        emoji: '👤',
                        titulo: 'SOY CLIENTE',
                        descripcion: 'Consulta, solicita y da seguimiento',
                        onTap: () => _seleccionar(RolUsuario.cliente),
                      ),
                    ],
                  ),
                ),
              ),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 16),
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
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descripcion,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
