import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../datos/errores.dart';
import '../../datos/repositorio.dart';

/// Destino de los QR: /q/A-0101 abre la ficha. Los contenedores (C-xxxx) llegan en la Fase 4.
class CodigoPantalla extends ConsumerStatefulWidget {
  const CodigoPantalla({super.key, required this.codigo});

  final String codigo;

  @override
  ConsumerState<CodigoPantalla> createState() => _CodigoPantallaState();
}

class _CodigoPantallaState extends ConsumerState<CodigoPantalla> {
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _resolver();
  }

  Future<void> _resolver() async {
    final codigo = widget.codigo.toUpperCase();
    if (codigo.startsWith('C-')) {
      setState(() => _mensaje = 'Los contenedores se habilitan en la Fase 4.');
      return;
    }
    try {
      final id = await ref.read(repositorioProvider).idPorCodigo(codigo);
      if (!mounted) return;
      if (id == null) {
        setState(() => _mensaje = 'La etiqueta $codigo no está registrada.');
      } else {
        context.go('/articulo/$id');
      }
    } on Object catch (e) {
      if (mounted) setState(() => _mensaje = traducir(e).mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.codigo)),
      body: Center(
        child: _mensaje == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_mensaje!),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => context.go('/'), child: const Text('Ir al inventario')),
              ]),
      ),
    );
  }
}
