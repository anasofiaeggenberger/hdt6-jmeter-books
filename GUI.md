# Corrida GUI de 100 usuarios

Estas instrucciones preparan la evidencia solicitada por el README. La captura debe salir de JMeter; no se incluye una imagen fabricada en el repositorio.

## Plugins

1. Ejecutar `jmeter`.
2. Abrir `Options > Plugins Manager > Installed Plugins`.
3. Confirmar que aparezcan `Custom Thread Groups` y `3 Basic Graphs`.
4. Tomar la captura de esa pestaña y guardarla como `evidencia/plugins.png`.

## Gráficos y corrida

1. Iniciar el API desde la raíz con `uv run api.py`.
2. En otra terminal, comprobar `curl -fsS http://127.0.0.1:8000/health` y ejecutar `curl -fsS -X POST http://127.0.0.1:8000/reset`.
3. Abrir el plan con las propiedades de la corrida:

   ```bash
   jmeter -Jusers=100 -Jramp_up=10 -Jhold=60 -Jcsv_file="$PWD/books.csv" -t plan.jmx
   ```

4. En el árbol de JMeter, agregar bajo el Test Plan estos listeners de `Add > Listener`:
   - `jp@gc - Active Threads Over Time`
   - `jp@gc - Response Times Over Time`
   - `jp@gc - Transactions per Second`
5. Presionar Start y esperar a que termine la corrida de 10 segundos de ramp-up más 60 segundos sostenidos.
6. Verificar que el Summary Report no muestre errores inesperados y que el listener de cada gráfico tenga datos.
7. Ajustar la ventana para que los tres gráficos queden visibles, tomar la captura real y guardarla como `evidencia/graficos.png`.

Los listeners son para la corrida GUI de evidencia. Las cinco corridas oficiales se ejecutan con `run_load_tests.sh` en modo no GUI.
