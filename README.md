# UT99 Dedicated Server – LeagueAS140+ (Ubuntu x86_64)

Instalační skript [`install-ut99-leagueas.sh`](./install-ut99-leagueas.sh) automaticky nasadí dedikovaný server **Unreal Tournament (1999)** s modem **LeagueAS140** a **LeagueAS140Plus (AS+)** na nativní 64bitové linuxové binárce (`ucc-bin-amd64` z patche OldUnreal 469e).

---

## Co skript udělá a proč takto funguje

1. **Příprava systému a uživatele** – nainstaluje potřebné balíčky (`curl`, `ca-certificates`, `tar`, `bzip2`, `gzip`, `git`, `python3`, `sudo`) a založí systémového uživatele `utserver`.
2. **Základ UT 436 + Bonus Packy 1–4** – stáhne základní linuxový server UT 436 a Bonus Packy 1–4 ze zrcadla `Roemer/ut99-server`.
3. **Patch OldUnreal 469e (64bit)** – přepíše server nativní `amd64` verzí (`System64/ucc-bin-amd64`), takže **nepotřebujete žádné 32bitové (`i386`) knihovny** (na rozdíl od např. LinuxGSM).
4. **LeagueAS140, AS+, MapVote a mapy** – naklonuje repozitář `Sizzl/UTA-PugServer` a zkopíruje jeho obsah do serveru.
   - *Proč `UTA-PugServer` a ne přímo zdrojový kód `LeagueAS140Plus`?* Repozitář `LeagueAS140Plus` obsahuje pouze zdrojové kódy (sestavuje se na Windows/CI). `UTA-PugServer` obsahuje hotové `.u`/`.int` buildy (`LeagueAS140`, nový `LeagueAS-SP` se spouštěčem `LeagueAS-SP.ASPlus`, `LeagueAS140Plus_*`, `InstaGibPlusAssets_v*`, `MapVoteLA13`, AS mapy a vzorové `.ini`).
5. **Generování konfigurace (`System64/`)** – z `System64/Default.ini` patche 469e vytvoří `System64/server.ini`, nakopíruje `MapVoteLA.ini`, `InstaGibPlus.ini` a `User.ini` přímo do `System64/` (odkud běží 64bitová binárka).
   - *Aktuální master servery:* Vzorová konfigurace v `UTA-PugServer` odkazuje na mrtvé master servery (`unreal.epicgames.com`, `master0.gamespy.com`). Skript proto převezme aktuální seznam uplinků z patche 469e (`333networks`, `oldunreal`, `errorist`, `openspy`, `qtracker`, `hlkclan`) a zapíše je přes `LeagueAS-SP.ServerUplink` (a query přes `LeagueAS-SP.ServerQuery`).
   - *Bez PUG/stats vazeb:* Části vázané na `utassault.net` (`PugStats`, `UTA-Auth`, `UTStats`) jsou ve výchozím nastavení vynechány.
6. **Spouštěcí skript, `systemd` a firewall** – vytvoří `start.sh`, `systemd` službu `ut99-leagueas` (povolí ji a rovnou spustí) a při aktivním `ufw` otevře potřebné porty.

---

## Požadavky a příprava před spuštěním

- **OS:** Ubuntu / Debian (`x86_64` / `amd64`) s právy `sudo` (pro běh bez roota viz `SKIP_SYSTEM=1` níže).
- **Místo na disku:**
  - cca **3,5 GB** s balíkem AS map (`WITH_MAPS=1`, samotný klon má ~2,8 GB, z toho ~1,8 GB jsou mapy),
  - cca **1 GB** bez map (`WITH_MAPS=0`, stáhne se ~500 MB a server startuje na `AS-Frigate`).
- **Zastavení stávajícího serveru:** Pokud vám na stroji běží jiný UT99 server (např. přes LinuxGSM), předem ho zastavte, jinak se oba poperou o port `7777/udp`:
  ```bash
  ./ut99server stop
  ```
- **Otevřené porty na routeru / VPS firewallu:**
  - `7777/udp` – herní port (`PORT`)
  - `7778/udp` – query port (`PORT + 1`) – **bez otevřeného query portu vás master servery nezařadí do veřejného seznamu!**

> [!IMPORTANT]
> **Kontrola konců řádků (CRLF vs LF):** Pokud byl skript stažen/uložen s Windows konci řádků (`CRLF`), `bash` na Linuxu spadne s chybou typu `$'\r': command not found` nebo `set: invalid option`. Pro jistotu před prvním spuštěním převeďte konce řádků na unixové `LF`:
> ```bash
> sed -i 's/\r$//' install-ut99-leagueas.sh
> ```

---

## Instalace a spuštění

### Základní instalace (doporučený postup)

```bash
sudo SERVER_NAME="Muj AS server" ADMIN_EMAIL="vas@email.cz" bash install-ut99-leagueas.sh
```

### Další příklady spuštění

**Bez stahování 1,8 GB AS map (rychlejší testovací instalace, start na `AS-Frigate`):**
```bash
sudo WITH_MAPS=0 SERVER_NAME="Muj AS test" bash install-ut99-leagueas.sh
```

**S vlastním admin heslem, privátním heslem do hry a jiným portem:**
```bash
sudo SERVER_NAME="Klanovy AS server" \
     ADMIN_PASS="MojeSilneHeslo" \
     GAME_PASS="heslo_pro_hrace" \
     PORT=7787 \
     bash install-ut99-leagueas.sh
```

### Opakované spuštění / aktualizace

Skript je bezpečné spustit opakovaně:
- Stažené archivy v `/home/utserver/downloads/` se znovu nestahují (použije se cache).
- Soubory hry a modů z `UTA-PugServer` se aktualizují (`git fetch` + `reset`).
- Existující konfigurační soubory (`server.ini`, `MapVoteLA.ini`, `InstaGibPlus.ini`, `User.ini`) se **nepřepisují**.
- Pokud chcete přegenerovat konfiguraci ze šablony, přidejte `FORCE_CONFIG=1` (původní soubory se zazálohují s příponou `.bak-RRRRMMDD-HHMMSS`):
  ```bash
  sudo FORCE_CONFIG=1 SERVER_NAME="Novy nazev" bash install-ut99-leagueas.sh
  ```

---

## Konfigurační proměnné

Všechny volby lze předat jako proměnné prostředí před `bash install-ut99-leagueas.sh`:

### Nastavení serveru a hry

| Proměnná | Výchozí hodnota | Popis |
| :--- | :--- | :--- |
| `SERVER_NAME` | `LeagueAS140+ Server` | Název serveru v seznamu serverů |
| `SHORT_NAME` | `LAS+` | Krátký název serveru |
| `ADMIN_NAME` | `admin` | Zobrazované jméno admina v informacích serveru |
| `ADMIN_EMAIL` | *(prázdné)* | Kontaktní e-mail admina |
| `MOTD1` | `League Assault 140 + AS Plus` | První řádek uvítací zprávy (MOTD) |
| `ADMIN_PASS` | *(vygeneruje se)* | Admin heslo (prázdné = náhodných 14 znaků) |
| `GAME_PASS` | *(prázdné)* | Heslo pro připojení hráčů (prázdné = veřejný server) |
| `MAX_PLAYERS` | `12` | Maximální počet hráčů (ovlivňuje i `MaxTeamSize = MAX_PLAYERS / 2`) |
| `MAX_SPECTATORS` | `4` | Maximální počet diváků |
| `START_MAP` | `AS-Siege][` nebo `AS-Frigate` | Úvodní mapa po startu (`AS-Siege][` pokud existuje, jinak `AS-Frigate`) |
| `GAME_CLASS` | `LeagueAS140.LeagueAssault` | Herní třída |
| `USE_ASPLUS` | `1` | `1` = přidá mutátor `LeagueAS-SP.ASPlus` (aktivuje LeagueAS140Plus) |
| `MUTATORS` | *(sestaví se automaticky)* | Vlastní seznam mutátorů (výchozí: `MapVoteLA13.BDBMapVote,LeagueAS-SP.ASPlus,ESP140.ESP,XC_Spec_r10a.XC_SpecMutator`) |
| `WITH_MAPS` | `1` | `1` = stáhne celý `UTA-PugServer` (~2,8 GB); `0` = vynechá adresář `Maps/` (~500 MB) |

### Síť, výkon a WebAdmin

| Proměnná | Výchozí hodnota | Popis |
| :--- | :--- | :--- |
| `PORT` | `7777` | Herní UDP port; query port je automaticky `PORT + 1` (UDP) |
| `MULTIHOME` | *(prázdné)* | Konkrétní IP adresa pro bindování (pokud má server více IP) |
| `TICKRATE` | `65` | `NetServerMaxTickRate` a `LanServerMaxTickRate` |
| `MAX_CLIENT_RATE` | `40000` | `MaxClientRate` |
| `EXTRA_MASTERS` | *(prázdné)* | Další master servery nad rámec 469e ve tvaru `"host:port host:port"` |
| `WEBADMIN` | `0` | `1` = zapne UWeb administraci |
| `WEBADMIN_PORT` | `5580` | TCP port pro WebAdmin |

> [!WARNING]
> **WebAdmin (`WEBADMIN=1`) používá nešifrované HTTP!** Heslo se při přihlášení přenáší v čitelné podobě. Nevystavujte port `5580/tcp` přímo do internetu – pokud WebAdmin zapnete, připojujte se přes SSH tunel (`ssh -L 5580:127.0.0.1:5580 uzivatel@server`) a v prohlížeči otevřete `http://127.0.0.1:5580`. Přihlašovací jméno pro WebAdmin je vždy `admin` (i když změníte `ADMIN_NAME`).

### Systémové proměnné a cesty

| Proměnná | Výchozí hodnota | Popis |
| :--- | :--- | :--- |
| `UT_USER` | `utserver` | Systémový uživatel, pod kterým server běží |
| `UT_HOME` | `/home/${UT_USER}` | Domovský adresář uživatele |
| `UT_DIR` | `${UT_HOME}/ut-server` | Instalační adresář UT serveru |
| `PUG_DIR` | `${UT_HOME}/UTA-PugServer` | Adresář s naklonovaným repozitářem `UTA-PugServer` |
| `DL_DIR` | `${UT_HOME}/downloads` | Cache stažených archivů |
| `SERVICE_NAME` | `ut99-leagueas` | Název `systemd` služby |
| `UT_PATCH_VERSION` | `469e` | Verze OldUnreal patche |
| `FORCE_CONFIG` | `0` | `1` = přepíše existující `.ini` soubory (se zálohou) |
| `SKIP_SYSTEM` | `0` | `1` = přeskočí `apt`, `useradd`, `systemd`, `chown` a `ufw` (viz níže) |

---

## Kam se co nainstaluje

```text
/home/utserver/
├── downloads/                         # Stažené archivy (cache)
├── UTA-PugServer/                     # Klon repozitáře Sizzl/UTA-PugServer
└── ut-server/
    ├── install-info.txt               # Souhrn instalace a vygenerované admin heslo
    ├── start.sh                       # Spouštěcí skript serveru
    ├── Logs/server.log                # Log běžícího serveru
    ├── Maps/                          # Mapy (.unr)
    ├── System/                        # Balíčky (.u, .int) a vzorové .ini
    └── System64/                      # 64bitová binárka a aktivní konfigurace
        ├── ucc-bin-amd64
        ├── server.ini                 # Hlavní konfigurace serveru
        ├── User.ini
        ├── MapVoteLA.ini              # Nastavení hlasování o mapách
        └── InstaGibPlus.ini           # Nastavení AS+ / InstaGibPlus
```

Služba `systemd`: `/etc/systemd/system/ut99-leagueas.service`.

---

## Provoz, správa a ověření serveru

### Základní příkazy služby

```bash
sudo systemctl status ut99-leagueas     # stav serveru
sudo systemctl restart ut99-leagueas    # restart (po změně .ini)
sudo systemctl stop ut99-leagueas       # zastavení
sudo systemctl start ut99-leagueas      # spuštění
```

### Sledování logů a zjištění hesla

```bash
# Souhrn instalace včetně vygenerovaného admin hesla
sudo cat /home/utserver/ut-server/install-info.txt

# Živý výstup herního logu
tail -f /home/utserver/ut-server/Logs/server.log

# Živý výstup systemd služby
journalctl -u ut99-leagueas -f
```

### Ověření připojení k master serverům

Po startu serveru zkontrolujte v logu, že uplinky úspěšně komunikují:

```bash
grep -i uplink /home/utserver/ut-server/Logs/server.log
```

### Přihlášení jako admin ve hře

Ve hře otevřete konzoli (`~` nebo `Tab`) a zadejte:

```text
adminlogin <ADMIN_PASS>
```

---

## Další úpravy

### Úprava herní konfigurace

Konfigurační soubory leží v `/home/utserver/ut-server/System64/`:
- `server.ini` – obecné nastavení, časové limity (`TimeLimit=9`), pravidla `LeagueAS140.LeagueAssault`, FOV (`MinFOV`, `MaxFOV`), `ServerActors`, `ServerPackages`.
- `MapVoteLA.ini` – seznam map a režimů v MapVote.
- `InstaGibPlus.ini` – nastavení funkcí AS+.

Po každé úpravě restartujte server (`sudo systemctl restart ut99-leagueas`).

### Instalace bez root oprávnění (`SKIP_SYSTEM=1`)

Pokud instalujete pod běžným uživatelem (bez `sudo`), **musíte zároveň přepsat cesty** (`UT_USER`, `UT_HOME` nebo `UT_DIR`), jinak se skript pokusí zapisovat do `/home/utserver`:

```bash
SKIP_SYSTEM=1 UT_USER="$USER" UT_HOME="$HOME" bash install-ut99-leagueas.sh
```

Po instalaci je nutné mít nainstalované závislosti (`curl`, `tar`, `bzip2`, `gzip`, `git`, `python3`) a server spouštět ručně (např. v `tmux`/`screen` přes `~/ut-server/start.sh`).

### PUG / statistiky (`utassault.net`)

Doplňky jako `PugStats`, `UTA-Auth` nebo `UTStats` jsou ve skriptu záměrně vynechané, protože jsou navázané na infrastrukturu `utassault.net`. Pokud je budete chtít doplnit, příslušné řádky do `server.ini` najdete v `README` repozitáře `Sizzl/UTA-PugServer` (`/home/utserver/UTA-PugServer/`).

---

## Řešení potíží

| Problém | Příčina a řešení |
| :--- | :--- |
| **`$'\r': command not found`** při spuštění | Skript má Windows konce řádků (`CRLF`). Spusťte `sed -i 's/\r$//' install-ut99-leagueas.sh`. |
| **Server není vidět v online prohlížeči serverů** | Zkontrolujte, zda je otevřený jak herní port (`7777/udp`), tak **query port (`7778/udp`)** v `ufw`, na routeru i u poskytovatele VPS. Dále ověřte log přes `grep -i uplink /home/utserver/ut-server/Logs/server.log`. |
| **Chyba `Address already in use` / server nejde spustit** | Na stejném portu už běží jiná instance (např. LinuxGSM `ut99server`). Zastavte ji nebo spusťte instalaci s jiným `PORT=...`. |
| **Chyba oprávnění při `SKIP_SYSTEM=1`** | Předejte také `UT_USER="$USER" UT_HOME="$HOME"`, aby se soubory neukládaly pod `/home/utserver`. |
| **Pomalé stahování nebo nedostatek místa** | Použijte `WITH_MAPS=0` (stáhne ~500 MB místo ~2,8 GB) a mapy si doplňte ručně do `ut-server/Maps/`. |
