import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/documentos_legales.dart';

/// Términos y condiciones, políticas de uso, tratamiento de datos y
/// normatividad, en pestañas. Se abre en la pestaña que se le indique.
class PolicyScreen extends StatelessWidget {
  final int pestanaInicial;
  const PolicyScreen({super.key, this.pestanaInicial = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kDocumentosLegales.length,
      initialIndex: pestanaInicial.clamp(0, kDocumentosLegales.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Términos y políticas'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accentText,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: kDocumentosLegales
                .map((d) => Tab(text: d.tituloCorto))
                .toList(),
          ),
        ),
        body: TabBarView(
          children: kDocumentosLegales.map((d) => _Documento(doc: d)).toList(),
        ),
      ),
    );
  }
}

class _Documento extends StatelessWidget {
  final DocumentoLegal doc;
  const _Documento({required this.doc});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            Icon(doc.icono, color: AppColors.accentText, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                doc.titulo,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${doc.resumen}\n$kVersionDocumentosLegales',
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 18),
        for (final s in doc.secciones) ...[
          Text(
            s.titulo,
            style: const TextStyle(
              color: AppColors.accentText,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.texto,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
