import 'package:flutter/material.dart';

import 'horario_medicamento.dart';

/// Un espacio físico del pastillero: día y toma (1, 2 o 3).
class CasillaLlenado {
  final String dia;
  final int toma;
  final int minuto;
  final List<String> medicamentos;

  const CasillaLlenado(this.dia, this.toma, this.minuto, this.medicamentos);

  String get hora =>
      '${(minuto ~/ 60).toString().padLeft(2, '0')}:'
      '${(minuto % 60).toString().padLeft(2, '0')}';
}

class PlanLlenado {
  final List<CasillaLlenado> casillas;
  final List<String> errores;

  const PlanLlenado(this.casillas, this.errores);
  bool get cabe => errores.isEmpty;
}

/// Recalcular SIEMPRE con la lista completa, después de añadir, editar o borrar.
PlanLlenado generarPlanLlenado(List<Map<String, dynamic>> medicamentos) {
  final casillas = <CasillaLlenado>[];
  final errores = <String>[];

  for (final dia in diasMedicamento) {
    final porHora = <int, List<String>>{};

    for (final med in medicamentos) {
      if (med['activo'] == false) continue;
      if (!obtenerDiasMedicamento(med['dias']).contains(dia)) continue;

      final nombre = med['nombre']?.toString().trim() ?? '';
      final dosis = med['dosis']?.toString().trim() ?? '';
      final descripcion = dosis.isEmpty ? nombre : '$nombre — $dosis';
      for (final minuto in minutosProgramados(med).toSet()) {
        if (minuto < 0 || minuto >= 1440) continue;
        porHora.putIfAbsent(minuto, () => []).add(descripcion);
      }
    }

    final horas = porHora.keys.toList()..sort();
    if (horas.length > 3) {
      errores.add('$dia tiene ${horas.length} horarios distintos; solo hay 3 casillas.');
      continue;
    }
    for (var i = 0; i < horas.length; i++) {
      final minuto = horas[i];
      casillas.add(CasillaLlenado(dia, i + 1, minuto, porHora[minuto]!));
    }
  }

  return PlanLlenado(casillas, errores);
}

class PlanLlenadoPage extends StatefulWidget {
  final List<Map<String, dynamic>> medicamentos;

  const PlanLlenadoPage({super.key, required this.medicamentos});

  @override
  State<PlanLlenadoPage> createState() => _PlanLlenadoPageState();
}

class _PlanLlenadoPageState extends State<PlanLlenadoPage> {
  final Set<String> revisadas = {};

  @override
  Widget build(BuildContext context) {
    final plan = generarPlanLlenado(widget.medicamentos);
    return Scaffold(
      appBar: AppBar(title: const Text('Guía de llenado')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Revisa cada casilla antes de marcarla. La app no detecta físicamente las pastillas.'),
          const SizedBox(height: 12),
          for (final error in plan.errores)
            Card(
              color: const Color(0xFFFFE8E4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error),
              ),
            ),
          if (plan.errores.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Corrige estos horarios antes de llenar el pastillero.'),
            ),
          if (plan.cabe)
            for (final casilla in plan.casillas)
              CheckboxListTile(
                title: Text('${casilla.dia} · Toma ${casilla.toma} · ${casilla.hora}'),
                subtitle: Text(casilla.medicamentos.join('\n')),
                isThreeLine: casilla.medicamentos.length > 1,
                value: revisadas.contains('${casilla.dia}-${casilla.toma}'),
                onChanged: (marcada) => setState(() {
                  final clave = '${casilla.dia}-${casilla.toma}';
                  if (marcada == true) {
                    revisadas.add(clave);
                  } else {
                    revisadas.remove(clave);
                  }
                }),
              ),
          if (plan.cabe && plan.casillas.isEmpty)
            const Text('No hay medicamentos activos programados.'),
        ],
      ),
    );
  }
}
