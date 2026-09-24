import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventario_maker/ui/idioma.dart';

const _mx = Locale('es', 'MX');

Future<BuildContext> _app(WidgetTester tester, List<LocalizationsDelegate<Object?>> delegados) async {
  late BuildContext contexto;
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    locale: _mx,
    supportedLocales: const [_mx],
    localizationsDelegates: delegados,
    home: Builder(builder: (context) {
      contexto = context;
      return const Scaffold();
    }),
  ));
  return contexto;
}

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  testWidgets('solo español de México, igual que con los delegados completos de Flutter', (tester) async {
    final dia = DateTime(2026, 9, 24, 7, 5);
    List<Object?> muestra(BuildContext c) {
      final m = MaterialLocalizations.of(c);
      final k = CupertinoLocalizations.of(c);
      return [
        m.cancelButtonLabel, m.okButtonLabel, m.copyButtonLabel, m.pasteButtonLabel, m.searchFieldLabel,
        m.formatMediumDate(dia), m.formatFullDate(dia), m.formatCompactDate(dia), m.formatShortDate(dia),
        m.formatMonthYear(dia), m.formatShortMonthDay(dia), m.formatYear(dia), m.formatDecimal(1234567),
        m.formatTimeOfDay(const TimeOfDay(hour: 7, minute: 5)), m.firstDayOfWeekIndex, m.narrowWeekdays,
        k.datePickerMediumDate(dia), k.datePickerHour(7), k.datePickerMinute(5), k.cutButtonLabel,
        WidgetsLocalizations.of(c).textDirection, WidgetsLocalizations.of(c).reorderItemUp,
      ];
    }

    final completos = muestra(await _app(tester, GlobalMaterialLocalizations.delegates));
    final contexto = await _app(tester, delegadosIdioma);
    expect(muestra(contexto), completos);
    expect(MaterialLocalizations.of(contexto).cancelButtonLabel, 'Cancelar');

    showDatePicker(context: contexto, initialDate: dia, firstDate: DateTime(2026), lastDate: DateTime(2027));
    await tester.pumpAndSettle();
    expect(find.text('septiembre de 2026'), findsOneWidget);
  });
}
