const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

// --- Yapılandırma ---
const HTTP_PORT = 3000;
const WS_PORT_PHONE = 8080; // Telefonun bağlanacağı port (8080)
const WS_PORT_VIEWER = 8081; // Tarayıcının bağlanacağı port (8081)
// --------------------

// 1. HTTP Sunucusu (Arayüzü Sunmak İçin)
const app = express();
const server = http.createServer(app);

// client.html dosyasını sun
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'client.html'));
});

server.listen(HTTP_PORT, () => {
    console.log(`[HTTP] Web Arayüzü çalışıyor: http://localhost:${HTTP_PORT}`);
});


// 2. WebSocket Sunucuları (Telefon ve Tarayıcı için Ayrı)

// wssPhone: 8080 portunda, telefondan gelen veriyi dinler
const wssPhone = new WebSocket.Server({ port: WS_PORT_PHONE });

// wssViewer: 8081 portunda, tarayıcılara veriyi gönderir
const wssViewer = new WebSocket.Server({ port: WS_PORT_VIEWER });

console.log(`[WS] Telefon Akış Sunucusu (8080) dinleniyor...`);
console.log(`[WS] Tarayıcı Görüntüleme Sunucusu (8081) dinleniyor...`);

// Tarayıcıların bağlandığını doğrulamak için bir log ekleyelim
// Tarayıcı (client.html) 8081'e bağlandığında bu çalışır
wssViewer.on('connection', function connection(ws) {
    console.log('[WS-8081] Tarayıcı (Görüntüleyici) bağlandı.');
    ws.on('close', () => {
        console.log('[WS-8081] Tarayıcı (Görüntüleyici) bağlantısı kesildi.');
    });
});

// Telefon bağlantısı (wssPhone - 8080)
// Telefon (Flutter) 8080'e bağlandığında bu çalışır
wssPhone.on('connection', function connection(ws, req) {
    const ip = req.socket.remoteAddress;
    console.log(`[WS-8080] Telefon bağlandı. IP: ${ip}`);

    // Telefonda gelen mesaj (video karesi)
    ws.on('message', function incoming(message) {

        // Gelen mesajı (kareyi), 8081 portuna bağlı OLAN TÜM TARAYICILARA ilet
        wssViewer.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                // Base64 verisini (veya buffer'ı) doğrudan gönder
                // Gelen mesaj zaten Base64 string olduğu için dönüştürmeye gerek yok
                client.send(message);
            }
        });
    });

    ws.on('close', () => {
        console.log(`[WS-8080] Telefon (${ip}) bağlantısı kesildi.`);
    });

    ws.on('error', (e) => {
        console.error(`[WS-8080] Telefon (${ip}) hatası: ${e.message}`);
    });
});
