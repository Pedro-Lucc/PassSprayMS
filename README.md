# ENUM MS Corporate — Spray Mode

> Ferramenta em **PowerShell** para **enumeração de contas** e **password spraying** contra tenants corporativos do **Microsoft Entra ID / Microsoft 365**, com suporte a **rotação de proxies autenticados**, controle de **sleep/jitter** e **janela de lockout**. Exporta todos os resultados para **planilhas Excel** organizadas por categoria.

Este repositório reúne dois componentes complementares:

| Componente | Arquivo | Função |
|---|---|---|
| **Ferramenta principal** | `enum_passs_spray.ps1` | Enumeração de usuários + password spraying no Microsoft 365 |
| **Infraestrutura de apoio** | Guia Squid (Vultr) | Provisionamento de um proxy privado autenticado para rotação de origem |

---

## ⚠️ Aviso Legal e de Uso Ético

Esta ferramenta destina-se **exclusivamente** a atividades **autorizadas** de teste de intrusão (*pentest*), *Red Team* e avaliações de segurança **com contrato/escopo formal assinado**.

- Utilize **somente** contra ambientes que você tem **permissão explícita e documentada** para testar.
- Password spraying pode causar **bloqueio de contas** e **alertas** no ambiente do cliente — alinhe **janelas de execução** e **thresholds de lockout** previamente.
- O uso não autorizado contra sistemas de terceiros é **ilegal** e de inteira responsabilidade do operador.

O autor e os contribuidores **não se responsabilizam** por qualquer uso indevido.

---

## ✨ Funcionalidades

- **Fase 1 — Enumeração:** identifica usuários **válidos/inválidos** via endpoint `GetCredentialType` e tenta detectar indícios de **MFA**.
- **Fase 2 — Password Spraying:** testa **uma senha por rodada** em **todos os usuários válidos** (modelo *low & slow*) antes de avançar para a próxima senha, reduzindo o risco de lockout.
- **Modo `-NoValidation`:** ignora a Fase 1 e trata **todos** os usuários da wordlist como alvos.
- **Rotação de proxies:** proxy único (`-Proxy`) ou lista com rotação aleatória (`-ProxyList`).
- **Autenticação de proxy:** usuário/senha explícitos, credenciais do Windows (NTLM/Kerberos) ou proxy aberto.
- **Controle de ritmo:** `-SleepMs` (timeout entre requisições), `-Jitter` (variação aleatória %) e `-SprayDelay` (pausa entre rodadas, respeitando a janela de lockout).
- **Classificação automática de resultados:** `LOGIN_OK`, `SENHA_INCORRETA`, `LOGIN_OK MAS MFA REQUERIDO`, `CONTA_BLOQUEADA`, `USUARIO_NAO_ENCONTRADO`, `ERRO`.
- **Exportação para Excel:** planilha geral + arquivos separados por categoria em `enum_resultados/`.

---

## 📦 Requisitos

- **Windows** com **PowerShell 5.1+** (ou PowerShell 7+).
- Módulos PowerShell (instalados automaticamente se ausentes):
  - `MSAL.PS`
  - `ImportExcel`
- Conectividade com `login.microsoftonline.com` (direta ou via proxy).

> O script tenta instalar os módulos com `Install-Module ... -Scope CurrentUser` na primeira execução.

---

## 🚀 Uso

```powershell
.\enum_passs_spray.ps1 -Domain <dominio> -UserList <arquivo> [opcoes]
```

### Parâmetros

| Parâmetro | Alias | Descrição |
|---|---|---|
| `-Domain <dominio>` | | Domínio alvo. Ex.: `empresa.onmicrosoft.com` |
| `-UserList <arquivo>` | | Arquivo com usuários, um por linha |
| `-PassList <arquivo>` | | Arquivo com senhas, uma por linha (padrão: `senhas.txt`) |
| `-TestLogin` | | Executa o password spraying nos usuários válidos |
| `-NoQuestion` | `-nq` | Não pergunta antes de iniciar o spray |
| `-NoValidation` | `-nv` | Pula a Fase 1 e faz spray em **todos** os usuários da wordlist |
| `-Proxy <url>` | | Usa um proxy único |
| `-ProxyList <url1>,<url2>` | | Usa um ou mais proxies com rotação |
| `-ProxyUseDefaultCredentials` | | Usa credenciais do Windows logado no proxy |
| `-ProxyUser <user>` | `-pu` | Usuário para proxy autenticado (basic/digest) |
| `-ProxyPassword <senha>` | `-pp` | Senha do proxy (se omitida, é solicitada de forma segura) |
| `-SleepMs <ms>` | `-s` | Timeout entre requisições (padrão: `500`) |
| `-Jitter <pct>` | `-j` | Variação aleatória (%) aplicada ao SleepMs. Ex.: `20` = ±20% |
| `-SprayDelay <min>` | `-sd` | Pausa (minutos) entre cada rodada de senha |
| `-Help` | `-h` | Mostra a ajuda |

### Modo de operação

**Password spraying:** o script testa **1 senha em todos os usuários válidos**, aguarda o `SprayDelay` e só então passa para a próxima senha — reduzindo o risco de lockout.
Com `-NoValidation`, a Fase 1 é ignorada e todos os usuários da wordlist vão direto para o spray.

### Exemplos

```powershell
# Apenas enumeração
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt

# Enumeração + spray sem confirmação
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq

# Spray com pausa de 30 min entre rodadas de senha
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq -SprayDelay 30

# Pula validação e faz spray em todos
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq -nv

# Ritmo controlado: 1500ms de sleep, ±20% jitter, 35 min entre rodadas
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq -s 1500 -j 20 -sd 35

# Com proxy único
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -Proxy "http://127.0.0.1:8080"

# Com lista de proxies autenticados (rotação)
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin `
  -ProxyList "http://1.2.3.4:3128","http://5.6.7.8:3128" -pu meu_usuario -pp 'MinhaSenha#123'
```

---

## 📊 Saída

Todos os resultados são exportados em **Excel**:

- `enum_ms_<timestamp>.xlsx` — planilha geral (abas **Resultados** e **Resumo**).
- Pasta `enum_resultados/` com arquivos segmentados:
  - `validos.xlsx`
  - `senha_incorreta.xlsx`
  - `mfa_requerido.xlsx`
  - `bloqueados.xlsx`
  - `outros.xlsx`
  - `resumo.xlsx`

### Interpretação dos códigos AADSTS

| Código | Significado | Status atribuído |
|---|---|---|
| `AADSTS50126` | Credencial inválida | `SENHA_INCORRETA` |
| `AADSTS50076` / `AADSTS50079` | Senha correta, mas **MFA requerido** | `LOGIN_OK MAS MFA REQUERIDO` |
| `AADSTS50053` | Conta bloqueada | `CONTA_BLOQUEADA` |
| `AADSTS50034` | Usuário não encontrado | `USUARIO_NAO_ENCONTRADO` |

---

## 🌐 Infraestrutura de Apoio — Proxy Privado (Squid na Vultr)

Para **rotacionar a origem** das requisições, é recomendável usar proxies **privados e autenticados**. O guia abaixo provisiona um **Squid Proxy** em uma VPS **Ubuntu (22.04/24.04 LTS)** da Vultr, com **autenticação obrigatória** por usuário/senha — evitando que o servidor se torne um *open proxy* (o que violaria as políticas da Vultr).

### 1. Atualizar o sistema e instalar dependências

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install squid apache2-utils -y
```

### 2. Criar a base de usuários

```bash
sudo htpasswd -c /etc/squid/passwords meu_utilizador
sudo chown proxy:proxy /etc/squid/passwords
sudo chmod 400 /etc/squid/passwords
```

### 3. Configurar o Squid

```bash
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
sudo nano /etc/squid/squid.conf
```

Substitua o conteúdo pelas diretivas abaixo:

```text
# Autenticação
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic children 5
auth_param basic realm Proxy Privado Vultr
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive on

# Regras de acesso
acl utilizadores_autenticados proxy_auth REQUIRED

# Portas seguras
acl Safe_ports port 80          # http
acl Safe_ports port 443         # https
http_access deny !Safe_ports

# Permitir apenas autenticados
http_access allow utilizadores_autenticados
http_access deny all

# Porta de escuta
http_port 3128

# Privacidade (oculta IP de origem)
forwarded_for delete
via off
```

### 4. Validar e iniciar

```bash
sudo squid -k parse
sudo systemctl restart squid
sudo systemctl enable squid
```

### 5. Firewall

```bash
sudo ufw allow 3128/tcp
```

> ⚠️ **Painel Web Vultr:** se houver um *Firewall Group* associado à VPS, adicione uma regra **Inbound TCP** na porta `3128`.

### 6. Testar o proxy

```bash
curl -U "meu_utilizador:sua_palavra_passe" -x http://IP_DO_SERVIDOR:3128 https://ifconfig.me
```

**Troubleshooting:**
- **Sucesso:** retorna o IP da VPS.
- **Erro 407:** credenciais incorretas ou Squid sem acesso a `/etc/squid/passwords`.
- **Connection refused / Timed out:** porta `3128` bloqueada no firewall ou serviço parado (`sudo systemctl status squid`).

Uma vez ativo, o proxy pode ser usado diretamente no script:

```powershell
.\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin `
  -Proxy "http://IP_DO_SERVIDOR:3128" -pu meu_utilizador -pp 'sua_palavra_passe'
```

---

## 🗂️ Estrutura do Repositório

```
.
├── enum_passs_spray.ps1     # Ferramenta principal (enumeração + spray)
├── users.txt                # Wordlist de usuários (exemplo)
├── senhas.txt               # Wordlist de senhas (exemplo)
├── enum_resultados/         # Saídas por categoria (gerado em runtime)
└── README.md
```

---

## 🤝 Contribuições

Sugestões, correções e melhorias são bem-vindas via *issues* e *pull requests*.

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo `LICENSE` para mais detalhes.
