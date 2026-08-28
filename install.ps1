# Dead Air x64 — установка и обновление поверх чистой версии.
#
# Кладётся в папку с игрой (туда, где database и fsgame.ltx) и запускается.
# Первый запуск ставит x64-версию, каждый следующий — обновляет её до актуальной.
#
# Что качается: bin (модули движка) из GitHub Releases и gamedata из репозитория.
# Архивы игры (10 ГБ) НЕ качаются — они одинаковы в оригинале и в x64-версии,
# сверено по размерам всех четырнадцати.
#
# Обновление УБИРАЕТ за собой: файлы, которые мы ставили раньше, а в новой сборке их
# больше нет, удаляются. Иначе у игрока копился бы мусор из прошлых версий — а лишний
# скрипт или шейдер ломает игру не хуже недостающего. Что именно поставлено, помнит
# манифест; файлы, которых в нём нет, не трогаются никогда — это чужое.

$ErrorActionPreference = 'Stop'

# --- СОВМЕСТИМОСТЬ СО СТАРЫМИ WINDOWS -------------------------------------------------------
# GitHub принимает только TLS 1.2, а Windows 7 и ранние сборки Windows 10 по умолчанию
# предлагают TLS 1.0 — соединение обрывается ещё до запроса, с невнятной ошибкой.
# Ставим протокол явно; на системах, где Tls12 недоступен вовсе, просто идём дальше и
# честно скажем об этом при неудачной загрузке.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Своя полоса прогресса рисуется ниже, встроенная только мешает.
$ProgressPreference = 'SilentlyContinue'

# Windows 7 из коробки идёт с PowerShell 2.0, где нет ни Invoke-WebRequest, ни распаковки.
# Проверяем сразу: лучше понятное сообщение в начале, чем непонятная ошибка в середине.
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host ''
    Write-Host '  Нужен PowerShell версии 3.0 или новее.' -ForegroundColor Red
    Write-Host "  У вас: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host ''
    Write-Host '  На Windows 7 он ставится обновлением Windows Management Framework:'
    Write-Host '  https://www.microsoft.com/download/details.aspx?id=54616'
    Write-Host ''
    Read-Host 'Enter — выход'
    exit 1
}

# --- ВЫВОД --------------------------------------------------------------------------------
# Определения стоят ЗДЕСЬ, а не ниже, и это не вкусовщина. PowerShell выполняет файл сверху вниз,
# и функция существует только после того, как строка с её определением выполнена. Пока они лежали
# ниже блока ключа доступа, обработчик негодного ключа звал Say, которого ещё не было: вместо
# «продолжаю без ключа» человек получал CommandNotFoundException, а поскольку внешнего try нет и
# $ErrorActionPreference = 'Stop', установка обрывалась насмерть. То есть спасательная ветка,
# написанная РАДИ тех, у кого остался протухший da_token.txt, ломала установку именно у них.
function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Size($bytes) {
    if ($bytes -ge 1073741824) { '{0:n2} ГБ' -f ($bytes / 1073741824) }
    else                       { '{0:n0} МБ' -f ($bytes / 1048576) }
}
function Speed($bps) {
    if ($bps -ge 1048576) { '{0:n1} МБ/с' -f ($bps / 1048576) }
    else                  { '{0:n0} КБ/с' -f ($bps / 1024) }
}
function Left($sec) {
    if ($sec -ge 3600) { '{0:n0} ч {1:n0} мин' -f [math]::Floor($sec/3600), (($sec % 3600)/60) }
    elseif ($sec -ge 60) { '{0:n0} мин' -f [math]::Ceiling($sec/60) }
    else { '{0:n0} сек' -f $sec }
}
function Fail($text) { Say ''; Say "ОШИБКА: $text" 'Red'; Say ''; Read-Host 'Enter — выход'; exit 1 }

# --- КУДА СМОТРЕТЬ ------------------------------------------------------------------------
$Owner  = 'DeadAir-x64'
$Repo   = 'DeadAir-x64-Update'
$Branch = 'main'

# --- КЛЮЧ ДОСТУПА (больше не нужен) ---------------------------------------------------------
# Сборка открыта, и для загрузки ничего не требуется. Поддержка ключа оставлена на случай, если
# репозиторий когда-нибудь снова закроют: положите рядом файл `da_token.txt`, и он подхватится.
#
# ⚠️ Без ключа GitHub считает запросы по адресу и пускает 60 штук в час. Установщик делает три,
# так что упереться в это можно только из-за общего адреса на всю сеть - об этом и говорит
# сообщение об ошибке ниже.
$Token = ''

if (-not $Token) {
    $tokenFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'da_token.txt'
    if (Test-Path $tokenFile) { $Token = (Get-Content $tokenFile -Raw).Trim() }
}

$GhHeaders = @{ 'User-Agent' = 'DeadAir-x64-Updater' }
if ($Token) { $GhHeaders['Authorization'] = "Bearer $Token" }

# Негодный ключ НЕ должен мешать: репозиторий открытый, и без ключа всё качается.
#
# 16.08.2026 у тестеров истёк ключ, розданный вместе со сборкой, и установщик вставал намертво с
# 401 — хотя всё, что ему нужно, доступно и без авторизации. Объяснять это текстом бесполезно:
# человек уже упёрся в ошибку. Проверяем ключ одним дешёвым запросом и, если он не подошёл,
# молча продолжаем без него.
if ($Token) {
    try {
        $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo" `
            -Headers $GhHeaders -TimeoutSec 20
    } catch {
        $GhHeaders.Remove('Authorization') | Out-Null
        $Token = ''
        Say '  Ключ доступа не подошёл — продолжаю без него (сборка открытая).' 'DarkGray'
    }
}

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Work      = Join-Path $env:TEMP 'da_x64_update'
$StampFile = Join-Path $Root 'appdata\da_x64_version.txt'
$Manifest  = Join-Path $Root 'appdata\da_x64_files.txt'

Say ''
Say '  Dead Air x64 — установка и обновление' 'Cyan'
Say '  ------------------------------------' 'Cyan'
Say ''

# --- 1. Это вообще Dead Air? --------------------------------------------------------------
if (-not (Test-Path (Join-Path $Root 'database\levels.xdb0'))) {
    Fail @"
Рядом со скриптом нет папки database с архивами игры.
Положите этот файл в корень установленной Dead Air — туда, где лежат
fsgame.ltx и папка database, — и запустите ещё раз.
"@
}
if (Get-Process xrEngine -ErrorAction SilentlyContinue) {
    Fail 'Игра запущена. Закройте её и запустите установку заново.'
}

# --- 2. Летний архив ----------------------------------------------------------------------
# Лето в Dead Air — это архив xtra_green.xdb0. В оригинальной установке он лежит НЕ в database,
# а в отдельной папке «Летняя растительность (опционально)»: автор оставил его на усмотрение
# игрока, и переносить его надо было руками.
#
# В x64 сезон переключается прямо в настройках игры, и переключатель смотрит только на database.
# Значит у того, кто архив не переносил, выбор «лето» не делал ровно ничего — и молча: меню
# соглашалось, а трава оставалась осенней. Именно на это и пожаловались с закрытого теста.
#
# Поэтому переносим архив сами. Само по себе его присутствие сезон не меняет: подключать его или
# нет решает признак в da_season.txt. Признак пишем осенним — то есть внешне не меняется ничего,
# но переключатель в меню начинает работать.
#
# Ищем по имени файла, а не по имени папки: у разных раздач она называется по-разному.
$seasonArchive = Join-Path $Root 'database\xtra_green.xdb0'
$seasonMarker = Join-Path $Root 'database\da_season.txt'

if (-not (Test-Path $seasonArchive)) {
    $databaseDir = Join-Path $Root 'database'
    $spare = Get-ChildItem $Root -Recurse -Filter 'xtra_green.xdb0' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -ne $databaseDir } | Select-Object -First 1

    if ($spare) {
        Say '  Переношу летний архив в database — без него сезон в настройках не работает...'
        try {
            Move-Item $spare.FullName $seasonArchive -Force
            if (-not (Test-Path $seasonMarker)) {
                # ASCII и без -NoNewline: тот появился только в PowerShell 5.0, а нам нужен и 3.0.
                [System.IO.File]::WriteAllText(
                    $seasonMarker, 'autumn', (New-Object System.Text.ASCIIEncoding))
            }
            Say '  Сезон теперь переключается в настройках игры (применяется после перезапуска).' 'DarkGray'
        } catch {
            Say "  ! не удалось перенести летний архив: $($_.Exception.Message)" 'DarkYellow'
            Say '    Перенесите xtra_green.xdb0 в папку database вручную.' 'DarkYellow'
        }
    }
}

# --- 3. Что уже стоит ----------------------------------------------------------------------
$installed = if (Test-Path $StampFile) { (Get-Content $StampFile -Raw).Trim() } else { '' }
$oldFiles  = if (Test-Path $Manifest) { @(Get-Content $Manifest | Where-Object { $_.Trim() }) } else { @() }

if ($installed) {
    Say "  Установлено сейчас: $installed"
    if ($oldFiles.Count) { Say "  Файлов от прошлой установки: $($oldFiles.Count)" 'DarkGray' }
} else {
    Say '  Версия x64 ещё не ставилась — будет первая установка.'
}

# --- 4. Узнаём актуальную версию -----------------------------------------------------------
Say '  Смотрю, что доступно...'
try {
    $api = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $rel = Invoke-RestMethod -Uri $api -Headers $GhHeaders -TimeoutSec 30
} catch {
    $hint = if ($Token) {
        'Ключ доступа не подошёл — возможно, он отозван или истёк. Он больше не обязателен: попробуйте удалить da_token.txt и запустить снова.'
    } else {
        'Похоже на обрыв связи. Если у вас общий адрес на всю сеть (общежитие, офис), GitHub мог временно ограничить запросы — попробуйте через час.'
    }
    Fail @"
Не удалось получить данные с GitHub.
$hint

Подробности: $($_.Exception.Message)
"@
}

$latest = $rel.tag_name
if (-not $latest) { Fail 'В репозитории пока нет ни одного выпуска.' }

# --- ОБНОВЛЕНИЕ САМОГО УСТАНОВЩИКА ----------------------------------------------------------
#
# ⛔ Установщик раскладывает bin и gamedata — себя он не обновлял НИКОГДА. У человека,
# поставившего сборку однажды, install.ps1 оставался тем же навсегда: все последующие правки
# самого установщика — докачка, полоса прогресса, внятные ошибки — до него не доезжали.
#
# Проверяем ДО выхода по «версия та же»: иначе те, кто уже на свежей сборке, не получили бы
# новый установщик вовсе — а это как раз те, кто обновляется регулярно.
#
# Берём файлы напрямую из репозитория, а не из архива с игровыми файлами: архив весит десятки
# мегабайт и качается только когда есть что ставить, а тут нужно 35 КБ и каждый запуск.
# Короткий файл с ЖЁСТКИМ ограничением по времени.
#
# ⛔ Здесь стоял Net.WebClient.DownloadData, у которого таймаут задать нечем. Это был
# единственный сетевой вызов во всём установщике без ограничения по времени — и он же
# единственный, кто ходил на raw.githubusercontent.com. Когда провайдер режет этот адрес
# по DPI, соединение не отвергается, а виснет: у человека установщик замирал сразу после
# «Смотрю, что доступно...» и не отмирал никогда.
#
# ⚠️ Accept и User-Agent — ограниченные заголовки: через .Headers они БРОСАЮТ исключение,
# и ошибка кода прикидывается обрывом связи. Ставятся только свойствами.
function Get-Small($url, $headers, $accept, $timeoutMs) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = 'DeadAir-x64-Updater'
    if ($accept) { $req.Accept = $accept }
    $req.Timeout = $timeoutMs
    $req.ReadWriteTimeout = $timeoutMs
    if ($headers) {
        foreach ($k in $headers.Keys) {
            if ($k -ne 'User-Agent' -and $k -ne 'Accept') { $req.Headers[$k] = $headers[$k] }
        }
    }
    $resp = $req.GetResponse()
    try {
        $ms = New-Object IO.MemoryStream
        $st = $resp.GetResponseStream()
        $buf = New-Object byte[] 16384
        while (($n = $st.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
        $ms.ToArray()
    } finally { $resp.Close() }
}

function Update-Self {
    $names = @('install.ps1', 'Обновление.cmd', 'Установить Dead Air x64.cmd')
    $done = 0
    $failed = 0
    foreach ($name in $names) {
        $enc = [Uri]::EscapeDataString($name)
        # Порядок именно такой, и он проверен побайтово.
        #
        # ⛔ api.github.com отдаёт содержимое ПЕРЕКОДИРОВАННЫМ: читает файл как текст и выдаёт
        # UTF-8. Оба .cmd лежат в CP866 — иначе cmd.exe покажет кракозябры вместо русского —
        # и через API приезжают раздутыми и испорченными: 338 байт превращаются в 505.
        # Записать такое человеку значит сломать ему ярлыки, да ещё при КАЖДОМ запуске:
        # отличие от настоящего файла никуда не денется. В форме base64 то же самое —
        # перекодирование происходит на стороне GitHub, а не при отдаче.
        #
        # Поэтому основной путь — raw.githubusercontent, он байт в байт. API оставлен
        # запасным ТОЛЬКО для install.ps1: он в UTF-8, перекодировать там нечего
        # (сверено: 42831 байт обоими путями, различий нет).
        $tries = @( @{ url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/$enc"; accept = $null } )
        if ($name -eq 'install.ps1') {
            $tries += @{ url = "https://api.github.com/repos/$Owner/$Repo/contents/$($enc)?ref=$Branch"
                         accept = 'application/vnd.github.raw' }
        }
        $fresh = $null
        foreach ($t in $tries) {
            try { $fresh = Get-Small $t.url $GhHeaders $t.accept 10000; break } catch { }
        }
        if (-not $fresh) {
            # Если не доехал ПЕРВЫЙ файл, до GitHub сейчас не достучаться вовсе.
            # Дальше пробовать нечего: это ещё две задержки на ровном месте.
            $failed++
            if ($failed -eq 1 -and $name -eq 'install.ps1') { break }
            continue
        }
        if ($fresh.Length -lt 100) { continue }

        $dst = Join-Path $Root $name
        $differs = $true
        if (Test-Path $dst) {
            $have = [IO.File]::ReadAllBytes($dst)
            $differs = ($have.Length -ne $fresh.Length)
            if (-not $differs) {
                for ($i = 0; $i -lt $fresh.Length; $i++) { if ($have[$i] -ne $fresh[$i]) { $differs = $true; break } }
            }
        }
        if ($differs) {
            # Пишем во временный файл и подменяем: оборвись запись на середине, у человека
            # останется рабочий старый установщик, а не половина нового.
            try {
                $tmp = "$dst.new"
                [IO.File]::WriteAllBytes($tmp, $fresh)
                Move-Item $tmp $dst -Force
                $done++
            } catch { }
        }
    }
    if ($done -gt 0) { Say '  Обновил сам установщик — со следующего запуска будет новее.' 'DarkGray' }
}

Say '  Проверяю обновление самого установщика...' 'DarkGray'
Update-Self

if ($installed -eq $latest) {
    Say ''
    Say "  У вас уже актуальная версия ($latest). Обновлять нечего." 'Green'
    Say ''
    Read-Host 'Enter — выход'
    exit 0
}

Say "  Доступна: $latest" 'Yellow'
Say ''

$asset = $rel.assets | Where-Object { $_.name -like 'bin*.zip' } | Select-Object -First 1
if (-not $asset) { Fail "В выпуске $latest нет файла bin*.zip — сообщите об этом автору сборки." }

# --- ЗАГРУЗКА ФАЙЛА -------------------------------------------------------------------------
# Своя загрузка вместо Invoke-WebRequest -OutFile, и вот почему.
#
# Первое: молчание. Invoke-WebRequest ничего не показывает, пока файл не доедет целиком.
# На медленном канале это выглядит как зависший установщик — замерено на живой сети,
# 79 МБ ехали одиннадцать минут при 70 КБ/с. Человек в такой тишине закрывает окно
# и идёт жаловаться, хотя всё работало. Показываем сколько скачано, с какой скоростью
# и сколько осталось ждать.
#
# Второе: обрыв. Invoke-WebRequest при разрыве связи теряет всё скачанное. Здесь
# запрашивается диапазон от уже полученного байта, и поток дописывается в конец файла:
# разорванное соединение стоит нам того, что не успело доехать, а не всей загрузки.
function Get-File($url, $dest, $expectSize, $headers) {
    $attempt = 0
    while ($true) {
        $have = 0
        if (Test-Path $dest) { $have = (Get-Item $dest).Length }
        if ($expectSize -gt 0 -and $have -ge $expectSize) { return }

        $attempt++
        if ($attempt -gt 20) { throw 'связь обрывается снова и снова' }
        if ($have -gt 0 -and $attempt -eq 1) { Say "    продолжаю с $(Size $have) - заново качать не нужно" 'DarkGray' }

        try {
            $req = [Net.HttpWebRequest]::Create($url)
            $req.UserAgent = 'DeadAir-x64'
            $req.Timeout = 60000
            $req.ReadWriteTimeout = 60000
            # User-Agent, Accept и им подобные .NET считает ограниченными: присвоение через
            # коллекцию Headers бросает исключение. Ставим их свойствами, остальное — в коллекцию.
            if ($headers) { foreach ($k in $headers.Keys) {
                switch ($k) {
                    'User-Agent' { $req.UserAgent = $headers[$k] }
                    'Accept'     { $req.Accept    = $headers[$k] }
                    default      { $req.Headers[$k] = $headers[$k] }
                }
            } }
            # Докачка возможна только когда известен ожидаемый размер: у архива с игровыми
            # файлами GitHub собирает его на лету и размер не сообщает, там качаем с нуля.
            if ($have -gt 0 -and $expectSize -gt 0) { $req.AddRange([int64]$have) }

            $resp = $req.GetResponse()
            # Сервер вправе не понять запрос диапазона и прислать файл целиком. Тогда начинаем
            # заново: иначе получим склейку из двух кусков, которая пройдёт по размеру и окажется
            # битым архивом, а причина будет неочевидной.
            if ($have -gt 0 -and [int]$resp.StatusCode -ne 206) { $have = 0 }

            $fmode = if ($have -gt 0) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
            $in  = $resp.GetResponseStream()
            $out = New-Object IO.FileStream($dest, $fmode, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $started = Get-Date
            $fromStart = [int64]$have
            try {
                $buf = New-Object byte[] 262144
                $doneBytes = [int64]$have
                # Считаем ВРЕМЯ, а не куски: раз в N кусков полоса на медленном канале молчит
                # минутами, и человек решает, что всё повисло. Первую строку рисуем сразу.
                $lastDraw = (Get-Date).AddSeconds(-10)
                while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $n)
                    $doneBytes += $n
                    if (((Get-Date) - $lastDraw).TotalMilliseconds -ge 400) {
                        $lastDraw = Get-Date
                        $sec = ((Get-Date) - $started).TotalSeconds
                        $speed = if ($sec -gt 0) { ($doneBytes - $fromStart) / $sec } else { 0 }
                        $line = if ($expectSize -gt 0) {
                            $left = if ($speed -gt 0) { [int](($expectSize - $doneBytes) / $speed) } else { 0 }
                            '    {0,3:n0}%  {1} из {2}   {3}   осталось ~{4}' -f `
                                (($doneBytes * 100) / $expectSize), (Size $doneBytes), (Size $expectSize), (Speed $speed), (Left $left)
                        } else {
                            '    {0}   {1}' -f (Size $doneBytes), (Speed $speed)
                        }
                        Write-Host ("`r" + $line.PadRight(66)) -NoNewline
                    }
                }
            } finally { $out.Close(); $in.Close(); $resp.Close() }
            Write-Host ("`r" + ('    готово: ' + (Size (Get-Item $dest).Length)).PadRight(66))
            return
        } catch {
            $now = 0
            if (Test-Path $dest) { $now = (Get-Item $dest).Length }
            if ($expectSize -gt 0 -and $now -ge $expectSize) { return }

            # Повторять имеет смысл ТОЛЬКО сетевую ошибку. Всё остальное — ошибка в самом
            # установщике, и двадцать повторов по три секунды лишь спрячут её за ложным
            # «связь оборвалась»: человек полезет чинить интернет, которым всё в порядке.
            if ($_.Exception -isnot [Net.WebException]) { throw }

            Say ''
            Say "    связь оборвалась на $(Size $now) - продолжаю (попытка $attempt)" 'DarkYellow'
            Start-Sleep -Seconds 3
        }
    }
}

# --- 5. Качаем -----------------------------------------------------------------------------
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$binZip  = Join-Path $Work 'bin.zip'
$dataZip = Join-Path $Work 'gamedata.zip'

Say "  Качаю модули движка ($([math]::Round($asset.size/1MB)) МБ)..."
# Для закрытого репозитория обычная ссылка на файл не годится: нужен запрос к API
# с ключом и заголовком octet-stream, иначе вернётся описание файла вместо самого файла.
$assetHeaders = $GhHeaders.Clone()
$assetHeaders['Accept'] = 'application/octet-stream'
$assetUrl = "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($asset.id)"
Get-File $assetUrl $binZip $asset.size $assetHeaders

Say '  Качаю игровые файлы...'
Get-File "https://api.github.com/repos/$Owner/$Repo/zipball/$Branch" $dataZip 0 $GhHeaders

# --- 6. Бэкап оригинала (только при первой установке) --------------------------------------
if (-not $installed) {
    $backup = Join-Path $Root 'original_x32_backup'
    Say '  Сохраняю оригинальные файлы 32-битной версии...'
    New-Item -ItemType Directory -Force $backup | Out-Null
    Get-ChildItem -Path "$Root\*" -Include *.dll,*.exe -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'unins*' } |
        ForEach-Object { Move-Item $_.FullName (Join-Path $backup $_.Name) -Force }
    if (Test-Path (Join-Path $Root 'fsgame.ltx')) {
        Copy-Item (Join-Path $Root 'fsgame.ltx') (Join-Path $backup 'fsgame.ltx') -Force
    }
    Say '  Оригинал лежит в original_x32_backup — не удаляйте её.' 'DarkGray'
}

# --- 7. Распаковываем ----------------------------------------------------------------------
Say '  Распаковываю...'
# Распаковка средствами .NET, а не Expand-Archive: та появилась только в PowerShell 5.0,
# то есть отсутствует на Windows 7 без свежего WMF.
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip($archive, $target) {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $target)
}
Unzip $binZip (Join-Path $Work 'bin_new')
Unzip $dataZip (Join-Path $Work 'data_new')

$binSrc = Join-Path $Work 'bin_new'
if (Test-Path (Join-Path $binSrc 'bin')) { $binSrc = Join-Path $binSrc 'bin' }

$repoDir = Get-ChildItem (Join-Path $Work 'data_new') -Directory | Select-Object -First 1
if (-not $repoDir) { Fail 'Архив игровых файлов оказался пустым.' }
$dataSrc = Join-Path $repoDir.FullName 'gamedata'
if (-not (Test-Path $dataSrc)) { Fail 'В архиве нет папки gamedata.' }

# --- 8. Собираем список того, что ставим ---------------------------------------------------
# Пути относительные, от корня игры — так их можно сравнивать между версиями.
$newFiles = New-Object System.Collections.Generic.List[string]

Get-ChildItem $binSrc -Recurse -File | ForEach-Object {
    $newFiles.Add('bin\' + $_.FullName.Substring($binSrc.Length).TrimStart('\'))
}
Get-ChildItem $dataSrc -Recurse -File | ForEach-Object {
    $newFiles.Add('gamedata\' + $_.FullName.Substring($dataSrc.Length).TrimStart('\'))
}

# [DA_PORT] Файлы, которые ложатся в САМ КОРЕНЬ игры — папка root в обновлении.
#
# Раньше корневых файлов обновление не возило вовсе: только bin и gamedata. А запускалки и
# установщики дополнений живут именно в корне, рядом с ярлыками, и попадали туда лишь при первой
# установке. Значит новая запускалка не доезжала ни до кого, кто уже играет.
#
# Заносим их в тот же манифест, что и остальное: тогда они и обновляются, и убираются по общим
# правилам. Чужие файлы в корне — ярлыки, правки игрока, другие моды — остаются нетронутыми:
# уборка сносит только то, что мы сами когда-то поставили.
$rootSrc = Join-Path $repoDir.FullName 'root'
if (Test-Path $rootSrc) {
    Get-ChildItem $rootSrc -Recurse -File | ForEach-Object {
        $newFiles.Add($_.FullName.Substring($rootSrc.Length).TrimStart('\'))
    }
}

# --- 8а. Какие шейдеры на самом деле меняются -----------------------------------------------
#
# Считать ОБЯЗАТЕЛЬНО до копирования: после него новый файл лежит поверх старого, и разницы уже
# не видно. Нужна она для чистки кэша ниже — см. шаг 9а.
#
# 🪤 Первая версия сравнивала не с установленным, а просто брала все шейдеры обновления, и на
# проверке вхолостую снесла бы 207 каталогов кэша из 602 файлов отгрузки: в ней лежит ВЕСЬ набор
# шейдеров, а не только правленые. Комментарий при этом обещал «пересоберутся единицы».
#
# Сравнение побайтовое, а не через Get-FileHash: тот появился в PowerShell 4.0, а установщик
# держит 3.0. Файлы шейдеров маленькие, читать их целиком дёшево.
$shaderSrc = Join-Path $dataSrc 'shaders'
$changedShaders = New-Object 'System.Collections.Generic.List[string]'
if (Test-Path $shaderSrc) {
    $prefix = $shaderSrc.Length
    Get-ChildItem $shaderSrc -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($prefix).TrimStart('\')
        $old = Join-Path $Root ('gamedata\shaders\' + $rel)
        $differs = $true
        if (Test-Path $old) {
            # ⚠️ Сравнивать СЫРЫЕ байты нельзя, и это уже выученный урок: отгрузка приезжает
            # архивом репозитория (LF), а на диске файл может лежать с CRLF. Побайтово разошлись
            # бы все текстовые файлы разом, и кэш сносился бы целиком при каждом обновлении.
            # На результат компиляции шейдера перевод строки не влияет — приводим оба к одному
            # виду, ровно как это делает _same_content в проверке полноты отгрузки.
            $a = [System.IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n")
            $b = [System.IO.File]::ReadAllText($old).Replace("`r`n", "`n")
            $differs = ($a -cne $b)
        }
        if ($differs) { $changedShaders.Add($_.Name) | Out-Null }
    }
}

# --- 9. Раскладываем -----------------------------------------------------------------------
Say '  Ставлю файлы...'
$binDst = Join-Path $Root 'bin'
New-Item -ItemType Directory -Force $binDst | Out-Null
Copy-Item "$binSrc\*" $binDst -Recurse -Force
Copy-Item $dataSrc $Root -Recurse -Force
Copy-Item (Join-Path $repoDir.FullName 'config\fsgame.ltx') (Join-Path $Root 'fsgame.ltx') -Force

# [DA_PORT] Корневые файлы — запускалки и установщики дополнений. Перечень их уже посчитан
# в шаге 8, здесь они собственно кладутся.
if (Test-Path $rootSrc) {
    Copy-Item (Join-Path $rootSrc '*') $Root -Recurse -Force
}

# --- 9а. Сносим кэш ровно тех шейдеров, которые изменились ------------------------------------
#
# ⛔ Мало заменить исходник шейдера. Движок компилирует его один раз и складывает двоичный
# результат в appdata\shaders_cache_oxr\<рендер>\<имя файла>\<набор настроек>, а при запуске
# берёт готовое, не сверяясь с исходником. У того, кто уже играл, правка молча не применяется:
# ни ошибки, ни строки в логе — просто прежнее поведение.
#
# Список посчитан ДО копирования (шаг 8а), поэтому здесь сносится ровно изменившееся: на чистой
# установке кэша ещё нет, на обновлении пересоберутся единицы.
$cacheRoot = Join-Path $Root 'appdata\shaders_cache_oxr'
if ($changedShaders.Count -and (Test-Path $cacheRoot)) {
    $dropped = 0
    foreach ($name in ($changedShaders | Sort-Object -Unique)) {
        # ⛔ Искать каталог кэша по ТОЧНОМУ имени исходника нельзя, и это стоило целого захода
        # отладки 27.08. Движок кладёт результат под именем ВАРИАНТА, а не файла: исходник
        # accum_sun_far.ps компилируется в каталог accum_sun_far_nomsaa.ps, combine_1.ps —
        # в combine_1_nomsaa.ps. Точный фильтр не находил их вовсе, и у всех, у кого кэш уже
        # был, изменённые шейдеры продолжали работать СТАРЫМИ двоичными: ни ошибки, ни строки
        # в логе — ровно та беда, от которой этот блок и написан.
        #
        # Поэтому сносим по основе имени: <имя без расширения>*<расширение>.
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext  = [System.IO.Path]::GetExtension($name)
        Get-ChildItem $cacheRoot -Recurse -Directory -Filter ($base + '*' + $ext) -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $dropped++
            }
    }
    if ($dropped) { Say "  Сброшен кэш изменённых шейдеров: $dropped." 'DarkGray' }
}


# --- 10. Убираем то, чего в новой сборке больше нет ------------------------------------------
# Считаем только по манифесту: файл удаляется, если МЫ его ставили и теперь он исчез.
# Всё, чего в манифесте не было, — чужое: другие моды, ручные правки. Не трогаем.
if ($oldFiles.Count) {
    # New-Object, а не ::new() — тот появился в PowerShell 5.0.
    $newSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [string[]]$newFiles, [System.StringComparer]::OrdinalIgnoreCase)

    $removed = 0
    foreach ($item in $oldFiles) {
        # ⚠️ Переменная НЕ $rel: так называется объект выпуска, полученный выше.
        # Перезапись сработала бы тихо и всплыла бы там, где его читают следующим.
        if ($newSet.Contains($item)) { continue }
        $path = Join-Path $Root $item
        if (Test-Path $path) {
            try { Remove-Item $path -Force; $removed++ }
            catch { Say "  ! не удалось убрать $item" 'DarkYellow' }
        }
    }

    if ($removed) {
        Say "  Убрано устаревших файлов: $removed" 'DarkGray'

        # пустые папки, оставшиеся после уборки
        foreach ($dir in @('gamedata', 'bin')) {
            $full = Join-Path $Root $dir
            if (-not (Test-Path $full)) { continue }
            Get-ChildItem $full -Recurse -Directory |
                Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem $_.FullName -Recurse -File | Select-Object -First 1) } |
                ForEach-Object { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
        }
    } else {
        Say '  Устаревших файлов не было.' 'DarkGray'
    }
}

# --- 11. Настройки и папки ------------------------------------------------------------------
New-Item -ItemType Directory -Force (Join-Path $Root 'appdata') | Out-Null
$userLtx = Join-Path $Root 'appdata\user.ltx'
if (-not (Test-Path $userLtx)) {
    Copy-Item (Join-Path $repoDir.FullName 'config\user.ltx.default') $userLtx -Force
    Say '  Настройки выставлены по умолчанию.' 'DarkGray'
} else {
    Say '  Ваши настройки сохранены как есть.' 'DarkGray'

    # Разовый перенос: пауза с нажатием клавиши при входе на локацию.
    #
    # Сцена «нажмите любую клавишу» в моде есть давно, но выключателем keypress_on_start её держали
    # в нуле. Теперь она включена. Файл настроек при обновлении не перезаписывается — иначе игрок
    # терял бы всё остальное, — поэтому у тех, у кого сборка уже стоит, остался бы старый ноль.
    # Правим ровно эту строку и ничего больше.
    $ltxLines = Get-Content $userLtx
    if ($ltxLines -match '^\s*keypress_on_start\s+0\s*$') {
        ($ltxLines -replace '^\s*keypress_on_start\s+0\s*$', 'keypress_on_start 1') |
            Set-Content $userLtx -Encoding oem
        Say '  Включена пауза при входе на локацию.' 'DarkGray'
    }

    # Разовый перенос: стратегия сборки мусора Lua.
    #
    # Прежний режим gc_step оставлял порог сборщика вплотную к текущему объёму, и сборка
    # запускалась из выделений памяти внутри скриптов - прямо посреди обновления объекта. Отсюда
    # рывки кадра по 12-16 миллисекунд. Режим gc_timeout делает ту же работу с бюджетом времени
    # и только в одном месте кадра. На замерах рывки исчезают полностью.
    #
    # Значение попадает в файл настроек, а он при обновлении не перезаписывается, иначе игрок
    # терял бы всё остальное. Поэтому правим ровно эту строку.
    $ltxLines = Get-Content $userLtx
    if ($ltxLines -match '^\s*lua_gc_method\s+(gc_step|gc_timeout)\s*$') {
        ($ltxLines -replace '^\s*lua_gc_method\s+(gc_step|gc_timeout)\s*$', 'lua_gc_method gc_adaptive') |
            Set-Content $userLtx -Encoding oem
        Say '  Сборка мусора переведена в щадящий режим.' 'DarkGray'
    }

    # Бюджет сборки мусора: старое значение 1000 подобрано при неверных единицах в движке
    # (счётчик отдавал тики, а бюджет считался в наносекундах — выходило в сто раз больше).
    # После исправления единиц 1000 означает ровно 1 мс на кадр, и сборщик за мусором не
    # успевает: куча Lua растёт. По замерам стоит 4000.
    $ltxLines = Get-Content $userLtx
    if ($ltxLines -match '^\s*lua_gc_timeout\s+1000\s*$') {
        ($ltxLines -replace '^\s*lua_gc_timeout\s+1000\s*$', 'lua_gc_timeout 4000') |
            Set-Content $userLtx -Encoding oem
    }

    # Размытие при перезарядке — выключить.
    #
    # Флаг g_weapon_dof включает три эффектора глубины резкости, и один из них навешивается
    # прямо на перезарядку (Weapon.cpp, ветка eReload). В умолчательном файле настроек он и так
    # ноль, но умолчания достаются только чистой установке — у тех, кто уже играл, остаётся
    # своё значение. Правим ровно эту строку.
    $ltxLines = Get-Content $userLtx
    if ($ltxLines -match '^\s*g_weapon_dof\s+[1-9]') {
        ($ltxLines -replace '^\s*g_weapon_dof\s+.*$', 'g_weapon_dof 0') |
            Set-Content $userLtx -Encoding oem
        Say '  Выключено размытие при перезарядке.' 'DarkGray'
    }

    # Вторая половина того же размытия — погодная глубина резкости.
    #
    # g_weapon_dof выключает эффектор оружия, но экран размывает ещё и погода: level_weathers
    # каждый тик гонит r2_dof_far/r2_dof_kernel с фокусом около полутора метров, а оружие при
    # перезарядке ровно там. Гасится это флагом r2_dof_enable.
    #
    # ⛔ Файлы наборов качества (rspec_*.ltx) его уже гасят, но они применяются ТОЛЬКО при смене
    # качества в меню. У того, кто уже играл, в user.ltx остаётся своё прежнее значение, и до
    # него правка не доходит вовсе. Правим ту же строку, тем же приёмом.
    $ltxLines = Get-Content $userLtx
    if ($ltxLines -match '^\s*r2_dof_enable\s+on') {
        ($ltxLines -replace '^\s*r2_dof_enable\s+.*$', 'r2_dof_enable off') |
            Set-Content $userLtx -Encoding oem
        Say '  Выключена погодная глубина резкости.' 'DarkGray'
    }
}

foreach ($sub in @('logs', 'savedgames', 'shaders_cache_oxr')) {
    New-Item -ItemType Directory -Force (Join-Path $Root "appdata\$sub") | Out-Null
}

$launcher = Join-Path $Root 'Dead Air x64.cmd'
@"
@echo off
cd /d "%~dp0"
start "" "%~dp0bin\xrEngine.exe" -r4 -force_flushlog
"@ | Out-File -FilePath $launcher -Encoding oem -Force

# --- 12. Запоминаем, что поставили ----------------------------------------------------------
$newFiles | Sort-Object -Unique | Out-File -FilePath $Manifest -Encoding utf8 -Force
$latest | Out-File -FilePath $StampFile -Encoding utf8 -Force
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue

Say ''
Say "  Готово. Установлена версия $latest." 'Green'
Say "  Файлов в сборке: $($newFiles.Count)" 'DarkGray'
Say '  Запуск — «Dead Air x64.cmd» в этой же папке.' 'Green'
Say ''
Read-Host 'Enter — выход'
