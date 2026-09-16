import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventario_maker/acceso/sesion.dart';
import 'package:inventario_maker/datos/errores.dart';
import 'package:inventario_maker/modelos/articulo.dart';
import 'package:inventario_maker/modelos/catalogos.dart';
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
}
