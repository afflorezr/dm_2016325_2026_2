library(shiny); library(bslib); library(DBI); library(RSQLite)
library(highcharter); library(DT)
library(promises); library(future)
plan(multisession)
source("db.R")
source("scraper.R", encoding = "UTF-8")
# Color fijo por comercio. Los nombres deben ser iguales a comercios.nombre
PALETA_COMERCIOS <- c("Éxito" = "#E69F00", "Farmatodo" = "#0072B2", "La Rebaja" = "#009E73")

UMBRAL_DEFECTO <- 10  # % para resaltar variaciones grandes

formato_cop <- function(x) {
  ifelse(is.na(x), "sin dato", paste0("$ ", formatC(
    x, format = "d", big.mark = ".",decimal.mark = ",")))
}

