import 'package:flutter/widgets.dart';

import '../../modelos/catalogos.dart';

/// La fuente de iconos (Lucide, licencia ISC) va empacada en assets/fuentes/lucide.ttf.
/// Antes venía del paquete lucide_icons_flutter, que además traía seis fuentes por grosor
/// que no usamos y pesaban 2.8 MB en la web y en el APK.
const _familia = 'Lucide';

/// Una sola familia de iconos en toda la app: Lucide, de contorno.
/// Tamaños: 16 en insignias, 20 en la interfaz, 24 en la barra inferior, 32+ en estados vacíos.
abstract final class Ico {
  // Navegación
  static const tablero = IconData(0xe1c1, fontFamily: _familia);
  static const inventario = IconData(0xe2d0, fontFamily: _familia);
  static const herramientas = IconData(0xe1b1, fontFamily: _familia);
  static const prestamos = IconData(0xe24a, fontFamily: _familia);
  static const solicitudes = IconData(0xe0f7, fontFamily: _familia);
  static const pendientes = IconData(0xe1d0, fontFamily: _familia);
  static const contenedores = IconData(0xe3e6, fontFamily: _familia);
  static const kits = IconData(0xe4fa, fontFamily: _familia);
  static const reportes = IconData(0xe2a3, fontFamily: _familia);
  static const adeudos = IconData(0xe468, fontFamily: _familia);
  static const cuentas = IconData(0xe1a4, fontFamily: _familia);
  static const ajustes = IconData(0xe154, fontFamily: _familia);
  static const bitacora = IconData(0xe1f5, fontFamily: _familia);
  static const menu = IconData(0xe115, fontFamily: _familia);
  static const mas = IconData(0xe0b7, fontFamily: _familia);
  static const diseno = IconData(0xe1dd, fontFamily: _familia);

  /// El hexágono de la marca en la barra lateral.
  static const marca = IconData(0xe0f3, fontFamily: _familia);

  // Acciones
  static const escanear = IconData(0xe258, fontFamily: _familia);
  static const prestar = IconData(0xe24a, fontFamily: _familia);
  static const devolver = IconData(0xe2a1, fontFamily: _familia);
  static const reportar = IconData(0xe0d1, fontFamily: _familia);
  static const contar = IconData(0xe1d0, fontFamily: _familia);
  static const editar = IconData(0xe1f9, fontFamily: _familia);
  static const nuevo = IconData(0xe13d, fontFamily: _familia);
  static const guardar = IconData(0xe226, fontFamily: _familia);
  static const baja = IconData(0xe18e, fontFamily: _familia);
  static const imprimir = IconData(0xe141, fontFamily: _familia);
  static const buscar = IconData(0xe151, fontFamily: _familia);
  static const filtros = IconData(0xe29a, fontFamily: _familia);
  static const descargar = IconData(0xe0b2, fontFamily: _familia);
  static const excel = IconData(0xe326, fontFamily: _familia);
  static const pdf = IconData(0xe0cc, fontFamily: _familia);
  static const foto = IconData(0xe064, fontFamily: _familia);
  static const qr = IconData(0xe1df, fontFamily: _familia);
  static const cerrar = IconData(0xe1b2, fontFamily: _familia);
  static const reintentar = IconData(0xe145, fontFamily: _familia);
  static const avanzar = IconData(0xe06f, fontFamily: _familia);
  static const regresar = IconData(0xe06e, fontFamily: _familia);

  // Estados y avisos
  static const ok = IconData(0xe226, fontFamily: _familia);
  static const aviso = IconData(0xe193, fontFamily: _familia);
  static const error = IconData(0xe084, fontFamily: _familia);
  static const info = IconData(0xe0f9, fontFamily: _familia);
  static const alerta = IconData(0xe077, fontFamily: _familia);
  static const reloj = IconData(0xe087, fontFamily: _familia);
  static const campana = IconData(0xe059, fontFamily: _familia);
  static const comentario = IconData(0xe117, fontFamily: _familia);
  static const verificado = IconData(0xe241, fontFamily: _familia);
  static const porVerificar = IconData(0xe0ba, fontFamily: _familia);
  static const noSePresta = IconData(0xe10b, fontFamily: _familia);
  static const sinFoto = IconData(0xe0f6, fontFamily: _familia);
  static const ubicacion = IconData(0xe111, fontFamily: _familia);
  static const persona = IconData(0xe19f, fontFamily: _familia);
  static const sinConexion = IconData(0xe08d, fontFamily: _familia);
  static const enLinea = IconData(0xe66e, fontFamily: _familia);
  static const porEnviar = IconData(0xe091, fontFamily: _familia);
  static const vacio = IconData(0xe2cc, fontFamily: _familia);
  static const sinResultados = IconData(0xe151, fontFamily: _familia);
  static const sinSenal = IconData(0xe1af, fontFamily: _familia);

  // Navegacion y objetos
  static const inicio = IconData(0xe0f5, fontFamily: _familia);
  static const arbol = IconData(0xe408, fontFamily: _familia);
  static const caja = IconData(0xe129, fontFamily: _familia);
  static const carpeta = IconData(0xe0d7, fontFamily: _familia);
  static const nuevaCarpeta = IconData(0xe0d9, fontFamily: _familia);
  static const subnivel = IconData(0xe0a2, fontFamily: _familia);
  static const mover = IconData(0xe334, fontFamily: _familia);
  static const inventarios = IconData(0xe086, fontFamily: _familia);
  static const lista = IconData(0xe106, fontFamily: _familia);
  static const cuadricula = IconData(0xe0ff, fontFamily: _familia);
  static const escuela = IconData(0xe234, fontFamily: _familia);
  static const maestro = IconData(0xe4ae, fontFamily: _familia);
  static const expediente = IconData(0xe09c, fontFamily: _familia);
  static const credencial = IconData(0xe617, fontFamily: _familia);
  static const acta = IconData(0xe5ac, fontFamily: _familia);
  static const oficio = IconData(0xe0cc, fontFamily: _familia);
  static const nota = IconData(0xe303, fontFamily: _familia);

  // Acciones
  static const agregarFoto = IconData(0xe1f7, fontFamily: _familia);
  static const galeria = IconData(0xe5c4, fontFamily: _familia);
  static const enlazar = IconData(0xe102, fontFamily: _familia);
  static const articuloNuevo = IconData(0xe268, fontFamily: _familia);
  static const agregarALista = IconData(0xe23f, fontFamily: _familia);
  static const apartar = IconData(0xe23d, fontFamily: _familia);
  static const quitar = IconData(0xe18d, fontFamily: _familia);
  static const quitarUno = IconData(0xe11c, fontFamily: _familia);
  static const quitarCirculo = IconData(0xe07e, fontFamily: _familia);
  static const desactivar = IconData(0xe051, fontFamily: _familia);
  static const reactivar = IconData(0xe2cd, fontFamily: _familia);
  static const desarchivar = IconData(0xe2cd, fontFamily: _familia);
  static const reparar = IconData(0xe0ec, fontFamily: _familia);
  static const revisar = IconData(0xe219, fontFamily: _familia);
  static const aprobar = IconData(0xe1a0, fontFamily: _familia);
  static const aprobado = IconData(0xe18a, fontFamily: _familia);
  static const entrega = IconData(0xe5c0, fontFamily: _familia);
  static const enviar = IconData(0xe152, fontFamily: _familia);
  static const entrar = IconData(0xe10d, fontFamily: _familia);
  static const salir = IconData(0xe10e, fontFamily: _familia);
  static const listo = IconData(0xe06c, fontFamily: _familia);
  static const todoListo = IconData(0xe38e, fontFamily: _familia);
  static const reiniciar = IconData(0xe148, fontFamily: _familia);
  static const ver = IconData(0xe0ba, fontFamily: _familia);
  static const ocultar = IconData(0xe0bb, fontFamily: _familia);
  static const avanzarFlecha = IconData(0xe049, fontFamily: _familia);
  static const plegar = IconData(0xe072, fontFamily: _familia);
  static const desplegar = IconData(0xe073, fontFamily: _familia);
  static const linterna = IconData(0xe0d3, fontFamily: _familia);
  static const enEsteAparato = IconData(0xe163, fontFamily: _familia);
  static const agregarPersona = IconData(0xe1a2, fontFamily: _familia);
  static const buscarPersona = IconData(0xe579, fontFamily: _familia);
  static const cambiarFecha = IconData(0xe5ed, fontFamily: _familia);

  // Estados, conteos y avisos
  static const conteo = IconData(0xe0ef, fontFamily: _familia);
  static const pin = IconData(0xe168, fontFamily: _familia);
  static const contrasena = IconData(0xe4a3, fontFamily: _familia);
  static const conContrasena = IconData(0xe1ff, fontFamily: _familia);
  static const categoria = IconData(0xe17f, fontFamily: _familia);
  static const energia = IconData(0xe1b4, fontFamily: _familia);
  static const alarma = IconData(0xe03a, fontFamily: _familia);
  static const fecha = IconData(0xe063, fontFamily: _familia);
  static const periodo = IconData(0xe2bd, fontFamily: _familia);
  static const vence = IconData(0xe2be, fontFamily: _familia);
  static const enEspera = IconData(0xe296, fontFamily: _familia);
  static const enCurso = IconData(0xe4c3, fontFamily: _familia);
  static const sinMarcar = IconData(0xe076, fontFamily: _familia);
  static const bloqueado = IconData(0xe051, fontFamily: _familia);
  static const abierto = IconData(0xe10c, fontFamily: _familia);
  static const perdida = IconData(0xe26a, fontFamily: _familia);
  static const noDisponible = IconData(0xe07e, fontFamily: _familia);
  static const imagenRota = IconData(0xe1c0, fontFamily: _familia);
  static const sinUbicacion = IconData(0xe2a6, fontFamily: _familia);
  static const personaInactiva = IconData(0xe1a3, fontFamily: _familia);
  static const sinCoincidencias = IconData(0xe4ad, fontFamily: _familia);
  static const correo = IconData(0xe10f, fontFamily: _familia);
  static const correoLeido = IconData(0xe361, fontFamily: _familia);
  static const correoSinLeer = IconData(0xe363, fontFamily: _familia);
  static const avisoActivo = IconData(0xe224, fontFamily: _familia);
  static const problemaSincronia = IconData(0xe498, fontFamily: _familia);
  static const carrito = IconData(0xe4ea, fontFamily: _familia);
  static const historial = IconData(0xe1f5, fontFamily: _familia);

  /// El icono de cada categoría (el nombre siempre se escribe junto).
  static IconData deCategoria(Categoria c) => switch (c) {
        Categoria.vex => const IconData(0xe0f3, fontFamily: _familia),
        Categoria.ftc => const IconData(0xe30b, fontFamily: _familia),
        Categoria.herramientas => const IconData(0xe1b1, fontFamily: _familia),
        Categoria.herramientasElectricas => const IconData(0xe45c, fontFamily: _familia),
        Categoria.consumibles => const IconData(0xe529, fontFamily: _familia),
        Categoria.comun => const IconData(0xe129, fontFamily: _familia),
        Categoria.sinClasificar => const IconData(0xe082, fontFamily: _familia),
      };

  /// Subcategorías (estructura, movimiento, sensores…): icono neutro, sin color propio.
  static IconData deSubcategoria(String? sub) => switch ((sub ?? '').toLowerCase()) {
        final s when s.contains('estructura') => const IconData(0xe581, fontFamily: _familia),
        final s when s.contains('movimiento') => const IconData(0xe494, fontFamily: _familia),
        final s when s.contains('electrón') || s.contains('electron') => const IconData(0xe0a9, fontFamily: _familia),
        final s when s.contains('sensor') => const IconData(0xe497, fontFamily: _familia),
        final s when s.contains('control') => const IconData(0xe0df, fontFamily: _familia),
        final s when s.contains('tornill') => const IconData(0xe0ef, fontFamily: _familia),
        final s when s.contains('energ') || s.contains('bater') => const IconData(0xe053, fontFamily: _familia),
        final s when s.contains('medici') => const IconData(0xe1bf, fontFamily: _familia),
        final s when s.contains('soldad') => const IconData(0xe0d2, fontFamily: _familia),
        final s when s.contains('impresi') => const IconData(0xe141, fontFamily: _familia),
        final s when s.contains('corte') => const IconData(0xe14e, fontFamily: _familia),
        final s when s.contains('segurid') => const IconData(0xe1ff, fontFamily: _familia),
        final s when s.contains('fabricaci') => const IconData(0xe3b4, fontFamily: _familia),
        final s when s.contains('kit') => const IconData(0xe2d0, fontFamily: _familia),
        final s when s.contains('manual') || s.contains('mano') => const IconData(0xe1b1, fontFamily: _familia),
        _ => const IconData(0xe17f, fontFamily: _familia),
      };

  /// Tipo de movimiento en historial y bitácora.
  static IconData deMovimiento(String tipo) => switch (tipo) {
        'PRESTAMO' => const IconData(0xe24a, fontFamily: _familia),
        'DEVOLUCION' => const IconData(0xe2a1, fontFamily: _familia),
        'CONSUMO' => const IconData(0xe529, fontFamily: _familia),
        'PERDIDA' => const IconData(0xe084, fontFamily: _familia),
        'DANO' || 'DAÑO' => const IconData(0xe193, fontFamily: _familia),
        'REPARACION' => const IconData(0xe1b1, fontFamily: _familia),
        'ALTA' => const IconData(0xe13d, fontFamily: _familia),
        'BAJA' => const IconData(0xe18e, fontFamily: _familia),
        'AJUSTE_CONTEO' => const IconData(0xe219, fontFamily: _familia),
        'EXTENSION' => const IconData(0xe304, fontFamily: _familia),
        _ => const IconData(0xe1f5, fontFamily: _familia),
      };
}
