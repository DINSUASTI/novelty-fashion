import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

Future<bool> authenticateWithBiometrics(String reason) {
  return LocalAuthentication().authenticate(
    localizedReason: reason,
    biometricOnly: false,
    persistAcrossBackgrounding: true,
  );
}

class AndroidBiometricGate extends StatefulWidget {
  const AndroidBiometricGate({
    super.key,
    required this.child,
    this.authenticate,
  });

  final Widget child;
  final Future<bool> Function()? authenticate;

  @override
  State<AndroidBiometricGate> createState() => _AndroidBiometricGateState();
}

class _AndroidBiometricGateState extends State<AndroidBiometricGate> {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  bool _authenticationFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating || _isAuthenticated) return;
    setState(() {
      _isAuthenticating = true;
      _authenticationFailed = false;
    });

    var authenticated = false;
    try {
      authenticated =
          await (widget.authenticate ?? _authenticateBiometrically)();
    } catch (_) {
      authenticated = false;
    }

    if (!mounted) return;
    setState(() {
      _isAuthenticating = false;
      _isAuthenticated = authenticated;
      _authenticationFailed = !authenticated;
    });
  }

  Future<bool> _authenticateBiometrically() {
    return authenticateWithBiometrics(
      'Autentícate para abrir Novelty Fashion.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) return widget.child;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Novelty Fashion',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo_novelty_transparent.png',
                  width: 220,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 28),
                const Text('Desbloqueo seguro'),
                if (_authenticationFailed) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'La autenticación no se completó. Usa tu huella, rostro o PIN del dispositivo para continuar.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                if (_isAuthenticating)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Autenticar con biometría o PIN'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
