import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_colors.dart';
import '../services/geocodificacion_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/bogota_map.dart';

/// Resultado de elegir el punto: las coordenadas y, si se eligió desde el
/// buscador, el nombre/dirección del lugar.
class PuntoSeleccionado {
  final LatLng punto;
  final String? nombre;
  const PuntoSeleccionado(this.punto, this.nombre);
}

/// Pantalla para que el Cliente marque el punto EXACTO de su solicitud:
/// buscando la dirección, el conjunto o el edificio (como en Google
/// Maps) o tocando el mapa. El Colaborador después ve ese mismo punto.
class SeleccionarPuntoScreen extends StatefulWidget {
  final LatLng centroInicial;
  final LatLng? puntoInicial;
  final String? nombreInicial;

  const SeleccionarPuntoScreen({
    super.key,
    required this.centroInicial,
    this.puntoInicial,
    this.nombreInicial,
  });

  @override
  State<SeleccionarPuntoScreen> createState() => _SeleccionarPuntoScreenState();
}

class _SeleccionarPuntoScreenState extends State<SeleccionarPuntoScreen> {
  final _mapController = MapController();
  final _busquedaCtrl = TextEditingController();
  final _busquedaFocus = FocusNode();
  Timer? _debounce;

  late LatLng? _punto = widget.puntoInicial;
  late String? _nombre = widget.nombreInicial;
  bool _aproximado = false;

  List<LugarEncontrado> _resultados = [];
  bool _buscando = false;
  bool _busquedaHecha = false;
  int _busquedaId = 0; // descarta respuestas de búsquedas viejas

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.dispose();
    _busquedaFocus.dispose();
    super.dispose();
  }

  void _alEscribir(String texto) {
    _debounce?.cancel();
    if (texto.trim().length < 3) {
      setState(() {
        _resultados = [];
        _buscando = false;
        _busquedaHecha = false;
      });
      return;
    }
    setState(() => _buscando = true);
    _debounce = Timer(const Duration(milliseconds: 600), () => _buscar(texto));
  }

  Future<void> _buscar(String texto) async {
    final id = ++_busquedaId;
    final resultados = await GeocodificacionService.buscar(
      texto,
      cerca: widget.puntoInicial ?? widget.centroInicial,
    );
    if (!mounted || id != _busquedaId) return;
    setState(() {
      _resultados = resultados;
      _buscando = false;
      _busquedaHecha = true;
    });
  }

  void _elegirResultado(LugarEncontrado lugar) {
    _busquedaFocus.unfocus();
    setState(() {
      _punto = lugar.punto;
      _nombre = lugar.etiqueta;
      _aproximado = lugar.aproximado;
      _resultados = [];
      _busquedaHecha = false;
      _busquedaCtrl.text = lugar.nombre;
    });
    _mapController.move(lugar.punto, 17);
  }

  @override
  Widget build(BuildContext context) {
    final hayPanel = _buscando || _resultados.isNotEmpty || _busquedaHecha;

    return Scaffold(
      appBar: AppBar(title: const Text('Ubicar el lugar')),
      body: Stack(
        children: [
          Positioned.fill(
            child: BogotaMap(
              controller: _mapController,
              centro: widget.puntoInicial ?? widget.centroInicial,
              zoom: 15,
              onTap: (punto) {
                _busquedaFocus.unfocus();
                setState(() {
                  _punto = punto;
                  _nombre = null;
                  _aproximado = false;
                  _resultados = [];
                  _busquedaHecha = false;
                });
              },
              marcadores: [
                if (_punto != null) buildPinMarker(punto: _punto!),
              ],
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _busquedaCtrl,
                  focusNode: _busquedaFocus,
                  onChanged: _alEscribir,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (t) {
                    _debounce?.cancel();
                    setState(() => _buscando = true);
                    _buscar(t);
                  },
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Busca una dirección, conjunto, edificio o lugar',
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textSecondary),
                    suffixIcon: _busquedaCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close,
                                color: AppColors.textSecondary),
                            onPressed: () {
                              _busquedaCtrl.clear();
                              _alEscribir('');
                            },
                          ),
                    fillColor: AppColors.surface,
                  ),
                ),
                if (hayPanel)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _buscando
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: AppColors.accent),
                              ),
                            ),
                          )
                        : _resultados.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No encontramos ese lugar. Prueba con el '
                                  'nombre del conjunto o edificio, o con la '
                                  'calle o carrera, o toca el mapa.',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12.5),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _resultados.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, color: AppColors.border),
                                itemBuilder: (context, i) {
                                  final l = _resultados[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.place_outlined,
                                        color: AppColors.accentText),
                                    title: Text(l.nombre,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: (l.detalle.isEmpty && !l.aproximado)
                                        ? null
                                        : Text(
                                            l.aproximado
                                                ? 'Ubica la vía (aproximado)'
                                                    '${l.detalle.isEmpty ? '' : ' · ${l.detalle}'}'
                                                : l.detalle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12)),
                                    onTap: () => _elegirResultado(l),
                                  );
                                },
                              ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    _punto == null
                        ? 'Busca el lugar arriba o toca el mapa donde quieres '
                            'que vaya el colaborador.'
                        : (_aproximado
                            ? 'Ubicamos la vía, no el número exacto. Toca el '
                                'mapa en el sitio correcto para ajustar el punto.'
                            : _nombre != null
                            ? 'Punto: $_nombre\nPuedes ajustarlo tocando el mapa.'
                            : 'Punto marcado en el mapa. Puedes ajustarlo '
                                'tocando otro sitio.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ),
                PrimaryButton(
                  label:
                      _punto == null ? 'ELIGE UN PUNTO PRIMERO' : 'USAR ESTE PUNTO',
                  onPressed: _punto == null
                      ? null
                      : () => Navigator.of(context)
                          .pop(PuntoSeleccionado(_punto!, _nombre)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
