# Primera vinculacion

Esta app permite a la persona crear su propia cuenta. El correo y la contrasena solo se introducen en la app; nadie debe enviarlos al desarrollador.

La cuenta del ESP32 se configura por USB y es diferente. Una vez que el firmware y las reglas de `Pastillero_BLE_WiFi_vinculacion.zip` esten preparados, la persona inicia sesion en la app, busca su pastillero por Bluetooth, introduce el PIN de la pantalla, toca Vincular cuenta y pulsa el boton fisico del ESP32 en menos de 60 segundos. El ESP32 requiere Wi-Fi e Internet en ese momento. El vinculo se guarda en Firebase y sobrevive a reinicios y cambios de telefono si se inicia sesion con la misma cuenta.

La app mostrara que el pastillero ya pertenece a otra cuenta si el vinculo previo existe. La transferencia de propiedad requiere un procedimiento de migracion con respaldo de los datos; no publiques reglas abiertas ni borres ownerUid para resolverlo.
