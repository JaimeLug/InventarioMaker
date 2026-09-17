import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_maker/datos/errores.dart';
import 'package:inventario_maker/sin_conexion/cola.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('un comando se guarda y se lee igual (sobrevive a cerrar la app)', () {
    final c = Comando(
      id: 'c1',
      tipo: 'DEVOLUCION',
      datos: {
        'lineas': [
          {'prestamo_id': 'p1', 'regresan': 1, 'danadas': 1, 'fotos_dano': [{'ruta': 'incidencias/i1/1.jpg'}]},
        ],
      },
      capturado: DateTime.utc(2026, 9, 17, 16, 42),
      usuarioId: 'u1',
      usuarioNombre: 'Laura Gómez',
      resumen: 'Devolución: Multímetro ×1 (1 con daño)',
      articuloIds: const ['a1'],
      fotos: [FotoEnCola(archivo: 'c1_0.jpg', bucket: 'privado', ruta: 'incidencias/i1/1.jpg')],
    );
    final leido = Comando.desdeMapa(c.aMapa());
    expect(leido.aMapa(), c.aMapa());
    expect(leido.capturado, c.capturado);
    expect(leido.fotos.single.subida, isFalse);
  });

  test('qué errores cuentan como falta de señal', () {
    expect(esFaltaDeConexion(const SocketException('Failed host lookup: eirouznbikpvnuhdmbnm.supabase.co')), isTrue);
    expect(esFaltaDeConexion(TimeoutException('sin respuesta')), isTrue);
    expect(esFaltaDeConexion(traducir(const SocketException('x'))), isTrue);
    expect(esFaltaDeConexion(const PostgrestException(message: 'Ese préstamo ya estaba cerrado.', code: 'P0001')), isFalse);
    expect(esFaltaDeConexion(const PostgrestException(message: 'Identifícate', code: 'PT401')), isFalse);
  });
}
