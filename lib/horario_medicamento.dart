import 'package:flutter/material.dart';

const List<String> diasMedicamento = [
  'L',
  'M',
  'Mi',
  'J',
  'V',
  'S',
  'D',
];

class TomaProgramada {
  final Map<String, dynamic> medicamento;
  final DateTime fecha;

  const TomaProgramada({
    required this.medicamento,
    required this.fecha,
  });
}

int minutosDeHora(String hora) {
  final partes = hora.split(':');

  if (partes.length != 2) return -1;

  final horas = int.tryParse(partes[0]);
  final minutos = int.tryParse(partes[1]);

  if (horas == null ||
      minutos == null ||
      horas < 0 ||
      horas > 23 ||
      minutos < 0 ||
      minutos > 59) {
    return -1;
  }

  return (horas * 60) + minutos;
}

String hora24DesdeMinutos(int minutosTotales) {
  final normalizados = ((minutosTotales % 1440) + 1440) % 1440;
  final horas = normalizados ~/ 60;
  final minutos = normalizados % 60;

  return '${horas.toString().padLeft(2, '0')}:'
      '${minutos.toString().padLeft(2, '0')}';
}

String formatearHora(BuildContext context, String hora) {
  final minutos = minutosDeHora(hora);
  if (minutos < 0) return hora;

  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60),
  );
}

String formatearTomaProgramada(
  BuildContext context,
  int minutosDesdeDiaBase,
) {
  final hora = formatearHora(
    context,
    hora24DesdeMinutos(minutosDesdeDiaBase),
  );
  final desplazamientoDia = minutosDesdeDiaBase ~/ 1440;

  if (desplazamientoDia <= 0) return hora;
  if (desplazamientoDia == 1) return '$hora · día siguiente';
  return '$hora · +$desplazamientoDia días';
}

int _intervaloValido(dynamic valor) {
  final intervalo = valor is num
      ? valor.toInt()
      : int.tryParse(valor?.toString() ?? '');

  if (intervalo == 4 ||
      intervalo == 6 ||
      intervalo == 8 ||
      intervalo == 12 ||
      intervalo == 24) {
    return intervalo!;
  }

  return 0;
}

List<int> minutosProgramados(Map<String, dynamic> medicamento) {
  final tipo = medicamento['tipoHorario']?.toString() ?? 'fijo';
  final horaBase = medicamento['horaInicio']?.toString() ??
      medicamento['hora']?.toString() ??
      '08:00';
  final inicio = minutosDeHora(horaBase);

  if (inicio < 0) return [];

  if (tipo != 'intervalo') {
    return [inicio];
  }

  final intervaloHoras = _intervaloValido(
    medicamento['intervaloHoras'],
  );

  if (intervaloHoras == 0) {
    return [inicio];
  }

  final intervaloMinutos = intervaloHoras * 60;
  final incluirMadrugada = medicamento['incluirMadrugada'] != false;
  final resultado = <int>[];

  if (incluirMadrugada) {
    for (var transcurridos = 0;
        transcurridos < 1440;
        transcurridos += intervaloMinutos) {
      // Los valores mayores a 1439 conservan que la toma pertenece al dia
      // siguiente al dia seleccionado para iniciar el ciclo.
      resultado.add(inicio + transcurridos);
    }
  } else {
    final fin = minutosDeHora(
      medicamento['horaFin']?.toString() ?? '22:00',
    );

    if (fin < inicio) return [inicio];

    for (var minuto = inicio;
        minuto <= fin;
        minuto += intervaloMinutos) {
      resultado.add(minuto);
    }
  }

  return resultado;
}

List<String> obtenerDiasMedicamento(dynamic valor) {
  final resultado = <String>[];

  if (valor is Iterable) {
    resultado.addAll(valor.map((dia) => dia.toString()));
  } else if (valor is Map) {
    resultado.addAll(
      valor.values
          .where((dia) => dia != null)
          .map((dia) => dia.toString()),
    );
  }

  resultado.removeWhere((dia) => !diasMedicamento.contains(dia));
  resultado.sort(
    (a, b) => diasMedicamento.indexOf(a).compareTo(
          diasMedicamento.indexOf(b),
        ),
  );

  return resultado;
}

bool medicamentoProgramadoEnFecha(
  Map<String, dynamic> medicamento,
  DateTime fecha,
) {
  final dias = obtenerDiasMedicamento(medicamento['dias']);
  if (dias.isEmpty) return false;

  final indice = fecha.weekday == DateTime.sunday ? 6 : fecha.weekday - 1;
  return dias.contains(diasMedicamento[indice]);
}

List<TomaProgramada> buscarProximasTomas(
  List<Map<String, dynamic>> medicamentos, {
  DateTime? desde,
}) {
  final ahora = desde ?? DateTime.now();
  final minutoActual = DateTime(
    ahora.year,
    ahora.month,
    ahora.day,
    ahora.hour,
    ahora.minute,
  );
  DateTime? mejorFecha;
  final proximas = <TomaProgramada>[];

  // Una toma de madrugada de hoy puede provenir de un ciclo que inicio ayer.
  for (var desplazamientoBase = -1;
      desplazamientoBase <= 7;
      desplazamientoBase++) {
    final diaBase = DateTime(
      ahora.year,
      ahora.month,
      ahora.day + desplazamientoBase,
    );

    for (final medicamento in medicamentos) {
      if (medicamento['activo'] == false ||
          !medicamentoProgramadoEnFecha(medicamento, diaBase)) {
        continue;
      }

      for (final minutoCiclo in minutosProgramados(medicamento)) {
        final candidata = DateTime(
          diaBase.year,
          diaBase.month,
          diaBase.day,
        ).add(Duration(minutes: minutoCiclo));

        if (candidata.isBefore(minutoActual)) continue;

        if (mejorFecha == null || candidata.isBefore(mejorFecha)) {
          mejorFecha = candidata;
          proximas
            ..clear()
            ..add(TomaProgramada(
              medicamento: medicamento,
              fecha: candidata,
            ));
          continue;
        }

        if (candidata.isAtSameMomentAs(mejorFecha)) {
          final yaIncluida = proximas.any(
            (toma) => identical(toma.medicamento, medicamento),
          );

          if (!yaIncluida) {
            proximas.add(TomaProgramada(
              medicamento: medicamento,
              fecha: candidata,
            ));
          }
        }
      }
    }
  }

  proximas.sort((a, b) {
    final nombreA = a.medicamento['nombre']?.toString() ?? '';
    final nombreB = b.medicamento['nombre']?.toString() ?? '';
    return nombreA.toLowerCase().compareTo(nombreB.toLowerCase());
  });

  return proximas;
}

TomaProgramada? buscarProximaToma(
  List<Map<String, dynamic>> medicamentos, {
  DateTime? desde,
}) {
  final proximas = buscarProximasTomas(
    medicamentos,
    desde: desde,
  );

  return proximas.isEmpty ? null : proximas.first;
}

String tiempoRestante(TomaProgramada toma, {DateTime? desde}) {
  final ahora = desde ?? DateTime.now();
  final segundos = toma.fecha.difference(ahora).inSeconds;
  final minutos = segundos <= 0 ? 0 : (segundos + 59) ~/ 60;

  if (minutos == 0) return 'Ahora';

  final dias = minutos ~/ (24 * 60);
  final restoDia = minutos % (24 * 60);
  final horas = restoDia ~/ 60;
  final minutosRestantes = restoDia % 60;

  if (dias > 0) {
    if (horas == 0) return 'En $dias d';
    return 'En $dias d $horas h';
  }

  if (horas == 0) return 'En $minutosRestantes min';
  if (minutosRestantes == 0) return 'En $horas h';
  return 'En $horas h $minutosRestantes min';
}

String etiquetaDiaToma(BuildContext context, DateTime fecha) {
  final hoy = DateTime.now();
  final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
  final inicioFecha = DateTime(fecha.year, fecha.month, fecha.day);
  final diferencia = inicioFecha.difference(inicioHoy).inDays;

  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Mañana';
  return MaterialLocalizations.of(context).formatShortDate(fecha);
}

String resumenHorario(
  BuildContext context,
  Map<String, dynamic> medicamento,
) {
  final tipo = medicamento['tipoHorario']?.toString() ?? 'fijo';

  if (tipo == 'intervalo') {
    final intervalo = _intervaloValido(medicamento['intervaloHoras']);
    return intervalo > 0 ? 'Cada $intervalo h' : 'Por intervalo';
  }

  final hora = medicamento['hora']?.toString() ??
      medicamento['horaInicio']?.toString() ??
      '';
  return formatearHora(context, hora);
}

String descripcionHorario(
  BuildContext context,
  Map<String, dynamic> medicamento,
) {
  final tipo = medicamento['tipoHorario']?.toString() ?? 'fijo';

  if (tipo != 'intervalo') {
    return 'A las ${resumenHorario(context, medicamento)}';
  }

  final intervalo = _intervaloValido(medicamento['intervaloHoras']);
  final inicio = medicamento['horaInicio']?.toString() ??
      medicamento['hora']?.toString() ??
      '08:00';
  final incluirMadrugada = medicamento['incluirMadrugada'] != false;

  if (incluirMadrugada) {
    return 'Cada $intervalo h desde ${formatearHora(context, inicio)} · 24 horas';
  }

  final fin = medicamento['horaFin']?.toString() ?? '22:00';
  return 'Cada $intervalo h · ${formatearHora(context, inicio)} a '
      '${formatearHora(context, fin)}';
}

String textoDiasMedicamento(dynamic valor) {
  final dias = obtenerDiasMedicamento(valor);

  if (dias.length == 7) return 'Todos los días';
  if (dias.isEmpty) return 'Sin días seleccionados';
  return dias.join(' · ');
}

List<String> horasFormateadas(
  BuildContext context,
  Map<String, dynamic> medicamento,
) {
  return minutosProgramados(medicamento)
      .map((minuto) => formatearTomaProgramada(context, minuto))
      .toList();
}
