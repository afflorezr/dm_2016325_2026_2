file.edit("~/.Renviron")
Sys.getenv("TABPFN_TOKEN") != ""

#install.packages("tabpfn")
library(tabpfn)

file.exists("heart.csv")

archivo   <- "heart.csv"  # <- su archivo
respuesta <- "target"          # <- su respuesta
quitar <- c("fbs", "chol", "trestbps", "restecg")              # <- columnas a quitar

d <- unique(read.csv(archivo, fileEncoding = "UTF-8"))
set.seed(2026)
if (nrow(d) > 3000) d <- d[sample(nrow(d), 3000), ]
d <- d[, setdiff(names(d), quitar)]
texto <- sapply(d, is.character) & names(d) != respuesta
d[texto] <- lapply(d[texto], function(v) as.integer(factor(v)))
d[[respuesta]] <- factor(d[[respuesta]])


set.seed(2026)
i <- sample(nrow(d), round(0.75 * nrow(d)))
entreno <- d[i, ]                # 75 %: lo que el modelo lee
prueba  <- d[-i, ]               # 25 %: el examen
c(nrow(entreno), nrow(prueba))


library(reticulate)
library(tabpfn)


# 1. Crear un entorno virtual dedicado
virtualenv_create("r-tabpfn")

# 2. Instalar la librería tabpfn (y torch, su dependencia principal) en ese entorno
virtualenv_install("r-tabpfn", packages = c("tabpfn", "torch"))

library(reticulate)
use_virtualenv("r-tabpfn", required = TRUE)
py_config()



formula <- as.formula(paste(respuesta, "~ ."))
modelo  <- tab_pfn(formula, data = entreno)  # lee el entrenamiento
pred    <- predict(modelo, prueba)           # una fila por caso
head(pred)






error <- mean(pred$.pred_class != prueba[[respuesta]])
comun <- names(which.max(table(entreno[[respuesta]])))
base  <- mean(prueba[[respuesta]] != comun)   # sin modelo
cat("Sin modelo:", round(100 * base, 1), "%  TabPFN:",
    round(100 * error, 1), "%\n")
