# .Rprofile — c\u00f3digo que se eval\u00faa al arrancar R en este directorio
#
# Fija semilla global para reproducibilidad; cualquier consumidor puede
# sobreescribirla. Configura CRAN mirror por si se instalan paquetes.

if (interactive()) {
  options(width = 110)
}

# Si renv est\u00e1 activo, lo respeta; si no, usa global libPaths
if (requireNamespace("renv", quietly = TRUE) &&
    file.exists("renv.lock") &&
    file.exists("renv/activate.R")) {
  source("renv/activate.R")
}
