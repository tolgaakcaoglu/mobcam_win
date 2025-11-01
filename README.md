Mobcam Client (PC İstemcisi)
============================

Telefonunuzun kamerasını USB veya Wi-Fi üzerinden bir PC web kamerasına dönüştüren DroidCam benzeri bir uygulama projesi.

Bu depo, Windows PC'de çalışan **Kontrol Paneli** uygulamasını içerir. Bu uygulama, mobil uygulamadan gelen video akışını almak için gereken Node.js sunucusunu ve adb port yönlendirmesini yönetir, akışı önizler ve [OBS Studio](https://obsproject.com/) gibi programlar için bir kaynak sağlar.

🚀 Proje Mimarisi
-----------------

Sistem 3 ana bileşenden oluşur:

1.  **Flutter Mobil Uygulaması (Ayrı Proje):**
    
    *   Telefonun kamerasından görüntü akışını (JPEG veya YUV formatında) yakalar.
        
    *   Akışı ws://localhost:8080 adresine (USB ile) veya ws://\[PC\_YEREL\_IP\]:8080 (Wi-Fi ile) adresine gönderir.
        
2.  **Node.js Sunucusu (server klasörü):**
    
    *   **Port 8080 (WS):** Mobil uygulamadan gelen ham video akışını dinler.
        
    *   **Port 8081 (WS):** Gelen akışı Windows Kontrol Paneli'ne (önizleme için) iletir (relay).
        
    *   **Port 3000 (HTTP):** Görüntüyü OBS'in "Tarayıcı" kaynağı olarak kullanabilmesi için client.html dosyasını sunar.
        
3.  **Flutter Windows Kontrol Paneli (Bu Proje):**
    
    *   Node.js sunucusunu (server.js) ve adb reverse komutlarını başlatan ve durduran arayüz.
        
    *   Akışı önizler, FPS ve PC'de kaybedilen kare istatistiklerini gösterir.
        
    *   OBS kurulumu için talimatlar sunar.
        
    *   Kapatıldığında sistem tepsisine (system tray) küçülür.
        

✨ Temel Özellikler (Windows İstemcisi)
--------------------------------------

*   Tek tıkla Node.js sunucusunu ve adb port yönlendirmesini başlatma/durdurma.
    
*   Gelen video akışının canlı önizlemesi.
    
*   Akış hızı (FPS) ve PC'de işlenemeyen (kaybedilen) kare istatistikleri.
    
*   OBS Studio'da "Tarayıcı Kaynağı" olarak kullanmak için http://localhost:3000 adresi.
    
*   Uygulama kapatıldığında sistem tepsisinde (system tray) çalışmaya devam etme.
    
*   Node.js veya adb kurulu değilse kullanıcıyı bilgilendirme.
    

📋 Gereksinimler
----------------

Bu projeyi derlemek ve çalıştırmak için sisteminizde şunların kurulu olması gerekir:

*   **Flutter SDK:** Windows platformu için yapılandırılmış olmalı.
    
*   **Visual Studio 2022:** "Masaüstü geliştirme (C++)" iş yükü kurulu olmalı.
    
*   **Node.js:** Sistem PATH'ine eklenmiş olmalı (Kontrol Paneli node komutunu çalıştırır).
    
*   **Android SDK (adb):** platform-tools klasörü (içinde adb.exe bulunur) sistem PATH'ine eklenmiş olmalı (Kontrol Paneli adb komutunu çalıştırır).
    

📦 Kurulum ve Build
-------------------

flutter build komutu, proje dizinindeki server klasörünü (Node.js kodunu içerir) otomatik olarak build klasörüne kopyalamaz.

1.  flutter pub get
    
2.  flutter build windows
    
3.  Release klasörünüzün son hali şöyle görünmelidir:\\build\\windows\\runner\\Release\\ ├── data\\ ├── server\\ <-- MANUEL KOPYALANAN KLASÖR │ ├── client.html │ └── server.js ├── mobcam\_win.exe <-- UYGULAMANIZ ├── flutter\_windows.dll └── (diğer .dll dosyaları)
    

🚀 Kullanım (USB ile)
---------------------

1.  build\\windows\\runner\\Release klasöründeki mobcam\_win.exe (veya verdiğiniz isim) dosyasını çalıştırın.
    
2.  Windows Kontrol Paneli'nde **"Servisi Başlat"** butonuna tıklayın. (Loglarda Node ve ADB'nin başladığını görmelisiniz).
    
3.  Telefonunuzu USB ile bilgisayara bağlayın ve USB Hata Ayıklama modunu etkinleştirin.
    
4.  Flutter Mobil Uygulamasını telefonunuzda başlatın.
    
5.  Mobil uygulamada **"Akışı Başlat"** butonuna tıklayın.
    
6.  Görüntü hem Windows Kontrol Paneli'ndeki önizlemeye hem de http://localhost:3000 adresine (OBS için) gelmeye başlayacaktır.
    

📺 OBS Studio Entegrasyonu
--------------------------

1.  OBS Studio'yu açın.
    
2.  "Kaynaklar" (Sources) paneline + simgesiyle tıklayın ve **"Tarayıcı"** (Browser) seçin.
    
3.  Açılan pencerede:
    
    *   **URL:** http://localhost:3000
        
    *   **Width:** Akış çözünürlüğünüz (örn: 1920)
        
    *   **Height:** Akış çözünürlüğünüz (örn: 1080)
        
    *   (Gerekirse "Control Audio via OBS" seçeneğini kapatın)
        
4.  "Tamam"a tıklayın. Görüntü OBS'e gelecektir.
    
5.  Zoom, Teams, Discord vb. uygulamalarda kullanmak için OBS'in "Kontroller" panelindeki **"Start Virtual Camera"** (Sanal Kamerayı Başlat) butonuna tıklayın.