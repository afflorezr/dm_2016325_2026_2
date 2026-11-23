# Minería de Datos - Clase 7: equivalentes en Python (ejercicios 3f, 4e y 5f)
# Angela Tatiana Rincón Barrera

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import MinMaxScaler, OneHotEncoder, StandardScaler, FunctionTransformer
from sklearn.impute import SimpleImputer
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline

ruta_datos = "DATOS"


# Ejercicio 3f: mediana por pclass y sex ----------------------------------
# usa el archivo que genera el script de R con las mismas edades ocultas

imp_r = pd.read_csv("ej3_imputacion_r.csv")

mediana_grupo = imp_r.groupby(["pclass", "sex"])["age_obs"].transform("median")
imp_r["imp_python"] = imp_r["age_obs"].fillna(mediana_grupo)

print("Ejercicio 3f")
print(imp_r.loc[imp_r["oculta"], ["pclass", "sex", "imp_clase_sexo", "imp_python"]].head())
print("Iguales a R:", np.allclose(imp_r["imp_python"], imp_r["imp_clase_sexo"]))


# Ejercicio 4e: MinMaxScaler ajustado solo con entrenamiento --------------

mobile = pd.read_csv(f"{ruta_datos}/mobile_data.csv")
X = mobile.drop(columns="price_range")
y = mobile["price_range"]

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=2024)

escalador = MinMaxScaler().fit(X_train)
X_test_esc = escalador.transform(X_test)

fuera = ((X_test_esc < 0) | (X_test_esc > 1)).sum()
print("\nEjercicio 4e")
print("Valores de prueba fuera de [0, 1]:", fuera)
print("Porcentaje:", round(100 * fuera / X_test_esc.size, 3), "%")


# Ejercicio 5f: Pipeline con ColumnTransformer -----------------------------

adult = pd.read_csv(f"{ruta_datos}/adult.csv")
adult = adult.apply(lambda c: c.str.strip() if c.dtype == "object" else c)
adult = adult.replace("?", np.nan)

y = (adult["income"] == ">50K").astype(int)
X = adult.drop(columns=["income", "education"])

X["ganancia_centinela"] = (X["capital.gain"] == 99999).astype(int)
X["capital.gain"] = X["capital.gain"].replace(99999, 41310)
pais = X["native.country"]
X["native.country"] = pais.where(pais.isna(),
                                 np.where(pais == "United-States", "Estados Unidos", "Otro"))

continuas = ["age", "fnlwgt", "education.num", "hours.per.week"]
logaritmo = ["capital.gain", "capital.loss"]
categoricas = ["workclass", "marital.status", "sex", "occupation",
               "relationship", "race"]

preprocesador = ColumnTransformer([
    ("num", Pipeline([("imputar", SimpleImputer(strategy="median")),
                      ("escalar", StandardScaler())]), continuas),
    ("log", Pipeline([("imputar", SimpleImputer(strategy="median")),
                      ("log", FunctionTransformer(np.log1p)),
                      ("escalar", StandardScaler())]), logaritmo),
    ("cat", Pipeline([("imputar", SimpleImputer(strategy="constant", fill_value="Desconocido")),
                      ("onehot", OneHotEncoder(handle_unknown="ignore"))]), categoricas),
    ("pais", Pipeline([("imputar", SimpleImputer(strategy="most_frequent")),
                       ("onehot", OneHotEncoder(handle_unknown="ignore"))]), ["native.country"]),
], remainder="passthrough")

pipeline = Pipeline([("preprocesar", preprocesador)])

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=2024)

X_train_listo = pipeline.fit_transform(X_train)   # aprende medianas, niveles, medias y sd
X_test_listo = pipeline.transform(X_test)          # solo aplica lo aprendido

print("\nEjercicio 5f")
print("Entrenamiento:", X_train_listo.shape, "| Prueba:", X_test_listo.shape)
print("NA en prueba:", np.isnan(X_test_listo.toarray() if hasattr(X_test_listo, "toarray")
                                else X_test_listo).sum())
