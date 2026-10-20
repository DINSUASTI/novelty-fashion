# novelty_fashion

## Inventario inicial

El APK incluye `assets/novelty_fashion.db`, una base SQLite ya poblada con los
83 productos, y `assets/INVENTARIO INICIAL.xlsx` como archivo de consulta
descargable desde Opciones de inventario. El XLSX (hoja `Ventas`, siete columnas
sin SKU) sirve para generar la base antes del build; no participa en las
consultas, los cálculos ni las ediciones. En una instalación nueva, la base se
copia al almacenamiento privado antes del desbloqueo biométrico. Si la base ya
existe, no se reemplaza: las
actualizaciones conservan los cambios locales.

Para regenerar la base empaquetada al cambiar el Excel, ejecutar
`flutter test tool/build_seed_database_test.dart` antes de `flutter build apk --release`.
Cada producto conserva su referencia, que puede repetirse entre productos.
El histórico registra solo los archivos importados por el usuario. La plantilla descargable tiene siete
columnas sin identificador interno; el importador también acepta los archivos antiguos
que sí lo incluían. La ganancia proyectada inicial es $4.485.000 sobre una inversión de
$4.766.000. Si se vacía el inventario desde la app, el histórico se conserva y
el inventario inicial no se vuelve a cargar automáticamente.

El identificador único de cada producto se asigna internamente como el mayor
identificador numérico existente más uno. No aparece en pantallas, plantillas ni
informes exportados. La referencia sí puede modificarse al editar un producto.

## Actualizar el APK sin perder los datos

El inventario y las fotos locales se guardan en la base privada
`novelty_fashion.db` de Android. Al instalar una actualización sobre la app
existente, Android conserva esta base; la app la reabre y aplica las migraciones
de esquema necesarias sin borrar los registros.

Cada importación exitosa guarda una copia del Excel original en SQLite. El menú
"Archivos importados" permite consultar y descargar esas copias. La opción
"Borrar todo el inventario" exige confirmación y biometría; elimina productos,
fotos e historial de cantidades, pero conserva los archivos importados para
poder recuperar una versión anterior o cargar un inventario corregido.
Al terminar una importación se muestra el nombre del archivo y los productos
procesados, creados y actualizados; si falla, se muestra el motivo.
La biometría se solicita al iniciar la aplicación y para confirmar ese borrado,
no al regresar a la app desde el Home del dispositivo.

1. Incrementar el número después de `+` en `version` de `pubspec.yaml` para cada
	actualización (por ejemplo, `1.0.1+2` después de `1.0.0+1`).
2. Mantener `applicationId` y la clave de firma originales. Actualmente el APK
	de release se firma con la clave de depuración local; conservar esa clave es
	imprescindible para actualizar los APK ya instalados con ella. Para una
	distribución definitiva se necesita una clave de release estable y respaldada.
3. Ejecutar `./tool/build_release_apk.ps1`. El APK para copiar o instalar se
	crea siempre en `build/app/outputs/flutter-apk/NoveltyFashion.apk`. Para una
	actualización por ADB, usar `adb install -r build/app/outputs/flutter-apk/NoveltyFashion.apk`.

No desinstalar la app: elimina los datos privados. Una firma distinta impedirá
la actualización. Antes de distribuir, verificar una actualización con datos
reales o de prueba y mantener una copia de seguridad independiente.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
