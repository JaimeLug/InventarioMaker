"""Interpretación de "Cantidad contada" y "Estado" del Excel (sin base de datos)."""
import pytest

from inventario_excel import interpretar_cantidad, interpretar_estado

# (texto, nombre del artículo, valor, unidad, estimada, desconocida)
CASOS = [
    ("3", "Multímetro", 3, "pieza", False, False),
    ("4", "Cajas REV adicionales apiladas", 4, "caja", False, False),
    ("4 cajas", "Kit base VEX", 4, "caja", False, False),
    ("3 cajas", "Kit VEX V5", 3, "caja", False, False),
    ("1 (mínimo)", "Batería VEX V5", 1, "pieza", True, False),
    ("1 caja", "Kit UltraPlanetary", 1, "caja", False, False),
    ("1 bolsa", "Tuercas Nylock", 1, "bolsa", False, False),
    ("~15", "Piezas impresas en 3D", 15, "pieza", True, False),
    ("varias", "Bandas dentadas", None, "pieza", True, True),
    ("bolsa, ~10", "Servos REV", 10, "pieza", True, False),
    ("1 contenedor lleno", "Perfil de aluminio", None, "pieza", True, True),
    ("~20 bolsas", "Herrajes REV surtidos", 20, "bolsa", True, False),
    ("1 bolsa (4 pz)", "Flat Mounting Bracket", 1, "bolsa", False, False),
    ("2 estuches", "Juego de brocas", 2, "estuche", False, False),
    ("1 (5 pzas)", "Juego de pinzas en estuche", 1, "juego", False, False),
    ("4 juegos", "Juegos de llaves allen", 4, "juego", False, False),
    ("1 carrete", "Soldadura", 1, "carrete", False, False),
    ("2 rollos", "Cinta doble cara", 2, "rollo", False, False),
    ("1 empaque", "Lija de tambor", 1, "empaque", False, False),
    ("1 canasta", "Piezas de MDF", 1, "canasta", False, False),
    ("2 paquetes", "Accesorios Dremel", 2, "paquete", False, False),
    ("1 (5 MH + 5 FC)", "Pack de conectores XT30", 1, "paquete", False, False),
    ("1 bolsa grande", "Tornillos y tuercas", 1, "bolsa", False, False),
    ("1 block", "Etiquetas adheribles", 1, "block", False, False),
    ("varios", "Stickers", None, "pieza", True, True),
    ("2 secciones", "Panel perforado", 2, "sección", False, False),
    ("2 o más", "Mesa de trabajo", 2, "pieza", True, False),
    ("", "Algo", None, "pieza", True, True),
    (None, "Algo", None, "pieza", True, True),
]


@pytest.mark.parametrize("texto,nombre,valor,unidad,estimada,desconocida", CASOS)
def test_interpretar_cantidad(texto, nombre, valor, unidad, estimada, desconocida):
    c = interpretar_cantidad(texto, nombre)
    assert (c.valor, c.unidad, c.estimada, c.desconocida) == (valor, unidad, estimada, desconocida)


@pytest.mark.parametrize("texto,esperado", [
    ("VACÍO", "VACIO"),
    ("Usados, mayoría vacíos", "USADO"),
    ("Usadas, INCOMPLETAS", "INCOMPLETO"),
    ("Selladas / emplayadas", "SIN_ABRIR"),
    ("NUEVA, en caja sellada", "SIN_ABRIR"),
    ("Nuevo, en caja", "NUEVO"),
    ("Usadas, con óxido", "USADO"),
    ("Operativa, sucia de filamento", "USADO"),
    ("Caja abierta", "USADO"),
    ("Etiquetada en contenedor naranja", None),
    (None, None),
])
def test_interpretar_estado(texto, esperado):
    assert interpretar_estado(texto) == esperado
