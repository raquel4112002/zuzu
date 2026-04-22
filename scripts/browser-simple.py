#!/usr/bin/env python3
"""
Browser Share - Versão Simplificada
Inicia Chromium com remote debugging para partilha
"""

from playwright.sync_api import sync_playwright
import time
import socket

REMOTE_PORT = 9222
DEBUG_DIR = "/home/raquel/.openclaw/browser-debug/profile"

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

print("🚀 A iniciar Chromium com remote debugging...")
print(f"📁 Pasta de perfil: {DEBUG_DIR}")
print(f"🔌 Porta CDP: {REMOTE_PORT}")
print("")

try:
    with sync_playwright() as p:
        browser = p.chromium.launch_persistent_context(
            user_data_dir=DEBUG_DIR,
            headless=False,
            args=[
                f"--remote-debugging-port={REMOTE_PORT}",
                "--no-first-run",
                "--no-default-browser-check",
                "--disable-dev-shm-usage",
                "--disable-gpu",
            ],
            timeout=60000,
        )
        
        print(f"✅ Browser iniciado!")
        print(f"🌐 Debug URL local: http://localhost:{REMOTE_PORT}")
        print(f"🌍 Debug URL remoto: http://{get_local_ip()}:{REMOTE_PORT}")
        print("")
        print("⚠️  INSTRUÇÕES:")
        print("   1. O browser abriu - navega para os sites")
        print("   2. Tenta password reset em cada site")
        print("   3. Quando estiveres pronto, diz 'podes conectar'")
        print("   4. Eu vou conectar e ver os resultados")
        print("")
        print("📋 Para fechar: Ctrl+C")
        print("")
        
        # Manter aberto
        page = browser.pages[0] if browser.pages else None
        if page:
            page.goto("about:blank")
        
        while True:
            time.sleep(1)
            
except KeyboardInterrupt:
    print("\n✅ Browser fechado!")
except Exception as e:
    print(f"❌ Erro: {e}")
    import traceback
    traceback.print_exc()
