import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// Textos de los componentes de Flutter (calendario, copiar y pegar, lectores de pantalla) solo en
/// español de México. Los delegados de `GlobalMaterialLocalizations` traen unos 80 idiomas y la web
/// tenía que descargarlos todos. Necesita `initializeDateFormatting('es_MX')` antes de arrancar.
const delegadosIdioma = <LocalizationsDelegate<Object?>>[_Material(), _Cupertino(), _Widgets()];

const _idioma = 'es_MX';

bool _esEspanol(Locale locale) => locale.languageCode == 'es';

class _Material extends LocalizationsDelegate<MaterialLocalizations> {
  const _Material();

  @override
  bool isSupported(Locale locale) => _esEspanol(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture(MaterialLocalizationEsMx(
        fullYearFormat: DateFormat.y(_idioma),
        compactDateFormat: DateFormat.yMd(_idioma),
        shortDateFormat: DateFormat.yMMMd(_idioma),
        mediumDateFormat: DateFormat.MMMEd(_idioma),
        longDateFormat: DateFormat.yMMMMEEEEd(_idioma),
        yearMonthFormat: DateFormat.yMMMM(_idioma),
        shortMonthDayFormat: DateFormat.MMMd(_idioma),
        decimalFormat: NumberFormat.decimalPattern(_idioma),
        twoDigitZeroPaddedFormat: NumberFormat('00', _idioma),
      ));

  @override
  bool shouldReload(_Material old) => false;
}

class _Cupertino extends LocalizationsDelegate<CupertinoLocalizations> {
  const _Cupertino();

  @override
  bool isSupported(Locale locale) => _esEspanol(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) => SynchronousFuture(CupertinoLocalizationEsMx(
        fullYearFormat: DateFormat.y(_idioma),
        dayFormat: DateFormat.d(_idioma),
        weekdayFormat: DateFormat.E(_idioma),
        mediumDateFormat: DateFormat.MMMEd(_idioma),
        singleDigitHourFormat: DateFormat('HH', _idioma),
        singleDigitMinuteFormat: DateFormat.m(_idioma),
        doubleDigitMinuteFormat: DateFormat('mm', _idioma),
        singleDigitSecondFormat: DateFormat.s(_idioma),
        decimalFormat: NumberFormat.decimalPattern(_idioma),
      ));

  @override
  bool shouldReload(_Cupertino old) => false;
}

class _Widgets extends LocalizationsDelegate<WidgetsLocalizations> {
  const _Widgets();

  @override
  bool isSupported(Locale locale) => _esEspanol(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) => SynchronousFuture(const WidgetsLocalizationEsMx());

  @override
  bool shouldReload(_Widgets old) => false;
}
