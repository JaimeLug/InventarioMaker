import 'package:intl/intl.dart';

/// Minúsculas y sin acentos, para buscar "desarmador" y encontrar "Desarmadór".
String normalizar(String texto) {
  const con = 'áàäâéèëêíìïîóòöôúùüûñ';
  const sin = 'aaaaeeeeiiiioooouuuun';
  final minusculas = texto.toLowerCase();
  final buffer = StringBuffer();
  for (final c in minusculas.split('')) {
    final i = con.indexOf(c);
    buffer.write(i >= 0 ? sin[i] : c);
  }
  return buffer.toString();
}

/// "1 pieza", "3 piezas", "2 secciones", "4 cajas".
String conUnidad(int cantidad, String unidad) => '$cantidad ${cantidad == 1 ? unidad : plural(unidad)}';

String plural(String palabra) {
  if (palabra.isEmpty) return palabra;
  if (palabra.endsWith('ón')) return '${palabra.substring(0, palabra.length - 2)}ones';
  if (RegExp(r'[aeiouáéó]$').hasMatch(palabra)) return '${palabra}s';
  if (palabra.endsWith('z')) return '${palabra.substring(0, palabra.length - 1)}ces';
  if (RegExp(r'[lrndjy]$').hasMatch(palabra)) return '${palabra}es';
  return '${palabra}s'; // palabras prestadas: "block" -> "blocks"
}

final _fecha = DateFormat("d 'de' MMM yyyy", 'es_MX');
final _fechaHora = DateFormat("d MMM yyyy, HH:mm", 'es_MX');
final _hora = DateFormat('HH:mm', 'es_MX');

String fecha(DateTime f) => _fecha.format(f.toLocal());
String fechaHora(DateTime f) => _fechaHora.format(f.toLocal());
String hora(DateTime f) => _hora.format(f.toLocal());
