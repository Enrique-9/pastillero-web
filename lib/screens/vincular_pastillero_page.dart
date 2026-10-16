import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../services/pastillero_ble.dart';

/// La primera cuenta se enlaza con el ESP32 al introducir el PIN de su
/// pantalla y confirmar en el boton fisico. El ESP32 escribe ownerUid.
class VincularPastilleroPage extends StatefulWidget {
  const VincularPastilleroPage({
    super.key,
    required this.usuarioUid,
    required this.yaVinculado,
  });

  final String usuarioUid;
  final bool yaVinculado;

  @override
  State<VincularPastilleroPage> createState() => _VincularPastilleroPageState();
}

class _VincularPastilleroPageState extends State<VincularPastilleroPage> {
  final ble = PastilleroBle();
  final pin = TextEditingController();
  bool trabajando = false;
  String mensaje = 'Enciende el pastillero y busca el PIN en su pantalla.';

  @override
  void initState() {
    super.initState();
    ble.addListener(_actualizar);
  }

  void _actualizar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ble.removeListener(_actualizar);
    ble.dispose();
    pin.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    if (trabajando) return;
    setState(() => trabajando = true);
    try {
      await accion();
    } catch (error) {
      if (mounted) setState(() => mensaje = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => trabajando = false);
    }
  }

  Future<void> _conectar(BleDevice dispositivo) => _ejecutar(() async {
    final codigo = pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      throw StateError('Escribe los seis digitos del PIN de la pantalla.');
    }
    await ble.conectar(dispositivo, codigo);
    if (mounted) setState(() => mensaje = 'Conectado. Pulsa Vincular cuenta.');
  });

  Future<void> _vincular() => _ejecutar(() async {
    await ble.comando('bind_owner', {'uid': widget.usuarioUid});
    if (mounted) setState(() => mensaje =
      'Pulsa el boton fisico del pastillero en los proximos 60 segundos. '
      'Cuando Firebase confirme el vinculo, se abrira la app.');
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular mi pastillero'), actions: [
        TextButton(onPressed: () => FirebaseAuth.instance.signOut(),
          child: const Text('Salir')),
      ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.medication_liquid, size: 70, color: Color(0xFF168C80)),
          const SizedBox(height: 20),
          Text(widget.yaVinculado
              ? 'Este pastillero ya esta vinculado a otra cuenta.'
              : 'Vincula tu cuenta una sola vez. Necesitas estar junto al pastillero.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (!widget.yaVinculado) ...[
            TextField(controller: pin, keyboardType: TextInputType.number,
              maxLength: 6, obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN de la pantalla',
                border: OutlineInputBorder())),
            FilledButton.icon(
              onPressed: trabajando || ble.conectado ? null : () => _ejecutar(ble.buscar),
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(ble.buscando ? 'Buscando...' : 'Buscar pastillero'),
            ),
            for (final dispositivo in ble.dispositivos.values)
              ListTile(
                title: Text(dispositivo.name ?? 'Pastillero'),
                subtitle: const Text('Conectar con el PIN'),
                onTap: trabajando ? null : () => _conectar(dispositivo),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: trabajando || !ble.conectado ? null : _vincular,
              child: const Text('Vincular cuenta'),
            ),
          ],
          const SizedBox(height: 18),
          Text(mensaje, textAlign: TextAlign.center),
          if (trabajando) const Center(child: CircularProgressIndicator()),
        ]),
      ))),
    );
  }
}
