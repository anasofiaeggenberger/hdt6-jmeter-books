# Resultados HDT 6

Los datos salen de la fila `Total` de cada `statistics.json` real. Todas las corridas usaron ramp-up de 10 segundos y 60 segundos sostenidos.

| Usuarios | Muestras | Solicitudes/s | p50 (ms) | p95 (ms) | p99 (ms) | Errores | Exit code gate |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 62058 | 883.325030247 | 17 | 32 | 40 | 0.00% | 0 |
| 50 | 62098 | 881.835868161 | 86 | 172 | 202 | 0.00% | 1 |
| 100 | 62006 | 880.091974906 | 175 | 336 | 424 | 0.00% | 1 |
| 200 | 62259 | 879.600457750 | 350 | 620 | 866 | 0.00% | 1 |
| 500 | 61406 | 865.275409697 | 886 | 1564 | 2695 | 0.00% | 1 |

## Respuestas del README

- El primer nivel cuyo p95 supera 100 ms es **50 usuarios**, con p95 de **172 ms**. En 10 usuarios el p95 fue 32 ms.
- Entre 200 y 500 usuarios, las solicitudes por segundo bajaron de **879.600457750** a **865.275409697**: una disminución de **14.325048053 solicitudes/s**, equivalente a **1.628586%**.
- En la corrida de 500 usuarios, la máquina reportó **10 núcleos**. Según la medición de CPU, el API promedió **94.69%** y alcanzó **100.00%**; JMeter promedió **0.01%** y alcanzó **1.00%**. Con esta evidencia, el API parece ser el proceso limitante de esta corrida. Es una conclusión prudente basada en una medición: no demuestra por sí sola toda la causalidad.

Los datos de CPU están en el reporte completo de 500 usuarios: `cpu.csv`, `cpu_summary.txt` y `cpu_cores.txt`. La puerta usa p95 <= 100 ms y errores <= 1%.
