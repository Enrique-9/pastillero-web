import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formularioKey = GlobalKey<FormState>();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarPasswordController = TextEditingController();

  bool _crearCuenta = false;
  bool _procesando = false;
  bool _ocultarPassword = true;
  bool _ocultarConfirmacion = true;
  String? _mensajeError;

  @override
  void dispose() {
    _correoController.dispose();
    _passwordController.dispose();
    _confirmarPasswordController.dispose();
    super.dispose();
  }

  void _cambiarModo() {
    if (_procesando) return;

    setState(() {
      _crearCuenta = !_crearCuenta;
      _mensajeError = null;
      _confirmarPasswordController.clear();
    });
  }

  Future<void> _continuar() async {
    FocusScope.of(context).unfocus();

    if (!_formularioKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _procesando = true;
      _mensajeError = null;
    });

    final correo = _correoController.text.trim();
    final password = _passwordController.text;

    try {
      if (_crearCuenta) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: correo,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: correo,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _mensajeError = _traducirError(error.code);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _mensajeError =
            'No se pudo completar la operación. Inténtalo nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  String _traducirError(String codigo) {
    switch (codigo) {
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con este correo.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'El correo o la contraseña son incorrectos.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos e inténtalo otra vez.';
      case 'network-request-failed':
        return 'No hay conexión con Firebase. Revisa tu Internet.';
      case 'operation-not-allowed':
        return 'El acceso por correo no está habilitado en Firebase.';
      default:
        return 'No se pudo acceder. Código: $codigo';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formularioKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      backgroundColor: Color(0xFF168C80),
                      child: Icon(
                        Icons.medication_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Mi Pastillero',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _crearCuenta
                          ? 'Crea la cuenta del familiar responsable'
                          : 'Acceso para el familiar responsable',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1417324D),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _crearCuenta ? 'Crear cuenta' : 'Iniciar sesión',
                            style: const TextStyle(
                              color: Color(0xFF17324D),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _correoController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            enabled: !_procesando,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (valor) {
                              final correo = valor?.trim() ?? '';
                              if (correo.isEmpty) {
                                return 'Escribe el correo electrónico';
                              }
                              if (!correo.contains('@') ||
                                  !correo.contains('.')) {
                                return 'Escribe un correo válido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _ocultarPassword,
                            autofillHints: _crearCuenta
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            textInputAction: _crearCuenta
                                ? TextInputAction.next
                                : TextInputAction.done,
                            enabled: !_procesando,
                            onFieldSubmitted: (_) {
                              if (!_crearCuenta) _continuar();
                            },
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _ocultarPassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                onPressed: _procesando
                                    ? null
                                    : () {
                                        setState(() {
                                          _ocultarPassword =
                                              !_ocultarPassword;
                                        });
                                      },
                                icon: Icon(
                                  _ocultarPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Escribe la contraseña';
                              }
                              if (valor.length < 6) {
                                return 'Utiliza al menos 6 caracteres';
                              }
                              return null;
                            },
                          ),
                          if (_crearCuenta) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmarPasswordController,
                              obscureText: _ocultarConfirmacion,
                              autofillHints: const [
                                AutofillHints.newPassword,
                              ],
                              textInputAction: TextInputAction.done,
                              enabled: !_procesando,
                              onFieldSubmitted: (_) => _continuar(),
                              decoration: InputDecoration(
                                labelText: 'Confirmar contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: _ocultarConfirmacion
                                      ? 'Mostrar contraseña'
                                      : 'Ocultar contraseña',
                                  onPressed: _procesando
                                      ? null
                                      : () {
                                          setState(() {
                                            _ocultarConfirmacion =
                                                !_ocultarConfirmacion;
                                          });
                                        },
                                  icon: Icon(
                                    _ocultarConfirmacion
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (valor) {
                                if (!_crearCuenta) return null;
                                if (valor != _passwordController.text) {
                                  return 'Las contraseñas no coinciden';
                                }
                                return null;
                              },
                            ),
                          ],
                          if (_mensajeError != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE8E7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Color(0xFFB3261E),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _mensajeError!,
                                      style: const TextStyle(
                                        color: Color(0xFFB3261E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _procesando ? null : _continuar,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                            ),
                            icon: _procesando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _crearCuenta
                                        ? Icons.person_add_alt_1
                                        : Icons.login,
                                  ),
                            label: Text(
                              _procesando
                                  ? 'Espera un momento...'
                                  : _crearCuenta
                                      ? 'Crear cuenta'
                                      : 'Iniciar sesión',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _procesando ? null : _cambiarModo,
                            child: Text(
                              _crearCuenta
                                  ? 'Ya tengo cuenta'
                                  : 'Crear una cuenta nueva',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'La cuenta es para quien administra los horarios. El adulto mayor solo utiliza el botón físico del pastillero.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
