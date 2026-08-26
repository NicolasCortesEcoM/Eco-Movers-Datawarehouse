
def login(page):
    page.goto(LOGIN_URL, wait_until="domcontentloaded")
    page.wait_for_selector("#emailAddress", timeout=30000)
    page.fill("#emailAddress", EMAIL)
    page.fill("#password", PASSWORD)
    page.click('button[data-test-id="sign-in-btn"]')
    # Espera a que salga de la pantalla de login (dashboard u otra ruta)
    page.wait_for_url(lambda url: "smartmoving.com" in url and "login" not in url.lower(), timeout=30000)
    time.sleep(2)
