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

# --- КУДА СМОТРЕТЬ ------------------------------------------------------------------------
$Owner  = 'DeadAir-x64'
$Repo   = 'DeadAir-x64-Update'
$Branch = 'main'

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Work      = Join-Path $env:TEMP 'da_x64_update'
$StampFile = Join-Path $Root 'appdata\da_x64_version.txt'
$Manifest  = Join-Path $Root 'appdata\da_x64_files.txt'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Say ''; Say "ОШИБКА: $text" 'Red'; Say ''; Read-Host 'Enter — выход'; exit 1 }

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

# --- 2. Что уже стоит ----------------------------------------------------------------------
$installed = if (Test-Path $StampFile) { (Get-Content $StampFile -Raw).Trim() } else { '' }
$oldFiles  = if (Test-Path $Manifest) { @(Get-Content $Manifest | Where-Object { $_.Trim() }) } else { @() }

if ($installed) {
    Say "  Установлено сейчас: $installed"
    if ($oldFiles.Count) { Say "  Файлов от прошлой установки: $($oldFiles.Count)" 'DarkGray' }
} else {
    Say '  Версия x64 ещё не ставилась — будет первая установка.'
}

# --- 3. Узнаём актуальную версию -----------------------------------------------------------
Say '  Смотрю, что доступно...'
try {
    $api = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'DeadAir-x64-Updater' } -TimeoutSec 30
} catch {
    Fail @"
Не удалось связаться с GitHub. Проверьте интернет и попробуйте позже.
Подробности: $($_.Exception.Message)
"@
}

$latest = $rel.tag_name
if (-not $latest) { Fail 'В репозитории пока нет ни одного выпуска.' }

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

# --- 4. Качаем -----------------------------------------------------------------------------
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$binZip  = Join-Path $Work 'bin.zip'
$dataZip = Join-Path $Work 'gamedata.zip'

Say "  Качаю модули движка ($([math]::Round($asset.size/1MB)) МБ)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $binZip -UseBasicParsing

Say '  Качаю игровые файлы...'
Invoke-WebRequest -Uri "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip" -OutFile $dataZip -UseBasicParsing

# --- 5. Бэкап оригинала (только при первой установке) --------------------------------------
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

# --- 6. Распаковываем ----------------------------------------------------------------------
Say '  Распаковываю...'
Expand-Archive -Path $binZip -DestinationPath (Join-Path $Work 'bin_new') -Force
Expand-Archive -Path $dataZip -DestinationPath (Join-Path $Work 'data_new') -Force

$binSrc = Join-Path $Work 'bin_new'
if (Test-Path (Join-Path $binSrc 'bin')) { $binSrc = Join-Path $binSrc 'bin' }

$repoDir = Get-ChildItem (Join-Path $Work 'data_new') -Directory | Select-Object -First 1
if (-not $repoDir) { Fail 'Архив игровых файлов оказался пустым.' }
$dataSrc = Join-Path $repoDir.FullName 'gamedata'
if (-not (Test-Path $dataSrc)) { Fail 'В архиве нет папки gamedata.' }

# --- 7. Собираем список того, что ставим ---------------------------------------------------
# Пути относительные, от корня игры — так их можно сравнивать между версиями.
$newFiles = New-Object System.Collections.Generic.List[string]

Get-ChildItem $binSrc -Recurse -File | ForEach-Object {
    $newFiles.Add('bin\' + $_.FullName.Substring($binSrc.Length).TrimStart('\'))
}
Get-ChildItem $dataSrc -Recurse -File | ForEach-Object {
    $newFiles.Add('gamedata\' + $_.FullName.Substring($dataSrc.Length).TrimStart('\'))
}

# --- 8. Раскладываем -----------------------------------------------------------------------
Say '  Ставлю файлы...'
$binDst = Join-Path $Root 'bin'
New-Item -ItemType Directory -Force $binDst | Out-Null
Copy-Item "$binSrc\*" $binDst -Recurse -Force
Copy-Item $dataSrc $Root -Recurse -Force
Copy-Item (Join-Path $repoDir.FullName 'config\fsgame.ltx') (Join-Path $Root 'fsgame.ltx') -Force

# --- 9. Убираем то, чего в новой сборке больше нет ------------------------------------------
# Считаем только по манифесту: файл удаляется, если МЫ его ставили и теперь он исчез.
# Всё, чего в манифесте не было, — чужое: другие моды, ручные правки. Не трогаем.
if ($oldFiles.Count) {
    $newSet = [System.Collections.Generic.HashSet[string]]::new(
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

# --- 10. Настройки и папки ------------------------------------------------------------------
New-Item -ItemType Directory -Force (Join-Path $Root 'appdata') | Out-Null
$userLtx = Join-Path $Root 'appdata\user.ltx'
if (-not (Test-Path $userLtx)) {
    Copy-Item (Join-Path $repoDir.FullName 'config\user.ltx.default') $userLtx -Force
    Say '  Настройки выставлены по умолчанию.' 'DarkGray'
} else {
    Say '  Ваши настройки сохранены как есть.' 'DarkGray'
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

# --- 11. Запоминаем, что поставили ----------------------------------------------------------
$newFiles | Sort-Object -Unique | Out-File -FilePath $Manifest -Encoding utf8 -Force
$latest | Out-File -FilePath $StampFile -Encoding utf8 -Force
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue

Say ''
Say "  Готово. Установлена версия $latest." 'Green'
Say "  Файлов в сборке: $($newFiles.Count)" 'DarkGray'
Say '  Запуск — «Dead Air x64.cmd» в этой же папке.' 'Green'
Say ''
Read-Host 'Enter — выход'
