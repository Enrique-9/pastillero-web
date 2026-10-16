# Pastillero web con Bluetooth en iPhone

Git guarda el código; **GitHub Pages** publica el sitio con HTTPS. El iPhone
debe abrir ese sitio dentro de **Bluefy**, no dentro de Safari.

## Publicación

1. Sube **el contenido de esta carpeta `pastillero_app`** a la raíz de un
   repositorio de GitHub. No subas `build/`, `.dart_tool/`, copias de seguridad,
   contraseñas ni datos reales de pacientes.
2. Asegúrate de que la rama principal del repositorio se llame `main`.
3. En GitHub abre **Settings > Pages > Build and deployment > Source** y
   selecciona **GitHub Actions**. El archivo `.github/workflows/pages.yml`
   compilará Flutter web y publicará `build/web` automáticamente al subir
   cambios a `main`.
4. Cuando Actions termine con éxito, la URL será habitualmente
   `https://USUARIO.github.io/REPOSITORIO/`. Para un repositorio llamado
   `USUARIO.github.io`, la URL será `https://USUARIO.github.io/`.
5. En el iPhone instala Bluefy, enciende Bluetooth, abre esa URL HTTPS dentro
   de Bluefy, entra a Bluetooth > Buscar pastillero, selecciona
   `Pastillero-XXXXXX` y escribe el PIN de la pantalla del dispositivo.

**Importante:** GitHub Pages publica una página visible por cualquiera que
conozca la dirección. El acceso a datos de medicamentos debe protegerse con
las reglas de Firebase; ocultar el código o la API key no sustituye las
reglas. Verifica las reglas de tu Realtime Database antes de usar datos reales.

La versión web usa el mismo código Flutter y el servicio BLE del firmware.
El selector de dispositivos BLE se invoca al tocar el botón, como requieren
los navegadores Web Bluetooth. Todavía hay que probar el flujo completo en
un iPhone con Bluefy; no pudimos ejecutar Flutter ni probar el hardware aquí.
