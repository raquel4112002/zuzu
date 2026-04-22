#!/usr/bin/env python3
"""
Browser Connect Script - Conecta ao browser remoto via Playwright
Permite controlar o browser partilhado

Uso:
    python scripts/browser-connect.py --url ws://localhost:9222
    python scripts/browser-connect.py --url ws://192.168.1.100:9222
"""

import argparse
import asyncio
import json
import requests
from playwright.async_api import async_playwright

async def connect_to_browser(ws_endpoint):
    """Conecta ao browser remoto e lista páginas abertas"""
    print(f"🔗 A conectar a: {ws_endpoint}")
    
    async with async_playwright() as p:
        try:
            browser = await p.chromium.connect_over_cdp(ws_endpoint)
            print("✅ Conectado com sucesso!")
            print("")
            
            # Listar contexts/páginas
            contexts = browser.contexts
            print(f"📑 Contextos ativos: {len(contexts)}")
            
            for i, context in enumerate(contexts):
                pages = context.pages
                print(f"\n   Contexto {i+1}:")
                for j, page in enumerate(pages):
                    try:
                        title = await page.title()
                        url = page.url
                        print(f"      [{j+1}] {title[:50]}...")
                        print(f"          {url[:60]}...")
                    except Exception as e:
                        print(f"      [{j+1}] Página (erro ao obter info: {e})")
            
            print("")
            print("🎯 Comandos disponíveis:")
            print("   - screenshot: Tira screenshot da página ativa")
            print("   - navigate <url>: Navega para URL")
            print("   - list: Lista páginas novamente")
            print("   - quit: Sai")
            print("")
            
            # Manter conexão ativa
            while True:
                cmd = input("browser> ").strip().lower()
                
                if cmd == "quit" or cmd == "exit":
                    print("👋 A desconectar...")
                    await browser.close()
                    break
                elif cmd == "list":
                    for i, context in enumerate(browser.contexts):
                        print(f"\n   Contexto {i+1}:")
                        for j, page in enumerate(context.pages):
                            try:
                                title = await page.title()
                                url = page.url
                                print(f"      [{j+1}] {title[:50]}")
                                print(f"          {url[:60]}")
                            except Exception as e:
                                print(f"      [{j+1}] Página")
                elif cmd.startswith("navigate ") or cmd.startswith("go "):
                    url = cmd.split(" ", 1)[1]
                    page = browser.contexts[0].pages[0] if browser.contexts and browser.contexts[0].pages else None
                    if page:
                        print(f"🌐 A navegar para: {url}")
                        await page.goto(url)
                        print(f"✅ Título: {await page.title()}")
                    else:
                        print("❌ Sem páginas abertas")
                elif cmd == "screenshot":
                    page = browser.contexts[0].pages[0] if browser.contexts and browser.contexts[0].pages else None
                    if page:
                        path = "/tmp/browser-screenshot.png"
                        await page.screenshot(path=path)
                        print(f"📸 Screenshot guardada em: {path}")
                    else:
                        print("❌ Sem páginas abertas")
                else:
                    print(f"❌ Comando desconhecido: {cmd}")
                    
        except Exception as e:
            print(f"❌ Erro ao conectar: {e}")
            print("")
            print("Possíveis causas:")
            print("   1. Browser não está a correr")
            print("   2. URL/Porta incorretos")
            print("   3. Firewall a bloquear")
            print("")
            print("Para iniciar o browser:")
            print("   python scripts/browser-share.py start")

def get_ws_endpoint(http_url):
    """Obtém WebSocket URL da HTTP API"""
    try:
        response = requests.get(f"{http_url}/json/version", timeout=5)
        if response.status_code == 200:
            data = response.json()
            ws_url = data.get("webSocketDebuggerUrl")
            if ws_url:
                return ws_url
    except Exception as e:
        print(f"⚠️  Não consegui obter WebSocket URL automaticamente: {e}")
    
    # Fallback: construir URL manualmente
    if http_url.startswith("http://"):
        host = http_url[7:].rstrip("/")
        return f"ws://{host}/devtools/browser/"
    return None

def main():
    parser = argparse.ArgumentParser(description="Conectar ao browser remoto")
    parser.add_argument("--url", required=True, help="URL do browser (http://IP:PORT ou ws://IP:PORT)")
    args = parser.parse_args()
    
    url = args.url
    
    # Converter HTTP para WebSocket se necessário
    if url.startswith("http://"):
        print("🔄 A obter WebSocket URL...")
        ws_url = get_ws_endpoint(url)
        if ws_url:
            url = ws_url
            print(f"✅ WebSocket URL: {url}")
        else:
            print("⚠️  A usar URL manual. Pode não funcionar.")
            url = url.replace("http://", "ws://") + "/devtools/browser/"
    
    asyncio.run(connect_to_browser(url))

if __name__ == "__main__":
    main()
