import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/errores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import 'fotos.dart';

/// − 3 + con botones grandes (manos ocupadas en el taller).
class SelectorCantidad extends StatelessWidget {
  const SelectorCantidad({super.key, required this.valor, required this.alCambiar, this.minimo = 0, required this.maximo, this.etiqueta});

  final int valor;
  final int minimo;
  final int maximo;
  final ValueChanged<int> alCambiar;
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (etiqueta != null) Padding(padding: const EdgeInsets.only(right: 12), child: Text(etiqueta!, style: tema.textTheme.bodyLarge)),
      IconButton.filledTonal(
        icon: const Icon(Ico.quitarUno),
        tooltip: 'Menos',
        onPressed: valor > minimo ? () => alCambiar(valor - 1) : null,
      ),
      SizedBox(width: 56, child: Text('$valor', textAlign: TextAlign.center, style: tema.textTheme.headlineSmall)),
      IconButton.filledTonal(
        icon: const Icon(Ico.nuevo),
        tooltip: 'Más',
        onPressed: valor < maximo ? () => alCambiar(valor + 1) : null,
      ),
    ]);
  }
}

/// Fotos elegidas para un reporte (se suben al guardar).
class SelectorFotos extends StatelessWidget {
  const SelectorFotos({super.key, required this.fotos, required this.alCambiar, this.texto = 'Agregar foto', this.maximo = 10});

  final List<FotoNueva> fotos;
  final VoidCallback alCambiar;
  final String texto;
  final int maximo;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in fotos)
        Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(f.bytes, width: 96, height: 96, fit: BoxFit.cover)),
          Positioned(
            right: 0,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Ico.cerrar, size: 18),
              tooltip: 'Quitar',
              onPressed: () {
                fotos.remove(f);
                alCambiar();
              },
            ),
          ),
        ]),
      if (fotos.length < maximo)
      SizedBox(
        width: 96,
        height: 96,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: () async {
            final foto = await elegirFoto(context);
            if (foto != null) {
              fotos.add(foto);
              alCambiar();
            }
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Ico.agregarFoto),
            const SizedBox(height: 4),
            Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    ]);
  }
}

/// Foto del almacén privado: se pide un enlace temporal y solo abre si la cuenta tiene permiso.
class FotoPrivada extends ConsumerWidget {
  const FotoPrivada({super.key, required this.ruta, this.tamano = 96});

  final String ruta;
  final double tamano;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.read(repositorioProvider).urlPrivada(ruta),
      builder: (context, snap) {
        final caja = SizedBox(width: tamano, height: tamano);
        if (!snap.hasData) {
          return snap.hasError ? SizedBox(width: tamano, height: tamano, child: const Icon(Ico.noSePresta)) : caja;
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
              body: InteractiveViewer(maxScale: 6, child: Center(child: Image.network(snap.data!))),
            ),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(snap.data!, width: tamano, height: tamano, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

/// Pantalla cuyo contenido necesita sesión (listas con nombres): pide acceso primero y luego carga.
class CargaConAcceso<T> extends ConsumerStatefulWidget {
  const CargaConAcceso({
    super.key,
    required this.descripcion,
    required this.requisito,
    required this.cargar,
    required this.construir,
  });

  final String descripcion;
  final Requisito requisito;
  final Future<T> Function(Repositorio repo) cargar;
  final Widget Function(BuildContext context, T datos, Future<void> Function() recargar) construir;

  @override
  ConsumerState<CargaConAcceso<T>> createState() => _CargaConAccesoState<T>();
}

class _CargaConAccesoState<T> extends ConsumerState<CargaConAcceso<T>> {
  T? _datos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await conAcceso<T>(
        context,
        ref,
        descripcion: widget.descripcion,
        requisito: widget.requisito,
        accion: () => widget.cargar(ref.read(repositorioProvider)),
      );
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _error = datos == null ? 'Se necesita identificarse para ver esto.' : null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = traducir(e).mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_datos != null) {
      return Stack(children: [
        RefreshIndicator(onRefresh: _cargar, child: widget.construir(context, _datos as T, _cargar)),
        if (_cargando) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
      ]);
    }
    if (_cargando) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
        ]),
      ),
    );
  }
}

/// Pide un texto (motivo, justificación, comentario). Devuelve null si se cancela.
Future<String?> pedirTexto(BuildContext context,
    {required String titulo, required String etiqueta, int minimo = 1, String? ayuda, String boton = 'Continuar'}) {
  final controlador = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: controlador,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: controlador.text.trim().length >= minimo ? () => Navigator.pop(context, controlador.text.trim()) : null,
            child: Text(boton),
          ),
        ],
      ),
    ),
  ).whenComplete(controlador.dispose);
}

/// Elige una fecha de devolución y la deja a la hora de fin de jornada.
Future<DateTime?> elegirFechaDevolucion(BuildContext context, {DateTime? desde, int maxDias = 30}) async {
  final hoy = DateTime.now();
  final inicial = (desde ?? hoy).add(const Duration(days: 1));
  final dia = await showDatePicker(
    context: context,
    initialDate: inicial,
    firstDate: DateTime(hoy.year, hoy.month, hoy.day),
    lastDate: hoy.add(Duration(days: maxDias)),
    helpText: 'Fecha de devolución',
  );
  if (dia == null) return null;
  return DateTime(dia.year, dia.month, dia.day, 15);
}

String nombreTipoSolicitante(TipoSolicitante t) => t.nombre;
