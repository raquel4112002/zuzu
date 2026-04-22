# 🌐 Browser Share - Guia de Utilização

Partilha o teu browser local para o Zuzu controlar remotamente via Playwright.

---

## 🚀 Quick Start

### Passo 1: Iniciar Browser Partilhado

```bash
cd /home/raquel/.openclaw/workspace
python scripts/browser-share.py start
```

**O que vai acontecer:**
- O Chromium abre numa janela separada
- Remote debugging ativo na porta `9222`
- Podes navegar normalmente neste browser

---

### Passo 2: Navegar para os Sites

No browser que abriu:

1. **Vai para os sites que queres verificar:**
   - `https://twitter.com/i/flow/password_reset`
   - `https://discord.com/login`
   - `https://cracked.to/member.php?action=lostpw`
   - etc.

2. **Tenta password reset** em cada site

3. **Observa a resposta:**
   - ✅ "Email enviado" → Conta existe
   - ❌ "Email não encontrado" → Conta não existe
   - ⚠️ Captcha/Rate limit → Inconclusivo

4. **Deixa o browser aberto** enquanto o Zuzu se conecta

---

### Passo 3: Conectar ao Browser

**Opção A: Tu conectas e partilhas info**

```bash
# Noutro terminal
python scripts/browser-share.py connect
```

Isto mostra o WebSocket URL. Depois:

```bash
python scripts/browser-connect.py --url ws://localhost:9222
```

**Opção B: Zuzu conecta remotamente**

Dás-me o output de:
```bash
python scripts/browser-share.py connect
```

E eu uso o comando para conectar remotamente!

---

## 📋 Comandos Disponíveis

### No browser-connect.py:

```
browser> list          # Lista todas as páginas abertas
browser> screenshot    # Tira screenshot da página ativa
browser> navigate URL  # Navega para URL específico
browser> quit          # Fecha conexão
```

### No browser-share.py:

```bash
python scripts/browser-share.py start   # Inicia browser
python scripts/browser-share.py status  # Verifica se está a correr
python scripts/browser-share.py connect # Gera comando de conexão
```

---

## 🔍 Verificação Automática de Sites

Depois de conectado, podes correr:

```bash
# Exemplo: verificar password reset no Twitter
browser> navigate https://twitter.com/i/flow/password_reset

# Depois preenches manualmente o email e tentas reset

# Tira screenshot do resultado
browser> screenshot
```

Screenshots ficam em: `/tmp/browser-screenshot.png`

---

## 🌍 Conexão Remota (Rede Local)

Se queres que o Zuzu aceda de outra máquina:

### 1. Descobre teu IP local:
```bash
hostname -I
# ou
ip addr show | grep inet
```

### 2. Abre porta na firewall:
```bash
sudo ufw allow 9222/tcp
```

### 3. Gera comando de conexão:
```bash
python scripts/browser-share.py connect
```

Vai mostrar algo como:
```
python scripts/browser-connect.py --url ws://192.168.1.100:9222
```

### 4. Partilha este comando comigo!

---

## 🔒 Segurança

### Riscos:
- Quem conecta tem **acesso total** ao browser
- Pode ver **todos os cookies/sessões**
- Pode navegar como se fosses tu

### Proteções:
- ✅ Usa apenas em **rede local confiável**
- ✅ **Não uses** com WiFi público
- ✅ **Fecha o browser** quando acabares
- ✅ Para produção: usa **ngrok/tailscale** com autenticação

### Para tunnel seguro (avançado):

```bash
# Instalar ngrok
sudo snap install ngrok

# Criar tunnel seguro
ngrok http 9222 --basic-auth "zuzu:password123"
```

Isto dá-te um URL público com password!

---

## 🐛 Troubleshooting

### "Browser não está a correr"
```bash
# Verifica status
python scripts/browser-share.py status

# Se não estiver, inicia
python scripts/browser-share.py start
```

### "Connection refused"
- Verifica se a porta 9222 está livre: `netstat -tlnp | grep 9222`
- Verifica firewall: `sudo ufw status`
- Tenta localhost: `curl http://localhost:9222/json/version`

### "Cannot connect to WebSocket"
- O browser pode estar bloqueado por firewall
- Tenta desativar temporariamente: `sudo ufw disable`
- Ou usa tunnel: `ngrok http 9222`

### Browser abre e fecha imediatamente
- Pode haver conflito com Chrome já aberto
- Fecha todo o Chrome/Chromium primeiro
- Ou usa perfil diferente: edita `DEBUG_DIR` no script

---

## 📊 Exemplo de Sessão Completa

```bash
# Terminal 1: Iniciar browser
python scripts/browser-share.py start
# Browser abre...

# Terminal 2: Conectar
python scripts/browser-connect.py --url ws://localhost:9222
# Conectado!

# No prompt do browser-connect:
browser> list
# Mostra páginas abertas

browser> navigate https://instagram.com/login/forgot
# Navega para Instagram password reset

# [Preenches email manualmente no browser]
# [Vês o resultado]

browser> screenshot
# Guarda screenshot em /tmp/browser-screenshot.png

browser> navigate https://discord.com/login
# Próximo site...

browser> quit
# Fecha conexão
```

---

## 📝 Notas

- **Perfil do browser:** `~/.openclaw/browser-debug/profile/`
- **Screenshots:** `/tmp/browser-screenshot.png`
- **Logs:** Output no terminal

---

## 🎯 Próximos Passos

1. **Inicia o browser:**
   ```bash
   python scripts/browser-share.py start
   ```

2. **Navega para os sites da lista** e tenta password reset

3. **Conecta-te** para veres os resultados:
   ```bash
   python scripts/browser-connect.py --url ws://localhost:9222
   ```

4. **Partilha comigo** o output ou screenshots!

---

*Guia criado por Zuzu 🐱‍💻*
