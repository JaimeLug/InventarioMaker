import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventario_maker/acceso/sesion.dart';
import 'package:inventario_maker/datos/errores.dart';
import 'package:inventario_maker/modelos/articulo.dart';
import 'package:inventario_maker/modelos/catalogos.dart';
import 'package:inventario_maker/modelos/contenedores.dart';
import 'package:inventario_maker/modelos/movimientos.dart';
import 'package:inventario_maker/modelos/pendientes.dart';
import 'package:inventario_maker/modelos/solicitudes.dart';
import 'package:inventario_maker/util/etiquetas_pdf.dart';
import 'package:inventario_maker/util/texto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> renglon([Map<String, dynamic> cambios = const {}]) => {
      'id': 'a1', 'codigo': 'A-0012', 'ref_foto': 12, 'nombre': 'Destornilladores surtidos', 'marca_modelo': null,
      'categoria': 'HERRAMIENTAS', 'subcategoria': 'Herramienta manual', 'unidad': 'pieza', 'cantidad_texto': '~17',
      'cantidad_estimada': true, 'conteo_desconocido': false, 'estado_inventario': 'POR_CONTAR', 'estado_fisico': 'USADO',
      'estado_fisico_texto': 'Usados', 'etiquetado': 'CONTENEDOR', 'ubicacion_ruta': null, 'ubicacion_texto': 'Cajón azul',
      'num_resguardo': null, 'num_serie': null, 'observaciones': 'Surtidos, mango rojo', 'es_consumible': false,
      'minimo_reposicion': null, 'activo': true, 'existencia': 17, 'prestado': 2, 'fuera_servicio': 0, 'apartado': 0,
      'retenido': 0, 'disponible': 15, 'prestable': true, 'prestado_hasta': '2026-09-20T15:00:00+00:00',
      'pendientes_abiertos': 1, 'foto_principal_url': null,
      ...cambios,
    };

Sesion sesion({Rol rol = Rol.docente, NivelSesion nivel = NivelSesion.pin, bool vigente = true, bool activo = true}) =>
    Sesion(id: 'u', nombre: 'Laura Gómez', rol: rol, nivel: nivel, activo: activo, vigente: vigente, tienePin: true);

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('Textos', () {
    test('plurales de unidades', () {
      expect(conUnidad(1, 'pieza'), '1 pieza');
      expect(conUnidad(3, 'pieza'), '3 piezas');
      expect(conUnidad(2, 'sección'), '2 secciones');
      expect(conUnidad(4, 'rollo'), '4 rollos');
      expect(conUnidad(0, 'block'), '0 blocks');
      expect(conUnidad(2, 'carrete'), '2 carretes');
      expect(conUnidad(3, 'contenedor'), '3 contenedores');
    });

    test('la búsqueda ignora acentos y mayúsculas', () {
      expect(normalizar('Común ELÉCTRICA Piñón'), 'comun electrica pinon');
    });
  });

  group('Artículo', () {
    test('cantidad estimada se muestra con ~', () {
      final a = Articulo.desdeMapa(renglon());
      expect(a.cantidadMostrada, '~17 piezas');
      expect(a.disponibilidad, '~15 disponibles');
      expect(a.ubicacion, 'Cajón azul');
      expect(a.textoBusqueda, contains('mango rojo'));
    });

    test('"s/m" del Excel no se muestra como marca', () {
      expect(Articulo.desdeMapa(renglon({'marca_modelo': 's/m'})).marcaModelo, isNull);
      expect(Articulo.desdeMapa(renglon({'marca_modelo': 'S / M'})).marcaModelo, isNull);
      expect(Articulo.desdeMapa(renglon({'marca_modelo': 'Truper'})).marcaModelo, 'Truper');
    });

    test('sin conteo no se presta', () {
      final a = Articulo.desdeMapa(renglon({'conteo_desconocido': true, 'prestable': false, 'existencia': 0, 'disponible': 0}));
      expect(a.cantidadMostrada, 'Sin contar');
      expect(a.disponibilidad, 'Se presta hasta contarlo');
    });

    test('sin clasificar se avisa primero', () {
      final a = Articulo.desdeMapa(renglon({'categoria': 'SIN_CLASIFICAR', 'estado_inventario': 'SIN_CLASIFICAR', 'prestable': false}));
      expect(a.disponibilidad, 'Sin clasificar: no usar');
    });

    test('códigos sin Ñ se leen bien', () {
      expect(EstadoFisico.desde('DANADO')!.nombre, 'Dañado');
      expect(nombresMovimiento['DANO'], 'Daño');
    });
  });

  group('Gate de escritura: qué falta', () {
    test('sin sesión, o sesión vencida o desactivada, pide acceso', () {
      expect(evaluar(null, Requisito.docente), Falta.sesion);
      expect(evaluar(sesion(vigente: false), Requisito.docente), Falta.sesion);
      expect(evaluar(sesion(activo: false), Requisito.docente), Falta.sesion);
    });

    test('un docente con PIN agrega fotos', () {
      expect(evaluar(sesion(), Requisito.docente), Falta.nada);
    });

    test('a un docente no se le pide contraseña para algo que su cuenta no puede hacer', () {
      expect(evaluar(sesion(), Requisito.administracion), Falta.rol);
      expect(evaluar(sesion(nivel: NivelSesion.contrasena), Requisito.administracion), Falta.rol);
    });

    test('el responsable con PIN necesita su contraseña para el alta', () {
      expect(evaluar(sesion(rol: Rol.responsable), Requisito.administracion), Falta.contrasena);
      expect(evaluar(sesion(rol: Rol.responsable, nivel: NivelSesion.contrasena), Requisito.administracion), Falta.nada);
    });

    test('cambiar mi propio PIN pide contraseña a cualquier rol', () {
      expect(evaluar(sesion(), Requisito.propiaConfirmada), Falta.contrasena);
      expect(evaluar(sesion(nivel: NivelSesion.contrasena), Requisito.propiaConfirmada), Falta.nada);
      expect(Requisito.propiaConfirmada.confirmar, isTrue);
    });
  });

  group('Errores', () {
    test('la base pide confirmar contraseña', () {
      final e = traducir(const PostgrestException(message: 'Confirma tu contraseña para continuar.', code: 'PT403', details: 'CONFIRMAR_CONTRASENA'));
      expect(e.detalle, 'CONFIRMAR_CONTRASENA');
      expect(e.pideAcceso, isFalse);
    });

    test('sesión vencida pide acceso', () {
      expect(traducir(const PostgrestException(message: 'Tu sesión terminó.', code: 'PT401', details: 'SESION_VENCIDA')).pideAcceso, isTrue);
    });

    test('sin permiso para la función también pide acceso', () {
      expect(traducir(const PostgrestException(message: 'permission denied for function articulo_crear', code: '42501')).pideAcceso, isTrue);
    });

    test('credenciales incorrectas en español', () {
      expect(traducir(const AuthException('Invalid login credentials', code: 'invalid_credentials')).mensaje, 'Correo o contraseña incorrectos.');
    });
  });
  group('Movimientos (Fase 3)', () {
    test('un reporte por revisar se lee con fotos y comentarios', () {
      final i = Incidencia.desdeMapa({
        'id': 'i1', 'tipo': 'DANO', 'articulo_id': 'a1', 'codigo': 'A-0079', 'nombre': 'Cautín', 'unidad': 'pieza',
        'cantidad': 1, 'en_taller': true, 'nota': 'Cable pelado junto al mango', 'sin_foto_justificacion': null,
        'reportada_por': 'Laura Gómez', 'reportada_en': '2026-09-18T15:00:00+00:00', 'a_cargo': 'Juan Pérez (Alumno, 5°B)',
        'fotos': ['incidencias/i1/1.jpg'],
        'comentarios': [{'autor': 'Jaime Lugo', 'texto': '¿Desde cuándo?', 'en': '2026-09-18T16:00:00+00:00'}],
      });
      expect(i.nombreTipo, 'Daño');
      expect(i.nombreEstado, 'En revisión');
      expect(i.fotos, ['incidencias/i1/1.jpg']);
      expect(i.comentarios.single.autor, 'Jaime Lugo');
    });

    test('un préstamo de "mis préstamos" sabe si está a mi nombre', () {
      final p = PrestamoListado.desdeMapa({
        'prestamo_id': 'p1', 'articulo_id': 'a1', 'codigo': 'A-0101', 'nombre': 'Impresora', 'unidad': 'pieza',
        'pendiente': 1, 'vence_en': '2026-09-18T21:00:00+00:00', 'vencido': false, 'a_mi_nombre': false,
        'a_cargo': 'Juan Pérez (Alumno, 5°B)', 'grupo': 'g1',
      });
      expect((p.aMiNombre, p.extensiones, p.aCargo), (false, 0, 'Juan Pérez (Alumno, 5°B)'));
    });

    test('la extensión de préstamo tiene nombre en el historial', () {
      expect(nombresMovimiento['EXTENSION'], 'Extensión de préstamo');
      expect(motivosAjuste['NO_SE_ENCONTRO'], 'No se encontró');
    });
  });

  group('Solicitudes (Fase 3b)', () {
    Map<String, dynamic> publica([Map<String, dynamic> cambios = const {}]) => {
          'folio': 'LM-0057', 'estado': 'ENTREGADO', 'confirmada': true, 'enlace_de_correo': false,
          'creada_en': '2026-09-16T14:00:00+00:00', 'motivo': 'Proyecto de clase: robot', 'fecha_devolucion': '2026-09-23T21:00:00+00:00',
          'codigo_aceptado': false, 'correo': 'j***@prepasoficiales.net', 'autorizo': 'Jaime Lugo',
          'solicitante': {'nombre': 'Juan Pérez Chan', 'matricula': '23-0456', 'grupo': '5°B', 'tipo': 'ALUMNO'},
          'lineas': [
            {'articulo_id': 'a1', 'codigo': 'A-0101', 'nombre': 'Multímetro', 'unidad': 'pieza', 'cantidad': 3, 'aprobada': 2, 'pendiente': 1},
            {'articulo_id': 'a2', 'codigo': 'A-0102', 'nombre': 'Cautín', 'unidad': 'pieza', 'cantidad': 1, 'aprobada': null, 'pendiente': 1},
          ],
          ...cambios,
        };

    test('el comprobante cuenta lo aprobado y lo que falta devolver', () {
      final s = SolicitudPublica.desdeMapa(publica());
      expect((s.estado, s.estado.conMaterial, s.estado.abierta), (EstadoSolicitud.entregado, true, false));
      expect((s.piezasEntregadas, s.piezasPendientes), (3, 2));
      expect(s.matricula, '23-0456');
    });

    test('antes de confirmar solo llegan las iniciales', () {
      final s = SolicitudPublica.desdeMapa(publica({'estado': 'PENDIENTE', 'confirmada': false, 'solicitante': {'nombre': 'J. P. C.', 'tipo': 'ALUMNO'}}));
      expect((s.nombre, s.matricula, s.estado.nombre), ('J. P. C.', null, 'En revisión'));
    });

    test('el código se muestra solo mientras está vigente', () {
      final futuro = DateTime.now().add(const Duration(minutes: 30)).toUtc().toIso8601String();
      final pasado = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      expect(CodigoEntrega.desdeMapa({'estado': 'VIGENTE', 'expira_en': futuro, 'codigo': '123456'}).vigente, isTrue);
      expect(CodigoEntrega.desdeMapa({'estado': 'VIGENTE', 'expira_en': pasado, 'codigo': '123456'}).vigente, isFalse);
      final usado = CodigoEntrega.desdeMapa({'estado': 'USADO', 'expira_en': futuro, 'usado_en': pasado});
      expect((usado.aceptado, usado.nombreEstado), (true, 'Usado'));
      expect(CodigoEntrega.desdeMapa({'estado': 'USADO', 'expira_en': futuro, 'entrega_anulada_en': pasado}).aceptado, isFalse);
    });

    test('historial de la persona en una línea', () {
      FichaSolicitante ficha(int n, int r) => FichaSolicitante.desdeMapa({
            'id': 's', 'nombre': 'Juan', 'tipo': 'ALUMNO', 'matricula': '1', 'prestamos_anteriores': n, 'con_retraso': r,
          });
      expect(ficha(0, 0).historial, 'Primer préstamo');
      expect(ficha(1, 0).historial, '1 préstamo anterior, todos a tiempo');
      expect(ficha(4, 1).historial, '4 préstamos anteriores, 1 con retraso');
    });

    test('el carrito se guarda y se lee igual', () {
      final l = LineaCarrito(articuloId: 'a1', codigo: 'A-0101', nombre: 'Multímetro', unidad: 'pieza', cantidad: 2);
      final copia = LineaCarrito.desdeMapa(l.aMapa());
      expect((copia.articuloId, copia.cantidad, copia.foto), ('a1', 2, null));
    });
  });

  group('Contenedores y etiquetas (Fase 4a)', () {
    Contenedor c(String id, String nombre, {String? padre, String? categoria}) => Contenedor.desdeMapa({
          'id': id, 'codigo': 'C-$id', 'nombre': nombre, 'tipo': 'CAJON', 'padre_id': padre, 'categoria_exclusiva': categoria,
          'activo': true, 'ruta': nombre, 'articulos': 0, 'subcontenedores': 0,
        });

    test('el QR se entiende como dirección, código suelto o escrito a mano', () {
      expect(codigoDeEscaneo('https://inventario-maker.pages.dev/q/C-0012'), 'C-0012');
      expect(codigoDeEscaneo('http://localhost:8123/q/a-0101'), 'A-0101');
      expect(codigoDeEscaneo(' c-12 '), 'C-0012');
      expect(codigoDeEscaneo('A101'), 'A-0101');
      expect(codigoDeEscaneo('https://www.google.com'), isNull);
      expect(codigoDeEscaneo('LM-0057'), isNull);
    });

    test('el árbol pone a cada hijo después de su padre', () {
      final arbol = comoArbol([c('3', 'Bolsa', padre: '2'), c('2', 'Cajón B', padre: '1'), c('1', 'Gabinete'), c('4', 'Anaquel')]);
      expect([for (final (x, nivel) in arbol) '${x.nombre}:$nivel'], ['Anaquel:0', 'Gabinete:0', 'Cajón B:1', 'Bolsa:2']);
    });

    test('VEX y FTC solo en su contenedor exclusivo; mixto para lo demás', () {
      final mixto = c('1', 'Cajón general');
      final vex = c('2', 'Caja VEX', categoria: 'VEX');
      expect((mixto.acepta(Categoria.herramientas), mixto.acepta(Categoria.vex)), (true, false));
      expect((vex.acepta(Categoria.vex), vex.acepta(Categoria.ftc), vex.acepta(Categoria.comun)), (true, false, false));
      expect(vex.nombreCategoria, 'Solo VEX');
    });

    test('la hoja de etiquetas lleva la dirección y reparte en hojas', () async {
      expect(direccionDeCodigo('https://inventario-maker.pages.dev/', 'C-0012'), 'https://inventario-maker.pages.dev/q/C-0012');
      final etiquetas = [for (var i = 1; i <= 31; i++) EtiquetaDatos(codigo: 'C-${i.toString().padLeft(4, '0')}', titulo: 'Cajón › $i', detalle: 'Gabinete 2 › Cajón')];
      final pdf = await generarEtiquetas(etiquetas, FormatoEtiqueta.chica, 'https://x.pages.dev');
      final texto = String.fromCharCodes(pdf);
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(texto).length, 2);   // 30 por hoja: 31 ocupan 2
      final empezada = await generarEtiquetas(etiquetas.take(2).toList(), FormatoEtiqueta.chica, 'https://x.pages.dev', empezarEn: 30);
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(empezada)).length, 2);
    });
  });

  group('Pendientes, desglose e inventario (Fase 4b)', () {
    test('el faltante de un renglón del desglose', () {
      expect(LineaDesglose(descripcion: 'Servo', esperada: 8, encontrada: 5).faltante, 3);
      expect(LineaDesglose(descripcion: 'Servo', esperada: 8, encontrada: 9).faltante, 0);
      expect(LineaDesglose(descripcion: 'Tornillería', encontrada: 1).faltante, 0);      // "varios": no hay faltante
      expect(LineaDesglose(descripcion: 'Servo', esperada: 2).faltante, 2);
      final m = LineaDesglose(descripcion: 'Motor', encontrada: 1, esConsumible: true).aMapa();
      expect((m['descripcion'], m['encontrada'], m['es_consumible']), ('Motor', 1, true));
    });

    test('qué diferencias faltan por decidir antes de cerrar', () {
      DiferenciaInventario d(Map<String, dynamic> x) => DiferenciaInventario.desdeMapa(
          {'articulo_id': 'a', 'codigo': 'A-1', 'nombre': 'x', 'contados': 1, 'diferencia': 0, 'conflicto': false, ...x});
      expect(d({}).pendiente, isFalse);                                  // coincide
      expect(d({'diferencia': -2}).pendiente, isTrue);
      expect(d({'diferencia': -2, 'decision': 'AJUSTE'}).pendiente, isFalse);
      expect(d({'conflicto': true, 'decision': 'AJUSTE'}).pendiente, isTrue);
      expect(d({'contados': 0, 'diferencia': null}).pendiente, isFalse);  // no contado: no bloquea el cierre
    });

    test('la diferencia de un conteo es contra lo que había al contar', () {
      final c = ConteoPorAplicar.desdeMapa({
        'id': 'c', 'articulo_id': 'a', 'codigo': 'A-1', 'nombre': 'Llaves', 'en_taller': 7, 'sistema': 8,
        'contado_por': 'Ruth', 'contado_en': '2026-09-17T15:00:00Z', 'mio': false,
      });
      expect(c.diferencia, -1);
    });
  });
}
