@echo off
chcp 65001 >nul

echo ============================================
echo   SMS_Cyr — установка исправления кириллицы
echo ============================================
echo.

echo === Проверка ADB ===
where adb >nul 2>nul
if errorlevel 1 (
    echo.
    echo ОШИБКА: adb не найден в PATH.
    echo Установите Android Platform Tools:
    echo https://developer.android.com/tools/releases/platform-tools
    echo.
    pause
    exit /b 1
)

echo === Проверка модема ===
adb devices
echo.
echo Если модем НЕ появился в списке выше — нажмите Ctrl+C.
echo Если появился — нажмите любую клавишу для продолжения.
pause >nul

echo.
echo === [1/7] Установка python3-light и gconv-modules ===
adb shell opkg update
adb shell opkg install python3-light
adb shell opkg install gconv-modules

echo.
echo === [2/7] Проверка Python ===
adb shell /opt/bin/python3 --version
if errorlevel 1 (
    echo.
    echo ОШИБКА: Python не установился. Проверьте интернет на модеме.
    pause
    exit /b 1
)

echo.
echo === [3/7] Копирование Python-скрипта ===
adb push "%~dp0files\send_sms_ucs2.py" /opt/bin/send_sms_ucs2.py
adb shell chmod +x /opt/bin/send_sms_ucs2.py
if errorlevel 1 (
    echo.
    echo ОШИБКА: не удалось залить send_sms_ucs2.py.
    echo Проверьте, что файл существует в files\send_sms_ucs2.py
    pause
    exit /b 1
)

echo.
echo === [4/7] Сохранение оригинального sms.sh (если ещё не сохранён) ===
adb shell "if [ ! -f /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh.orig ]; then cp /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh.orig; fi"
echo Оригинал сохранён как sms.sh.orig (или уже существовал).

echo.
echo === [5/7] Установка пропатченного sms.sh ===
adb push "%~dp0files\sms.sh" /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
adb shell chmod 755 /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
if errorlevel 1 (
    echo.
    echo ОШИБКА: не удалось залить sms.sh.
    echo Проверьте, что файл существует в files\sms.sh
    pause
    exit /b 1
)

echo.
echo === [6/7] Проверка синтаксиса sms.sh ===
adb shell sh -n /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
if errorlevel 1 (
    echo.
    echo ОШИБКА: синтаксис sms.sh нарушен! Восстанавливаем из sms.sh.orig...
    adb shell cp /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh.orig /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
    adb shell systemctl restart lighttpd
    echo Восстановлено. Обратитесь к разработчику патча.
    pause
    exit /b 1
)

echo.
echo === [7/7] Перезапуск lighttpd ===
adb shell systemctl restart lighttpd

echo.
echo ============================================
echo   ГОТОВО
echo ============================================
echo.
echo Откройте QManager: SMS Center -^> Новое сообщение
echo Отправьте SMS с кириллицей - должно дойти как есть.
echo.
echo Проверить в System Logs: при отправке появится
echo "Non-ASCII detected — using Python UCS-2 sender"
echo.
pause