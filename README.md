# Doping Hafıza Desktop (Linux)
Bu uygulama, Doping Hafıza web platformunun masaüstü deneyimini Linux üzerinde daha erişilebilir hale getirmek amacıyla paketlenmiştir.

> ## ⚠️ Disclaimer (Yasal Uyarı)
> Bu uygulama resmî Doping Hafıza ürünü değildir.
> Doping Hafıza ile herhangi bir resmi bağlantısı yoktur. Tüm marka, logo ve içerik hakları ilgili sahiplerine aittir.
> Bu yazılım yalnızca kişisel kullanım ve eğitim amaçlı bir wrapper (sarmalayıcı) olarak geliştirilmiştir.
> Uygulama içerisinde kullanılan tüm içerikler Doping Hafıza'nın kendi servislerinden gelmektedir.
> Geliştirici, içeriklerin doğruluğu, güncelliği veya hizmet sürekliliği konusunda sorumluluk kabul etmez.

### 📌 Notlar
- Uygulama Electron / WebView tabanlıdır.
- İnternet bağlantısı gerektirir.
- Sunucu taraflı değişikliklerden etkilenebilir.

### 🚫 Sorumluluk Reddi
Bu yazılımın kullanımı tamamen kullanıcı sorumluluğundadır.
Olası hesap sorunları, veri kaybı veya servis erişim problemlerinden geliştirici sorumlu tutulamaz. Upstream uygulama kodları Doping tarafından obfuscate edilmiştir; bu proje kaynak kodunu yeniden geliştirmez, yalnızca Linux çalışma kabuğu ve güncelleme kanalını paketleme sırasında ayarlar.

## Güncel kurulum

GitHub Releases içindeki kurulum betiği, son AppImage'ı indirir; uygulamayı menüye
ekler ve simgeyi XDG hicolor dizinine kurar:

```bash
curl -fL https://github.com/c8dhjp4tyv-bit/Doping-Hafiza-Linux/releases/latest/download/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

Kurulum betiği kullanıcı kurulumu yapar (`~/.local/share/doping-hafiza`) ve
otomatik güncelleyicinin dosyaya yazabilmesi için bu yöntem önerilir. İsterseniz
yerel bir AppImage belirtebilir, sistem geneli kurabilir veya oturum açılışında
başlatmayı etkinleştirebilirsiniz:

```bash
./install.sh --appimage ./doping-hafiza-1.14.0-x86_64.AppImage
sudo ./install.sh --system --appimage ./doping-hafiza-1.14.0-x86_64.AppImage
./install.sh --autostart
./install.sh --uninstall
```

`.desktop` kaydı uygulamayı masaüstü ortamının uygulama menüsüne ve görev çubuğu
listesine tanıtır; görev çubuğuna sabitleme işlemi kullanılan masaüstü ortamına
özgüdür. Bu bir GUI uygulaması olduğu için systemd daemon kurulmaz. İstenirse
`--autostart` ile XDG autostart kaydı oluşturulur.

## CI ve haftalık paketleme

`.github/workflows/weekly-build.yml`, Doping Hafıza'nın [resmî teknik destek
sayfasında](https://teknik.dopinghafiza.com/) yayınlanan güncel Windows EXE'sini
haftada bir (Pazartesi 06:17, Türkiye saati) indirir. EXE içindeki x64 Electron
uygulaması Wine veya decompile kullanmadan çıkarılır; Electron Linux runtime ile
AppImage olarak yeniden paketlenir. Kaynak EXE SHA-256'sı, AppImage checksum'ları,
`latest-linux.yml` ve `install.sh` aynı Release'e yüklenir.

Workflow ayrıca `workflow_dispatch` ile elle çalıştırılabilir. Yeni upstream
semver sürümü için `v<sürüm>` etiketiyle Release oluşturulur veya mevcut Release
güncellenir. Upstream aynı sürüm numarasını korursa electron-updater semver gereği
güncelleme başlatmaz.

Yerel paketleme için `asar`, `7z`, `mksquashfs`, ImageMagick ve Electron zip'i
gereklidir. Kaynak EXE, Electron zip'i ve AppImage runtime yolu verilmezse betik
resmî destek sayfasındaki güncel EXE bağlantısını ve gerekli runtime'ları indirir:

```bash
npm install --global @electron/asar@3.4.1
SOURCE_EXE_PATH=./DopingHafiza-Kurulum.exe \
ELECTRON_ZIP_PATH=./electron-v42.10.1-linux-x64.zip \
APPIMAGE_RUNTIME_PATH=./runtime-x86_64 \
ASAR_BIN=asar ./packaging/build-appimage.sh
```

Betik Electron sürümünü resmi EXE içindeki `Electron/<sürüm>` işaretinden
otomatik algılar. Upstream bir build bu işareti kaldırırsa `ELECTRON_VERSION_OVERRIDE`
ile sürüm açıkça verilebilir.

## Otomatik güncelleme ve GPU

`packaging/patch-updater.js`, obfuscate edilmiş uygulamadaki updater çağrısını
dar bir patch ile bu GitHub repository'sine yönlendirir. `resources/app-update.yml`
ve Release içindeki `latest-linux.yml` electron-updater'ın GitHub Releases
kanalını kullanmasını sağlar; diferansiyel blockmap olmadığı için tam AppImage
indirilir ve uygulama kapanırken kurulur.

Grafik sürücüsü sorunlarını önlemek için `packaging/AppRun` her başlatmada
`--disable-gpu --disable-gpu-compositing` ekler. Gerekirse X11 seçmek için
`DOPING_HAFIZA_OZONE_PLATFORM=x11` kullanılabilir.

## Star History

<a href="https://www.star-history.com/?repos=c8dhjp4tyv-bit%2FDoping-Hafiza-Linux&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=c8dhjp4tyv-bit/Doping-Hafiza-Linux&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=c8dhjp4tyv-bit/Doping-Hafiza-Linux&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=c8dhjp4tyv-bit/Doping-Hafiza-Linux&type=date&legend=top-left" />
 </picture>
</a>
