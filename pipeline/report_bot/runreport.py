#!/usr/bin/env python3
"""
SmartMoving - Automatizacion del envio de "All Jobs Report"

    pip install playwright
    playwright install chromium
    python send_report.py

Primera vez (para guardar la sesion):
    playwright open --save-storage=auth.json https://app.smartmoving.com
"""

import os
import re
import sys
from datetime import datetime, timedelta

from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

# --- CONFIGURACION -----------------------------------------------------------
EMAIL      = os.getenv("REPORT_EMAIL", "nicolas@ecomovers.com")
REPORT_URL = os.getenv("REPORT_URL", "https://app.smartmoving.com/reports/all-jobs")
STORAGE    = os.getenv("STORAGE", "auth.json")
HEADLESS   = os.getenv("HEADLESS", "true").lower() != "false"
FORCE_MODE = os.getenv("MODE") or None          # 'yearly' | 'relative' | None (auto)

MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
          "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

START_SEL = 'input[formcontrolname="jobDateRangeStart"]'
END_SEL   = 'input[formcontrolname="jobDateRangeEnd"]'
EMAIL_SEL = '[data-test-id="sendResultsTo"]'
RUN_SEL   = 'button[data-test-id="x4y9tu7gjb"]'

PROFILE_ICON_SEL = '[data-test-id="profileMenuInitialsIcon"]'
PROFILE_NAV_SEL  = '[data-test-id="profileMenuNav"]'
LOGOUT_SEL       = '[data-test-id="profileMenuLogOut"] a'

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


# --- 1. RANGO DE FECHAS SEGUN LA HORA DE EJECUCION ---------------------------
def resolve_range(now=None):
    """Entre 3 y 10 a.m. -> anio completo. De 10 a.m. en adelante -> -90/+60 dias."""
    now = now or datetime.now()
    mode = FORCE_MODE or ("yearly" if 3 <= now.hour < 10 else "relative")

    if mode == "yearly":
        return mode, datetime(now.year, 1, 1), datetime(now.year, 12, 31)

    today = datetime(now.year, now.month, now.day)
    return mode, today - timedelta(days=90), today + timedelta(days=60)


def iso(d):
    return d.strftime("%Y-%m-%d")


def mdy(d):
    """Formato que muestra el input: M/D/YYYY, sin ceros a la izquierda."""
    return f"{d.month}/{d.day}/{d.year}"


# --- 2. SELECCION DE FECHA EN EL DATEPICKER (Angular Material) ---------------
def pick_date(page, selector, date, label):
    inp = page.locator(selector)
    inp.scroll_into_view_if_needed()
    inp.click()

    cal = page.locator("mat-datepicker-content").last
    cal.wait_for(state="visible", timeout=10_000)

    # a) Abrir la vista multi-anio
    cal.locator(".mat-calendar-period-button").click()
    page.wait_for_timeout(300)

    # b) Navegar bloques de 24 anios hasta encontrar el anio objetivo
    year = date.year
    found = False
    for _ in range(15):
        cell = cal.locator(".mat-calendar-body-cell-content",
                           has_text=re.compile(rf"^{year}$"))
        if cell.count():
            cell.first.click()
            found = True
            break

        first_shown = int(cal.locator(".mat-calendar-body-cell-content")
                             .first.inner_text().strip())
        direction = (".mat-calendar-previous-button" if year < first_shown
                     else ".mat-calendar-next-button")
        nav = cal.locator(direction)
        if nav.is_disabled():
            raise RuntimeError(
                f"[{label}] No se puede navegar hasta el anio {year} (flecha deshabilitada).")
        nav.click()
        page.wait_for_timeout(250)

    if not found:
        raise RuntimeError(f"[{label}] Anio {year} no encontrado en el calendario.")
    page.wait_for_timeout(300)

    # c) Mes
    month = MONTHS[date.month - 1]
    month_cell = cal.locator(".mat-calendar-body-cell").filter(
        has=page.locator(f'.mat-calendar-body-cell-content:text-is("{month}")')).first
    if month_cell.get_attribute("aria-disabled") == "true":
        raise RuntimeError(
            f"[{label}] El mes {month} {year} esta deshabilitado (fuera del min/max permitido).")
    month_cell.click()
    page.wait_for_timeout(300)

    # d) Dia
    day_cell = cal.locator(".mat-calendar-body-cell").filter(
        has=page.locator(f'.mat-calendar-body-cell-content:text-is("{date.day}")')).first
    if day_cell.get_attribute("aria-disabled") == "true":
        raise RuntimeError(
            f"[{label}] El dia {mdy(date)} esta deshabilitado. "
            "Revisa el orden en que se asignan las fechas.")
    day_cell.click()

    try:
        cal.wait_for(state="hidden", timeout=5_000)
    except PWTimeout:
        pass

    # e) Verificar que quedo escrito
    got = inp.input_value().strip()
    if got != mdy(date):
        raise RuntimeError(f'[{label}] Esperaba "{mdy(date)}" pero el campo quedo en "{got}".')
    print(f"   OK {label}: {got}")


# --- 3. LOGOUT ---------------------------------------------------------------
def logout(page):
    """Abre el menu de perfil y hace click en Log Out.

    Nunca lanza excepcion: el reporte ya se envio, un fallo aqui no debe
    marcar toda la corrida como fallida. Solo avisa.
    """
    try:
        # El menu puede venir ya abierto (clase 'open'); si no, se abre con el icono.
        nav = page.locator(PROFILE_NAV_SEL)
        already_open = "open" in (nav.get_attribute("class") or "")
        if not already_open:
            page.locator(PROFILE_ICON_SEL).click()
            page.wait_for_timeout(600)

        link = page.locator(LOGOUT_SEL)
        link.wait_for(state="visible", timeout=5_000)
        link.click()

        # Confirmar que realmente salio: la app redirige fuera de /reports.
        page.wait_for_url(re.compile(r"/(logout|login|sign-?in)"),
                          timeout=15_000)
        page.wait_for_timeout(1_500)
        print(f"   OK Logout: {page.url}")
    except Exception as err:
        print(f"   AVISO: no se pudo cerrar sesion ({err}). "
              "Cerrando el navegador de todas formas.", file=sys.stderr)


# --- 4. FLUJO PRINCIPAL ------------------------------------------------------
def main():
    # Validacion temprana del email: el campo es required y valida formato.
    # Si es invalido, Angular deshabilita Run Report y el click nunca funciona.
    if not EMAIL_RE.match(EMAIL):
        print(f"ERROR: REPORT_EMAIL invalido: '{EMAIL}'. "
              "Debe ser una direccion completa (usuario@dominio.com).", file=sys.stderr)
        sys.exit(1)

    mode, start, end = resolve_range()
    print(f"Modo:  {mode}\nRango: {iso(start)} -> {iso(end)}\nEmail: {EMAIL}\n")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        context = browser.new_context(
            storage_state=STORAGE if os.path.exists(STORAGE) else None)
        page = context.new_page()

        try:
            page.goto(REPORT_URL, wait_until="domcontentloaded")
            page.wait_for_selector(START_SEL, timeout=30_000)
            page.wait_for_timeout(1_500)   # deja que Angular hidrate los valores por defecto

            # -- ORDEN DE ASIGNACION -----------------------------------------
            # Los dos campos estan acoplados: el `max` del inicio se mueve con el
            # fin, y el `min` del fin se mueve con el inicio. Si la nueva fecha
            # de inicio es posterior al fin actual, sus dias salen deshabilitados.
            # Por eso decidimos el orden leyendo el valor actual del campo de fin.
            raw_end = page.locator(END_SEL).input_value().strip()
            try:
                current_end = datetime.strptime(raw_end, "%m/%d/%Y")
            except ValueError:
                current_end = None

            if current_end and start > current_end:
                pick_date(page, END_SEL,   end,   "Fecha final")
                pick_date(page, START_SEL, start, "Fecha inicial")
            else:
                pick_date(page, START_SEL, start, "Fecha inicial")
                pick_date(page, END_SEL,   end,   "Fecha final")

            # -- EMAIL --------------------------------------------------------
            email = page.locator(EMAIL_SEL)
            email.scroll_into_view_if_needed()
            default_email = email.input_value()
            email.click()
            email.fill("")                                  # limpia el valor por defecto
            email.press_sequentially(EMAIL, delay=30)       # dispara los eventos de Angular
            email.blur()

            final_email = email.input_value().strip()
            if final_email != EMAIL:
                raise RuntimeError(
                    f'El email no quedo bien: "{final_email}" (esperaba "{EMAIL}").')
            if email.evaluate("el => el.classList.contains('ng-invalid')"):
                raise RuntimeError(f'Angular marco "{EMAIL}" como invalido.')
            print(f"   OK Email: {default_email} -> {final_email}")

            # -- RUN REPORT ---------------------------------------------------
            # El boton se deshabilita si el formulario es invalido: esperar, no asumir.
            try:
                page.wait_for_function(
                    "sel => { const b = document.querySelector(sel); return b && !b.disabled; }",
                    arg=RUN_SEL, timeout=10_000)
            except PWTimeout:
                raise RuntimeError("El boton Run Report sigue deshabilitado: "
                                   "hay algun campo invalido en el formulario.")

            page.locator(RUN_SEL).click()
            page.wait_for_timeout(6_000)
            page.screenshot(path=f"report-{iso(datetime.now())}.png", full_page=True)
            print(f"\nLISTO: reporte enviado a {EMAIL} ({iso(start)} -> {iso(end)})")

            logout(page)

        except Exception as err:
            try:
                page.screenshot(path="error.png", full_page=True)
            except Exception:
                pass
            print(f"\nERROR: {err}\n   Screenshot: error.png", file=sys.stderr)
            logout(page)          # cerrar sesion aunque el reporte haya fallado
            browser.close()
            sys.exit(1)

        finally:
            browser.close()


if __name__ == "__main__":
    main()