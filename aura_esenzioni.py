"""
Interrogazione delle esenzioni da reddito tramite portale Sistema Tessera Sanitaria.

Nota operativa:
- Questo script NON interroga AURA Piemonte.
- Usa il form HTML di Sistema TS: /EsenzioniRedditoMedici/riepilogo.do
- Richiede una sessione già autenticata. In assenza dei cookie di sessione del portale,
  la richiesta restituirà una pagina di login, un redirect o un errore applicativo.

Uso consigliato:
1. Accedi manualmente a Sistema TS con il browser.
2. Recupera i cookie di sessione necessari dagli strumenti sviluppatore del browser.
3. Inseriscili nella variabile d'ambiente SISTEMA_TS_COOKIE.
4. Esegui lo script passando il codice fiscale del paziente.

Esempio:
    export SISTEMA_TS_COOKIE='JSESSIONID=...; altri_cookie=...'
    python aura_esenzioni.py RSSMRA85M01H501Z
"""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from http.cookies import SimpleCookie

import requests
from bs4 import BeautifulSoup


SISTEMA_TS_BASE_URL = "https://sistemats4.sanita.finanze.it"
INTERROGAZIONE_URL = (
    f"{SISTEMA_TS_BASE_URL}/EsenzioniRedditoMedici/interrogazione.do?navbar=1"
)
RIEPILOGO_URL = f"{SISTEMA_TS_BASE_URL}/EsenzioniRedditoMedici/riepilogo.do"


@dataclass(frozen=True)
class EsenzioneRedditoResult:
    codice_fiscale: str
    testo_pagina: str
    html: str


def is_valid_codice_fiscale(value: str) -> bool:
    """Valida in modo formale un codice fiscale italiano di 16 caratteri."""
    return bool(re.fullmatch(r"[A-Z0-9]{16}", value.strip().upper()))


def load_cookie_header_from_env() -> str:
    """Legge i cookie di sessione dalla variabile d'ambiente SISTEMA_TS_COOKIE."""
    cookie_header = os.getenv("SISTEMA_TS_COOKIE", "").strip()
    if not cookie_header:
        raise RuntimeError(
            "Variabile d'ambiente SISTEMA_TS_COOKIE non impostata. "
            "Serve una sessione autenticata di Sistema TS."
        )
    return cookie_header


def session_from_cookie_header(cookie_header: str) -> requests.Session:
    """Crea una sessione requests popolata con i cookie esportati dal browser."""
    session = requests.Session()
    parsed = SimpleCookie()
    parsed.load(cookie_header)

    for morsel in parsed.values():
        session.cookies.set(
            morsel.key,
            morsel.value,
            domain="sistemats4.sanita.finanze.it",
            path="/",
        )

    return session


def assert_probably_authenticated(html: str) -> None:
    """
    Intercetta i casi più probabili di sessione non valida.

    Non è una garanzia assoluta: Sistema TS può cambiare markup o flussi SSO.
    """
    lowered = html.lower()
    markers = (
        "login",
        "autenticazione",
        "accesso",
        "sessione scaduta",
        "sessione non valida",
        "spid",
        "cns",
    )
    if any(marker in lowered for marker in markers) and "ricerca assistito esente" not in lowered:
        raise RuntimeError(
            "La risposta sembra una pagina di login/sessione scaduta. "
            "Aggiorna SISTEMA_TS_COOKIE dopo avere effettuato nuovamente l'accesso."
        )


def extract_readable_text(html: str) -> str:
    """Estrae testo leggibile dall'HTML di risposta."""
    soup = BeautifulSoup(html, "html.parser")

    for tag in soup(["script", "style", "noscript"]):
        tag.decompose()

    lines = [line.strip() for line in soup.get_text("\n").splitlines()]
    return "\n".join(line for line in lines if line)


def interroga_esenzioni_reddito(codice_fiscale: str) -> EsenzioneRedditoResult:
    """Invia la POST al riepilogo Sistema TS e restituisce HTML e testo estratto."""
    codice_fiscale = codice_fiscale.strip().upper()
    if not is_valid_codice_fiscale(codice_fiscale):
        raise ValueError(f"Codice fiscale non valido: {codice_fiscale!r}")

    session = session_from_cookie_header(load_cookie_header_from_env())

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "it-IT,it;q=0.9,en;q=0.8",
        "Content-Type": "application/x-www-form-urlencoded",
        "Origin": SISTEMA_TS_BASE_URL,
        "Referer": INTERROGAZIONE_URL,
    }

    payload = {
        "codiceFiscale": codice_fiscale,
    }

    response = session.post(
        RIEPILOGO_URL,
        data=payload,
        headers=headers,
        timeout=30,
        allow_redirects=True,
    )
    response.raise_for_status()

    html = response.text
    assert_probably_authenticated(html)

    return EsenzioneRedditoResult(
        codice_fiscale=codice_fiscale,
        testo_pagina=extract_readable_text(html),
        html=html,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Interroga Sistema TS per le esenzioni da reddito di un assistito."
    )
    parser.add_argument(
        "codice_fiscale",
        help="Codice fiscale dell'assistito da interrogare.",
    )
    parser.add_argument(
        "--salva-html",
        metavar="FILE",
        help="Salva l'HTML grezzo della risposta in un file locale.",
    )
    args = parser.parse_args()

    result = interroga_esenzioni_reddito(args.codice_fiscale)

    print("=" * 80)
    print(f"Risultato interrogazione Sistema TS per: {result.codice_fiscale}")
    print("=" * 80)
    print(result.testo_pagina)

    if args.salva_html:
        with open(args.salva_html, "w", encoding="utf-8") as file:
            file.write(result.html)
        print(f"\nHTML salvato in: {args.salva_html}")


if __name__ == "__main__":
    main()