#!/usr/bin/env python3
"""
Browser Share Script - Playwright Remote Debugging
Permite partilhar o browser localmente para acesso remoto via WebSocket

Uso:
    python scripts/browser-share.py start   # Inicia browser com remote debugging
    python scripts/browser-share.py status  # Verifica status
    python scripts/browser-share.py connect # Gera comando de conexão
"""

import subprocess
import sys
import json
import socket
from pathlib import Path
from datetime import datetime

REMOTE_PORT = 9222
DEBUG_DIR = Path.home() / ".openclaw" / "browser-debug"
DEBUG_DIR.mkdir(parents=True, exist_ok=True)

def get_local_ip():
    """Obtém IP local da máquina"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def start_browser():
    """Inicia Chromium com remote debugging"""
    print("🚀 A iniciar Chromium com remote debugging...")
    print(f"📁 Pasta de debug: {DEBUG_DIR}")
    print(f"🔌 Porta: {REMOTE_PORT}")
    print("")
    
    cmd = [
        "playwright", "run", "chromium",
        f"--remote-debugging-port={REMOTE_PORT}",
        f"--user-data-dir={DEBUG_DIR}/profile",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--disable-extensions-except=" + str(DEBUG_DIR),
        "--disable-features=TranslateUI",
        "--disable-component-extensions-with-background-pages",
        "--disable-background-networking",
        "--disable-sync",
        "--metrics-recording-list",
        "--no-first-run",
        "--safebrowsing-disable-auto-update",
    ]
    
    print(f"🌐 URL de debug local: http://localhost:{REMOTE_PORT}")
    print(f"🌍 URL de debug remoto: http://{get_local_ip()}:{REMOTE_PORT}")
    print("")
    print("⚠️  IMPORTANTE:")
    print("   1. O browser vai abrir numa janela separada")
    print("   2. Navega para os sites que queres verificar")
    print("   3. Faz login se necessário")
    print("   4. Deixa o browser aberto")
    print("   5. Noutra terminal, corre: python scripts/browser-share.py connect")
    print("")
    print("📋 Para parar o browser: Ctrl+C neste terminal")
    print("")
    
    try:
        subprocess.run(cmd, check=True)
    except KeyboardInterrupt:
        print("\n✅ Browser fechado!")
        sys.exit(0)
    except Exception as e:
        print(f"❌ Erro: {e}")
        sys.exit(1)

def check_status():
    """Verifica se o browser está a correr"""
    try:
        response = subprocess.run(
            ["curl", "-s", f"http://localhost:{REMOTE_PORT}/json/version"],
            capture_output=True, text=True, timeout=2
        )
        if response.returncode == 0:
            data = json.loads(response.stdout)
            print("✅ Browser está a correr!")
            print(f"   Versão: {data.get('Browser', 'Desconhecida')}")
            print(f"   Protocolo: {data.get('Protocol-Version', 'N/A')}")
            print(f"   URL: http://localhost:{REMOTE_PORT}")
            return True
        else:
            print("❌ Browser não está a correr")
            return False
    except Exception as e:
        print(f"❌ Browser não está acessível: {e}")
        return False

def generate_connect_command():
    """Gera comando para conectar ao browser remoto"""
    local_ip = get_local_ip()
    
    print("=" * 60)
    print("🔗 COMANDO PARA CONECTAR AO BROWSER")
    print("=" * 60)
    print("")
    print("Opção 1: Conexão Local (mesma máquina)")
    print("-" * 60)
    print(f"python scripts/browser-connect.py --url ws://localhost:{REMOTE_PORT}")
    print("")
    
    print("Opção 2: Conexão Remota (outra máquina na rede)")
    print("-" * 60)
    print(f"python scripts/browser-connect.py --url ws://{local_ip}:{REMOTE_PORT}")
    print("")
    print("⚠️  Para conexão remota:")
    print("   1. Certifica-te que a porta {REMOTE_PORT} está acessível na firewall")
    print(f"   2. No teu terminal: sudo ufw allow {REMOTE_PORT}/tcp")
    print("   3. Ou usa ngrok/tailscale para tunnel seguro")
    print("")
    
    print("Opção 3: Listar páginas disponíveis")
    print("-" * 60)
    print(f"curl http://localhost:{REMOTE_PORT}/json/list")
    print("")
    print("=" * 60)

def main():
    if len(sys.argv) < 2:
        print("Uso: python scripts/browser-share.py [start|status|connect]")
        print("")
        print("Comandos:")
        print("  start   - Inicia browser com remote debugging")
        print("  status  - Verifica se browser está a correr")
        print("  connect - Gera comando de conexão")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == "start":
        start_browser()
    elif command == "status":
        check_status()
    elif command == "connect":
        generate_connect_command()
    else:
        print(f"❌ Comando desconhecido: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
