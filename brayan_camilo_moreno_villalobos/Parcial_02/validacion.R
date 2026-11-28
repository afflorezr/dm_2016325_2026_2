library(pointblank)

validar_observaciones <- function(df) {
 
  agente <- create_agent(tbl = df) |>

    col_vals_gt(columns = precio, value = 0) |>
    
    col_vals_not_null(columns = c(Comercio, `URL de extracción`, `Fecha y hora de consulta`)) |>
    
    rows_distinct(columns = c(Comercio, id_anuncio, `Fecha y hora de consulta`)) |>
    
    interrogate()
  
  return(all_passed(agente))
}