import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../modelos/contenedores.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../tema.dart';

/// Escáner (F-03): lee el QR de un artículo o contenedor. Si la cámara no está disponible o la etiqueta
/// no lee, se escribe el código que va impreso bajo el QR.
class EscanearPantalla extends StatefulWidget {
  const EscanearPantalla({super.key, this.devolver = false});

  /// En lugar de abrir lo escaneado, regresa el código a la pantalla anterior (inventario).
  final bool devolver;

  @override
  State<EscanearPantalla> createState() => _EscanearPantallaState();
}

class _EscanearPantallaState extends State<EscanearPantalla> {
  final _camara = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  final _manual = TextEditingController();
  String? _aviso;
  bool _yendo = false;

  @override
  void dispose() {
    _camara.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _abrir(String leido) {
    if (_yendo) return;
    final codigo = codigoDeEscaneo(leido);
    if (codigo == null) {
      setState(() => _aviso = 'Este código no es del laboratorio.');
      return;
    }
    _yendo = true;
    if (widget.devolver) {
      context.pop(codigo);
    } else {
      context.pushReplacement('/q/$codigo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.devolver ? 'Escanear lo que regresa' : 'Escanear etiqueta'),
        actions: [
          TmBotonIcono(Icons.flashlight_on_outlined, etiqueta: 'Linterna', onTap: () => _camara.toggleTorch()),
          const SizedBox(width: Espacio.x2),
        ],
      ),
      body: Centrado(
        child: Column(children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Stack(alignment: Alignment.center, children: [
              MobileScanner(
                controller: _camara,
                onDetect: (captura) {
                  final valor = captura.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                  if (valor != null) _abrir(valor);
                },
                errorBuilder: (context, error) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      style: const TextStyle(color: Colors.white),
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'No hay permiso para usar la cámara. Actívalo en los ajustes del celular o del navegador, o escribe el código abajo.'
                          : 'No se pudo abrir la cámara. Escribe el código que viene impreso bajo el QR.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ]),
            ),
          ),
          if (_aviso != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.x3, Espacio.x3, Espacio.x3, 0),
              child: TmAlerta(
                titulo: _aviso!,
                texto: 'Los códigos del taller empiezan con A- (artículos) o C- (contenedores).',
                tono: Tono.error,
                accion: TmBoton('Entendido', tamano: TamanoBoton.chico, onTap: () => setState(() => _aviso = null)),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  widget.devolver
                      ? 'Apunta al QR de cada artículo que regresa.'
                      : 'Apunta al QR del artículo o del cajón. Si la etiqueta no lee, escribe el código impreso debajo.',
                  style: Tipografia.chico.copyWith(color: tema.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Espacio.x2),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      textCapitalization: TextCapitalization.characters,
                      style: Tipografia.codigoFuerte.copyWith(fontSize: 16),
                      decoration: const InputDecoration(labelText: 'O escribe el código', hintText: 'A-0101 o C-0012'),
                      onSubmitted: _abrir,
                    ),
                  ),
                  const SizedBox(width: Espacio.x2),
                  TmBoton('Abrir', tipo: TipoBoton.primario, icono: Ico.avanzar, onTap: () => _abrir(_manual.text)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
