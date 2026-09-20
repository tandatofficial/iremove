@echo off
set /p REPO_URL="Nhap dia chi Github Repository (vi du: https://github.com/tandat1408/iremove.git): "
if "%REPO_URL%"=="" goto end

git remote remove origin 2>nul
git remote add origin %REPO_URL%
git branch -M main
git push -u origin main

echo.
echo [!] Da push code len GitHub!
echo [!] Vao tab 'Actions' tren GitHub repo de xem tien trinh dong goi file iRemove.ipa tu dong.
pause
:end
