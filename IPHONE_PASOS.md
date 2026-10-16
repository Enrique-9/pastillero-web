# Pastillero en iPhone

Este proyecto ya incluye la descripción del permiso Bluetooth en
`ios/Runner/Info.plist`. El firmware ESP32 que funciona con Android también
anuncia BLE para el iPhone.

## Pendientes antes de ejecutar

1. Se necesita una **Mac** con Flutter, Xcode y las herramientas de iOS
   configuradas. Una PC Windows puede editar el código, pero no generar ni
   firmar la app nativa para iPhone. Para probarla en un iPhone propio puedes
   configurar en Xcode una cuenta personal gratuita de Apple y firmar el
   proyecto para desarrollo. Publicarla para otras personas requiere el
   programa de distribución de Apple.
2. Registra una app **iOS** dentro de tu proyecto Firebase existente
   `pastillero-digital-8ad62`. En Xcode cambia `com.example.pastilleroApp`
   por un identificador de paquete único y usa exactamente el mismo al
   registrar la app en Firebase.
3. En la Mac, desde la raíz del proyecto, ejecuta `flutterfire configure` y
   elige el proyecto Firebase existente y la plataforma iOS. Verifica que
   `lib/firebase_options.dart` ahora incluye `TargetPlatform.iOS` con valores
   reales, en lugar de lanzar `UnsupportedError`. No copies los valores de
   Android: Firebase usa otro ID de aplicación para iOS.
4. En la Mac conecta el iPhone, acepta **Confiar en esta computadora**,
   habilita **Modo de desarrollador** en el iPhone, abre
   `ios/Runner.xcworkspace` en Xcode y elige tu equipo en **Signing &
   Capabilities**. Luego ejecuta `flutter pub get` y `flutter run` desde la
   raíz del proyecto, seleccionando tu iPhone.
5. Al entrar a Bluetooth en la app, permite el acceso cuando iOS lo pida,
   toca **Buscar pastillero**, selecciona `Pastillero-XXXXXX` e introduce el
   PIN de seis dígitos de la pantalla del pastillero.

Este paquete es el proyecto fuente, **no** un archivo `.ipa` instalable. No
se pudo compilar iOS aquí por no disponer de macOS/Xcode y aún falta la
configuración Firebase específica de tu app iOS.
