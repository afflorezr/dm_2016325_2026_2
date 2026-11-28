"""Pruebas de la interfaz contra una SQLite temporal, sin usar los datos entregados."""
from pathlib import Path
import pytest
from streamlit.testing.v1 import AppTest
import db
from test_logica import fila,insertar


@pytest.fixture
def interfaz(tmp_path,monkeypatch):
    path=tmp_path/'ui.sqlite';db.inicializar(path)
    for run,price in [('20260101T100000_test',100),('20260102T100000_test',120)]:
        for store in ('colsubsidio','cafam','larebaja'):
            insertar(path,[fila(run=run,store=store,price=price)])
    monkeypatch.setattr(db,'DB',path)
    import streamlit as st
    st.cache_data.clear()
    yield Path(__file__).resolve().parents[1]/'app.py'
    st.cache_data.clear()


def test_inicio_y_filtro_vacio(interfaz):
    app=AppTest.from_file(str(interfaz),default_timeout=30).run()
    assert not app.exception
    assert not app.error
    assert len(app.metric)==6
    app.multiselect[0].set_value([]).run()
    assert not app.exception
    assert app.metric[0].value=='0'


@pytest.mark.parametrize('page',['catalogo','historial','canasta','actualizar','calidad'])
def test_paginas(interfaz,page):
    app=AppTest.from_file(str(interfaz),default_timeout=30).run()
    app.switch_page('paginas/'+page+'.py').run()
    assert not app.exception
    assert not app.error
    if page=='historial':
        widget=next(w for w in app.selectbox if w.label=='Presentación comparable')
        widget.set_value('rexona_men_48').run()
        assert not app.exception
        assert len(app.get('plotly_chart'))==2
    if page=='canasta': assert app.metric[0].value=='Sin dato'
