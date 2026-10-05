@echo off
chcp 65001 >nul

echo ============================================
echo   SMS_Cyr — удаление исправления кириллицы
echo ============================================
echo.

echo === Проверка ADB ===
where adb >nul 2>nul
if errorlevel 1 (
    echo.
    echo ОШИБКА: adb не найден в PATH.
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
echo === [1/4] Восстановление оригинального sms.sh ===
echo Сначала пробуем из локальной копии пакета (files\sms.sh.orig)...
adb push "%~dp0files\sms.sh.orig" /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
if errorlevel 1 (
    echo Не удалось залить локальную копию, пробуем sms.sh.orig с модема...
    adb shell cp /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh.orig /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
    if errorlevel 1 (
        echo.
        echo ОШИБКА: оригинальный sms.sh недоступен ни в пакете, ни на модеме.
        echo Проверьте:
        echo   - files\sms.sh.orig в папке пакета
        echo   - /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh.orig на модеме
        pause
        exit /b 1
    )
)
adb shell chmod 755 /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh

echo.
echo === [2/4] Проверка синтаксиса sms.sh ===
adb shell sh -n /usrdata/qmanager/www/cgi-bin/quecmanager/cellular/sms.sh
if errorlevel 1 (
    echo.
    echo ВНИМАНИЕ: восстановленный sms.sh содержит синтаксическую ошибку.
    echo Это странно — файл взят из пакета как эталон. Обратитесь к разработчику.
    pause
    exit /b 1
)

echo.
echo === [3/4] Удаление Python-скрипта ===
adb shell rm -f /opt/bin/send_sms_ucs2.py

echo.
echo === [4/4] Перезапуск lighttpd ===
adb shell systemctl restart lighttpd

echo.
echo ============================================
echo   ГОТОВО
echo ============================================
echo.
echo Патч удалён, QManager вернулся к штатному sms_tool.
echo Кириллица снова будет превращаться в "????" - это ожидаемо.
echo.
echo Зависимости python3-light и gconv-modules оставлены
echo (места почти не занимают, могут пригодиться).
echo.
pause