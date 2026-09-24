import '../armazon.dart';
import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../acceso/gate.dart';
import '../../datos/proveedores.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/contenedores.dart';
import '../../util/etiquetas.dart';
import '../../util/etiquetas_pdf.dart' deferred as hoja;
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';

/// Hoja de etiquetas QR para imprimir (F-12): contenedores y artículos con etiqueta propia.
class EtiquetasPantalla extends ConsumerStatefulWidget {
  const EtiquetasPantalla({super.key, this.codigos = const []});

  /// Códigos que llegan ya elegidos (desde un contenedor o una ficha).
  final List<String> codigos;

  @override
  ConsumerState<EtiquetasPantalla> createState() => _EtiquetasPantallaState();
}

class _EtiquetasPantallaState extends ConsumerState<EtiquetasPantalla> {
  late final _elegidos = <String>{...widget.codigos.map((c) => c.toUpperCase())};
  FormatoEtiqueta _formato = FormatoEtiqueta.chica;
  int _empezarEn = 1;
  String _texto = '';
  bool _generando = false;

  Future<void> _imprimir(List<EtiquetaDatos> etiquetas, String urlApp) async {
    setState(() => _generando = true);
    try {
      await hoja.loadLibrary();
      await hoja.imprimirEtiquetas(etiquetas, _formato, urlApp, empezarEn: _empezarEn);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sesion = ref.watch(sesionProvider).value;
    final contenedores = (ref.watch(contenedoresProvider).value ?? const <Contenedor>[]).where((c) => c.activo).toList();
    final articulos = (ref.watch(articulosProvider).value ?? const <Articulo>[])
        .where((a) => a.activo && a.etiquetado == Etiquetado.individual)
        .toList();
    final urlApp = ref.watch(configuracionProvider).value?['url_app'] as String?;
    final publicada = urlApp != null && urlApp.startsWith('https://');

    final opciones = <EtiquetaDatos>[
      for (final (c, _) in comoArbol(contenedores))
        EtiquetaDatos(codigo: c.codigo, titulo: c.nombre, detalle: c.padreId == null ? c.nombreCategoria : c.ruta),
      for (final a in articulos..sort((x, y) => x.codigo.compareTo(y.codigo)))
        EtiquetaDatos(codigo: a.codigo, titulo: a.nombre, detalle: [a.categoria.nombre, if (a.numSerie != null) 'S/N ${a.numSerie}'].join(' · ')),
    ];
    final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty);
    final visibles = opciones.where((e) => palabras.every(normalizar('${e.codigo} ${e.titulo} ${e.detalle ?? ''}').contains)).toList();
    final elegidas = opciones.where((e) => _elegidos.contains(e.codigo)).toList();
    final hojas = elegidas.isEmpty ? 0 : ((elegidas.length + _empezarEn - 1) / _formato.porHoja).ceil();

    if (!(sesion?.administra ?? false)) {
      return TmArmazon(
               ruta: '/etiquetas',
               titulo: 'Etiquetas',
               conRegresar: true,
               child: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Las etiquetas las imprime el responsable del laboratorio o sub administración.'))),
             );
    }

    return TmArmazon(
             ruta: '/etiquetas',
             titulo: 'Imprimir etiquetas',
             conRegresar: true,
             barraInferior: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: elegidas.isEmpty || _generando || !publicada ? null : () => _imprimir(elegidas, urlApp),
            icon: _generando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Ico.imprimir),
            label: Text(elegidas.isEmpty ? 'Elige qué imprimir' : 'Imprimir ${elegidas.length} en $hojas hoja${hojas == 1 ? '' : 's'}'),
          ),
        ),
      ),
             child: Centrado(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!publicada)
            Card(
              color: tema.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Ico.aviso),
                title: const Text('Todavía no se publica la app web.'),
                subtitle: Text('Los QR llevan la dirección de la app (ahora es ${urlApp ?? 'ninguna'}). '
                    'Una etiqueta impresa con esa dirección no abriría en otros celulares.'),
              ),
            ),
          Text('Formato de hoja (carta)', style: tema.textTheme.titleSmall),
          for (final f in FormatoEtiqueta.values)
            RadioListTile<FormatoEtiqueta>(
              value: f,
              groupValue: _formato,
              onChanged: (v) => setState(() {
                _formato = v!;
                _empezarEn = _empezarEn.clamp(1, _formato.porHoja);
              }),
              title: Text(f.nombre),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          Row(children: [
            const Expanded(child: Text('Empezar en la etiqueta número (para usar una hoja ya empezada)')),
            SelectorCantidad(valor: _empezarEn, minimo: 1, maximo: _formato.porHoja, alCambiar: (v) => setState(() => _empezarEn = v)),
          ]),
          const Divider(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
              label: Text('Todos los contenedores (${contenedores.length})'),
              onPressed: () => setState(() => _elegidos.addAll(contenedores.map((c) => c.codigo))),
            ),
            ActionChip(
              label: Text('Artículos con etiqueta propia (${articulos.length})'),
              onPressed: () => setState(() => _elegidos.addAll(articulos.map((a) => a.codigo))),
            ),
            if (_elegidos.isNotEmpty) ActionChip(label: const Text('Quitar todo'), onPressed: () => setState(_elegidos.clear)),
          ]),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Ico.buscar), hintText: 'Buscar por código o nombre'),
            onChanged: (t) => setState(() => _texto = t),
          ),
          for (final e in visibles)
            CheckboxListTile(
              value: _elegidos.contains(e.codigo),
              onChanged: (v) => setState(() => v == true ? _elegidos.add(e.codigo) : _elegidos.remove(e.codigo)),
              title: Text('${e.codigo} · ${e.titulo}'),
              subtitle: e.detalle == null ? null : Text(e.detalle!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          if (opciones.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('No hay contenedores ni artículos con etiqueta propia todavía.')),
          const SizedBox(height: 80),
        ]),
      ),
           );
  }
}
