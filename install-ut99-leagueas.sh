#!/usr/bin/env bash
# =============================================================================
#  UT99 dedicated server + LeagueAS140 + LeagueAS140Plus (AS+)  --  Ubuntu x86_64
#
#  Co skript udela:
#    1. nainstaluje balicky, zalozi uzivatele (vychozi: utserver)
#    2. stahne zakladni linuxovy server UT 436 + Bonus Packy 1-4
#    3. prepise ho patchem OldUnreal 469e (nativni 64bit ucc-bin-amd64)
#    4. naklonuje Sizzl/UTA-PugServer (hotove buildy LeagueAS140, LeagueAS-SP,
#       LeagueAS140Plus_*, InstaGibPlusAssets, MapVoteLA13, AS mapy ...) a
#       zkopiruje ho do serveru
#    5. vygeneruje System64/server.ini z Default.ini patche 469e
#       (aktualni master servery, ServerPackages/ServerActors, LeagueAS sekce)
#    6. nakopiruje InstaGibPlus.ini a MapVoteLA.ini
#    7. vytvori start.sh, systemd sluzbu a otevre porty v ufw
#
#  Pouziti:
#     sudo bash install-ut99-leagueas.sh
#     sudo SERVER_NAME="Muj AS server" ADMIN_PASS=tajne bash install-ut99-leagueas.sh
#
#  Opakovane spusteni je bezpecne: soubory hry/modu se aktualizuji, existujici
#  server.ini / MapVoteLA.ini / InstaGibPlus.ini se NEPREPISUJI
#  (prepsani vynutite FORCE_CONFIG=1, puvodni soubor se zazalohuje).
# =============================================================================
set -Eeuo pipefail

# ----------------------------- nastaveni -------------------------------------
UT_USER="${UT_USER:-utserver}"
UT_HOME="${UT_HOME:-/home/${UT_USER}}"
UT_DIR="${UT_DIR:-${UT_HOME}/ut-server}"
PUG_DIR="${PUG_DIR:-${UT_HOME}/UTA-PugServer}"
DL_DIR="${DL_DIR:-${UT_HOME}/downloads}"
SERVICE_NAME="${SERVICE_NAME:-ut99-leagueas}"

SERVER_NAME="${SERVER_NAME:-LeagueAS140+ Server}"
SHORT_NAME="${SHORT_NAME:-LAS+}"
ADMIN_NAME="${ADMIN_NAME:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
MOTD1="${MOTD1:-League Assault 140 + AS Plus}"
ADMIN_PASS="${ADMIN_PASS:-}"          # prazdne = vygeneruje se
GAME_PASS="${GAME_PASS:-}"            # prazdne = verejny server
MAX_PLAYERS="${MAX_PLAYERS:-12}"
MAX_SPECTATORS="${MAX_SPECTATORS:-4}"

PORT="${PORT:-7777}"                  # UDP hra; query = PORT+1 (UDP)
MULTIHOME="${MULTIHOME:-}"            # IP k bindovani, kdyz ma stroj vic adres
TICKRATE="${TICKRATE:-65}"
MAX_CLIENT_RATE="${MAX_CLIENT_RATE:-40000}"

WEBADMIN="${WEBADMIN:-0}"             # 1 = zapnout UWeb admin (HTTP, nesifrovane!)
WEBADMIN_PORT="${WEBADMIN_PORT:-5580}"

WITH_MAPS="${WITH_MAPS:-1}"           # 0 = nestahovat ~1.8 GB AS map z UTA-PugServer
USE_ASPLUS="${USE_ASPLUS:-1}"         # 1 = startovat s LeagueAS-SP.ASPlus (nacte LeagueAS140Plus)
START_MAP="${START_MAP:-}"            # prazdne = AS-Siege][ (kdyz existuje), jinak AS-Frigate
GAME_CLASS="${GAME_CLASS:-LeagueAS140.LeagueAssault}"
MUTATORS="${MUTATORS:-}"              # prazdne = sestavi se nize
EXTRA_MASTERS="${EXTRA_MASTERS:-}"    # "host:port host:port" navic k seznamu z 469e

FORCE_CONFIG="${FORCE_CONFIG:-0}"
SKIP_SYSTEM="${SKIP_SYSTEM:-0}"       # 1 = bez apt/useradd/systemd/ufw (instalace pod beznym uzivatelem)

UT_PATCH_VERSION="${UT_PATCH_VERSION:-469e}"
URL_PATCH="${URL_PATCH:-https://github.com/OldUnreal/UnrealTournamentPatches/releases/download/v${UT_PATCH_VERSION}/OldUnreal-UTPatch${UT_PATCH_VERSION}-Linux-amd64.tar.bz2}"
URL_BASE="${URL_BASE:-https://raw.githubusercontent.com/Roemer/ut99-server/refs/heads/main/files}"
URL_PUG="${URL_PUG:-https://github.com/Sizzl/UTA-PugServer.git}"
# -----------------------------------------------------------------------------

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "Chyba na radku $LINENO (prikaz: $BASH_COMMAND)"' ERR

[[ "$(uname -m)" == "x86_64" ]] || die "Skript pocita s x86_64 (amd64). Zjisteno: $(uname -m)"
if [[ "$SKIP_SYSTEM" != "1" && $EUID -ne 0 ]]; then
  die "Spustte pres sudo (nebo SKIP_SYSTEM=1 pro instalaci bez roota)."
fi

# prikazy bezici pod uzivatelem serveru
as_ut() {
  if [[ "$SKIP_SYSTEM" == "1" || "$(id -un)" == "$UT_USER" ]]; then "$@"
  else sudo -H -u "$UT_USER" -- "$@"; fi
}

fetch() { # fetch URL CIL
  local url="$1" dst="$2"
  if [[ -s "$dst" ]]; then echo "   (cache) $(basename "$dst")"; return 0; fi
  echo "   stahuji $(basename "$dst")"
  as_ut curl -fL --retry 3 --retry-delay 3 -o "${dst}.part" "$url"
  as_ut mv "${dst}.part" "$dst"
}

# ----------------------------- 1. system -------------------------------------
if [[ "$SKIP_SYSTEM" != "1" ]]; then
  log "Instaluji balicky"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates tar bzip2 gzip git python3 sudo >/dev/null

  if ! id "$UT_USER" &>/dev/null; then
    log "Zakladam uzivatele $UT_USER"
    useradd --create-home --home-dir "$UT_HOME" --shell /bin/bash "$UT_USER"
  fi
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    log "Zastavuji bezici sluzbu $SERVICE_NAME"
    systemctl stop "$SERVICE_NAME"
  fi
else
  for c in curl tar bzip2 git python3; do
    command -v "$c" >/dev/null || die "Chybi prikaz: $c"
  done
fi
as_ut mkdir -p "$UT_HOME" "$UT_DIR" "$DL_DIR"

# ----------------------------- 2. zaklad UT 436 ------------------------------
log "Zakladni server UT 436 + Bonus Packy"
if [[ ! -f "$UT_DIR/System/Botpack.u" ]]; then
  fetch "$URL_BASE/ut-server-linux-436.tar.gz" "$DL_DIR/ut-server-linux-436.tar.gz"
  as_ut tar xzf "$DL_DIR/ut-server-linux-436.tar.gz" -C "$UT_DIR" --strip-components=1
else
  echo "   zaklad uz je nainstalovan, preskakuji"
fi
for i in 1 2 3 4; do
  if [[ ! -f "$UT_DIR/.bonuspack$i" ]]; then
    fetch "$URL_BASE/UTBonusPack$i.tar.gz" "$DL_DIR/UTBonusPack$i.tar.gz"
    as_ut tar xzf "$DL_DIR/UTBonusPack$i.tar.gz" -C "$UT_DIR"
    as_ut touch "$UT_DIR/.bonuspack$i"
  fi
done

# ----------------------------- 3. patch OldUnreal ----------------------------
log "Patch OldUnreal $UT_PATCH_VERSION (amd64)"
if [[ "$(cat "$UT_DIR/.patch-version" 2>/dev/null || true)" != "$UT_PATCH_VERSION" ]]; then
  fetch "$URL_PATCH" "$DL_DIR/OldUnreal-UTPatch${UT_PATCH_VERSION}-Linux-amd64.tar.bz2"
  as_ut tar xjf "$DL_DIR/OldUnreal-UTPatch${UT_PATCH_VERSION}-Linux-amd64.tar.bz2" -C "$UT_DIR"
  echo "$UT_PATCH_VERSION" | as_ut tee "$UT_DIR/.patch-version" >/dev/null
else
  echo "   patch $UT_PATCH_VERSION uz je aplikovan, preskakuji"
fi
[[ -x "$UT_DIR/System64/ucc-bin-amd64" ]] || die "Po patchi chybi System64/ucc-bin-amd64"
as_ut mkdir -p "$UT_DIR/Logs" "$UT_DIR/Cache" "$UT_DIR/Save"

# ----------------------------- 4. LeagueAS / UTA-PugServer -------------------
log "LeagueAS140 + LeagueAS140Plus (repo Sizzl/UTA-PugServer)"
if [[ -d "$PUG_DIR/.git" ]]; then
  as_ut git -C "$PUG_DIR" fetch --depth 1 origin
  as_ut git -C "$PUG_DIR" reset --hard FETCH_HEAD
elif [[ "$WITH_MAPS" == "1" ]]; then
  echo "   klonuji cely repozitar (cca 2.8 GB vcetne AS map, chvili to potrva)"
  as_ut git clone --depth 1 "$URL_PUG" "$PUG_DIR"
else
  echo "   klonuji bez adresare Maps"
  as_ut git clone --depth 1 --filter=blob:none --no-checkout "$URL_PUG" "$PUG_DIR"
  as_ut git -C "$PUG_DIR" sparse-checkout set --no-cone '/*' '!/ut-server/Maps/'
  as_ut git -C "$PUG_DIR" checkout
fi
as_ut cp -a "$PUG_DIR/ut-server/." "$UT_DIR/"

SYS="$UT_DIR/System"
SYS64="$UT_DIR/System64"
for f in LeagueAS140.u LeagueAS-SP.u LeagueAS-CP.u "LeagueAS140+++.u"; do
  [[ -f "$SYS/$f" ]] || die "V repozitari chybi System/$f"
done

# nejnovejsi build LeagueAS140Plus = ten, ke kteremu repozitar dodava .int
PLUS_PKG="${PLUS_PKG:-}"
if [[ -z "$PLUS_PKG" ]]; then
  PLUS_PKG="$(cd "$SYS" && ls -t LeagueAS140Plus_*.int 2>/dev/null | head -n1 | sed 's/\.int$//')"
fi
[[ -n "$PLUS_PKG" && -f "$SYS/$PLUS_PKG.u" ]] || die "Nenasel jsem build LeagueAS140Plus_*.u"
ASSETS_PKG="$(cd "$SYS" && ls InstaGibPlusAssets_v*.u | sort -V | tail -n1 | sed 's/\.u$//')"
echo "   AS+ balicek:     $PLUS_PKG"
echo "   assets balicek:  $ASSETS_PKG"

if [[ -z "$START_MAP" ]]; then
  if [[ -f "$UT_DIR/Maps/AS-Siege][.unr" ]]; then START_MAP='AS-Siege]['; else START_MAP='AS-Frigate'; fi
fi
[[ -f "$UT_DIR/Maps/$START_MAP.unr" ]] || die "Startovni mapa $START_MAP.unr neexistuje v $UT_DIR/Maps"
if [[ -z "$MUTATORS" ]]; then
  MUTATORS="MapVoteLA13.BDBMapVote"
  [[ "$USE_ASPLUS" == "1" ]] && MUTATORS+=",LeagueAS-SP.ASPlus"
  MUTATORS+=",ESP140.ESP,XC_Spec_r10a.XC_SpecMutator"
fi

# ----------------------------- 5. konfigurace --------------------------------
log "Konfigurace"
if [[ -z "$ADMIN_PASS" ]]; then
  ADMIN_PASS="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 14)"
fi

backup_or_keep() { # vrati 0, kdyz se ma soubor (znovu) vytvorit
  local f="$1"
  if [[ -f "$f" ]]; then
    if [[ "$FORCE_CONFIG" == "1" ]]; then
      as_ut cp -a "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"; return 0
    fi
    echo "   ponechavam existujici $(basename "$f")"; return 1
  fi
  return 0
}

if backup_or_keep "$SYS64/MapVoteLA.ini"; then
  as_ut cp "$SYS/MapVoteLA.example.ini" "$SYS64/MapVoteLA.ini"
fi
if backup_or_keep "$SYS64/InstaGibPlus.ini"; then
  as_ut cp "$SYS/InstaGibPlus.example.ini" "$SYS64/InstaGibPlus.ini"
fi
if [[ ! -f "$SYS64/User.ini" ]]; then
  as_ut cp "$SYS64/DefUser.ini" "$SYS64/User.ini"
fi

if backup_or_keep "$SYS64/server.ini"; then
  # promenne se predavaji explicitne (sudo by exportovane prostredi zahodilo)
  as_ut env SRC="$SYS64/Default.ini" DST="$SYS64/server.ini" \
    SERVER_NAME="$SERVER_NAME" SHORT_NAME="$SHORT_NAME" ADMIN_NAME="$ADMIN_NAME" \
    ADMIN_EMAIL="$ADMIN_EMAIL" MOTD1="$MOTD1" ADMIN_PASS="$ADMIN_PASS" GAME_PASS="$GAME_PASS" \
    MAX_PLAYERS="$MAX_PLAYERS" MAX_SPECTATORS="$MAX_SPECTATORS" PORT="$PORT" \
    TICKRATE="$TICKRATE" MAX_CLIENT_RATE="$MAX_CLIENT_RATE" WEBADMIN="$WEBADMIN" \
    WEBADMIN_PORT="$WEBADMIN_PORT" EXTRA_MASTERS="$EXTRA_MASTERS" \
    PLUS_PKG="$PLUS_PKG" ASSETS_PKG="$ASSETS_PKG" \
    python3 - <<'PYEOF'
import os, re

E = os.environ
src, dst = E["SRC"], E["DST"]
lines = open(src, encoding="latin-1").read().splitlines()

# --- rozdelit na sekce (zachovat poradi i duplicitni klice) ---
sections, order, cur = {}, [], None
for ln in lines:
    m = re.match(r"^\[(.+)\]\s*$", ln)
    if m:
        cur = m.group(1)
        if cur not in sections:
            sections[cur] = []
            order.append(cur)
        continue
    if cur is not None and ln.strip():
        sections[cur].append(ln)

def sec(name):
    if name not in sections:
        sections[name] = []
        order.append(name)
    return sections[name]

def setkey(name, key, value):
    s = sec(name)
    for i, ln in enumerate(s):
        if ln.split("=", 1)[0].strip().lower() == key.lower():
            s[i] = f"{key}={value}"
            return
    s.append(f"{key}={value}")

def replace_section(name, text):
    sections[name] = [l for l in text.strip().splitlines() if l.strip()]
    if name not in order:
        order.append(name)

# --- [Engine.GameEngine]: master servery + LeagueAS ---
ge = sec("Engine.GameEngine")
masters = []
for ln in ge:
    m = re.match(r"(?i)ServerActors=IpServer\.UdpServerUplink\s+MasterServerAddress=(\S+)\s+MasterServerPort=(\d+)", ln)
    if m:
        masters.append((m.group(1), m.group(2)))
if not masters:  # zaloha, kdyby Default.ini zadne neobsahoval
    masters = [("master.333networks.com", "27900"), ("master.oldunreal.com", "27900"),
               ("master2.oldunreal.com", "27900"), ("master.errorist.eu", "27900"),
               ("master.openspy.net", "27900"), ("master.qtracker.com", "27900"),
               ("master.hlkclan.net", "27900")]
for item in E.get("EXTRA_MASTERS", "").split():
    host, _, port = item.partition(":")
    if (host, port or "27900") not in masters:
        masters.append((host, port or "27900"))

keep = [ln for ln in ge
        if not re.match(r"(?i)ServerActors=IpServer\.UdpServer(Query|Uplink)", ln)
        and not re.match(r"(?i)ServerActors=UWeb\.WebServer", ln)]
other      = [ln for ln in keep if not re.match(r"(?i)Server(Actors|Packages)=", ln)]
actors     = [ln for ln in keep if re.match(r"(?i)ServerActors=", ln)]
packages   = [ln for ln in keep if re.match(r"(?i)ServerPackages=", ln)]

actors += ["ServerActors=LeagueAS-SP.ServerQuery"]
actors += [f"ServerActors=LeagueAS-SP.ServerUplink MasterServerAddress={h} MasterServerPort={p}"
           for h, p in masters]
actors += ["ServerActors=UWeb.WebServer",
           "ServerActors=BallFiXstic.FixTele",
           "ServerActors=ColderSteelFix.ColderSteelFix",
           "ServerActors=LeagueAS140+++.ModernUTSupport"]
for p in ["LeagueAS-CP", "AssaultBonusPack", "Autorip", "EavyAssaultPlus",
          "ZeroPingPlus103", "LeagueAS140+++", "MapVoteLA13", "ESP140",
          E["ASSETS_PKG"], E["PLUS_PKG"]]:
    if f"ServerPackages={p}".lower() not in [x.lower() for x in packages]:
        packages.append(f"ServerPackages={p}")
sections["Engine.GameEngine"] = other + actors + packages

# --- zakladni nastaveni serveru ---
setkey("URL", "Port", E["PORT"])
setkey("Engine.GameReplicationInfo", "ServerName", E["SERVER_NAME"])
setkey("Engine.GameReplicationInfo", "ShortName", E["SHORT_NAME"])
setkey("Engine.GameReplicationInfo", "AdminName", E["ADMIN_NAME"])
setkey("Engine.GameReplicationInfo", "AdminEmail", E["ADMIN_EMAIL"])
setkey("Engine.GameReplicationInfo", "MOTDLine1", E["MOTD1"])
setkey("Engine.GameInfo", "AdminPassword", E["ADMIN_PASS"])
setkey("Engine.GameInfo", "GamePassword", E["GAME_PASS"])
setkey("Engine.GameInfo", "MaxPlayers", E["MAX_PLAYERS"])
setkey("Engine.GameInfo", "MaxSpectators", E["MAX_SPECTATORS"])
setkey("IpDrv.TcpNetDriver", "NetServerMaxTickRate", E["TICKRATE"])
setkey("IpDrv.TcpNetDriver", "LanServerMaxTickRate", E["TICKRATE"])
setkey("IpDrv.TcpNetDriver", "MaxClientRate", E["MAX_CLIENT_RATE"])
setkey("UWeb.WebServer", "bEnabled", "True" if E["WEBADMIN"] == "1" else "False")
setkey("UWeb.WebServer", "ListenPort", E["WEBADMIN_PORT"])
setkey("UTServerAdmin.UTServerAdmin", "AdminUsername", "admin")
setkey("UTServerAdmin.UTServerAdmin", "AdminPassword", E["ADMIN_PASS"])

# --- LeagueAS sekce (podle README Sizzl/UTA-PugServer, bez pug/auth/stats casti) ---
replace_section("LeagueAS-SP.ServerSetupDataLink", """
bDoDataLink=False
bNATCompliant=True
""")
replace_section("LeagueAS-SP.ServerSideModule", """
bSiegeFix=True
MiniPrimAdjust=1.070000
MiniSecAdjust=1.080000
bDebug=False
""")
replace_section("LeagueAS140.LeagueAssault", f"""
bngStatsCompatibility=True
bEnableCSHP=False
bAttackOnly=False
bMatchMode=False
bPracticeMode=False
bStandardise=True
bAuthorisePlayers=False
bAdminNameScore=True
bServerNameScore=True
bServerNameGameType=True
bCheckServername=True
bAutoPausing=True
bNoSuicidePenalties=True
FirstMapStartTime=180
SubsequentMapStartTime=55
TeamNameRed=RED
TeamNameBlue=BLUE
PrivateString=LOCKED - PRIVATE
PublicString=OPEN - PUBLIC
bImprovedTeamBalance=True
TeamBalanceDelayTime=60
bPreventMapChangeKick=True
PreventMapChangeKickTime=40
AuthModuleClass=LeagueAS140.LeagueAS_AuthAbstract
EntryActorClassString=LeagueAS140+++.ModernLASER
FriendlyFireScale=0.000000
MaxTeams=2
GoalTeamScore=0.000000
MaxTeamSize={max(1, int(E["MAX_PLAYERS"]) // 2)}
FragLimit=0
TimeLimit=9
bMultiWeaponStay=True
bForceRespawn=True
bUseTranslocator=False
MaxCommanders=0
bNoMonsters=False
bHumansOnly=False
bCoopWeaponMode=True
bClassicDeathMessages=False
MinFOV=80.000000
MaxFOV=130.000000
MaxNameChanges=0
MaxPauseTime=300
MaxPauseCount=10
MaxPausePerMapCount=3
PauseLeadInOutTime=5
""")
replace_section("LeagueAS140.HackProtection", """
ScanForRogues=0
Advertise=0
bEnableCRCCheck=False
bAllowCRC0=True
""")
replace_section("LeagueASCheatReporter.UTReporterCfg", "Enabled=False")
replace_section("LeagueAS-Reporter.UTReporterConfig", "EnableIRCCom=False\nEnabled=False")

with open(dst, "w", encoding="latin-1", newline="\r\n") as f:
    for name in order:
        f.write(f"[{name}]\n")
        for ln in sections[name]:
            f.write(ln + "\n")
        f.write("\n")
print(f"   server.ini vytvoren ({len(masters)} master serveru)")
PYEOF
  as_ut chmod 600 "$SYS64/server.ini"
fi

# ----------------------------- 6. start skript -------------------------------
log "Start skript a sluzba"
START_URL="${START_MAP}?game=${GAME_CLASS}?mutator=${MUTATORS}"
as_ut tee "$UT_DIR/start.sh" >/dev/null <<EOF
#!/usr/bin/env bash
# vygenerovano install-ut99-leagueas.sh
cd "$SYS64" || exit 1
export LD_LIBRARY_PATH=".:\${LD_LIBRARY_PATH:-}"
exec ./ucc-bin-amd64 server '${START_URL}' \\
     -ini=server.ini -userini=User.ini -nohomedir -log=../Logs/server.log ${MULTIHOME:+-multihome=$MULTIHOME}
EOF
as_ut chmod +x "$UT_DIR/start.sh"

if [[ "$SKIP_SYSTEM" != "1" ]]; then
  chown -R "$UT_USER":"$UT_USER" "$UT_DIR"
  cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Unreal Tournament 99 - LeagueAS140+ dedicated server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${UT_USER}
Group=${UT_USER}
WorkingDirectory=${SYS64}
ExecStart=${UT_DIR}/start.sh
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"

  # ----------------------------- 7. firewall ---------------------------------
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    log "Oteviram porty v ufw"
    ufw allow "${PORT}/udp"            comment 'UT99 game'   >/dev/null
    ufw allow "$((PORT + 1))/udp"      comment 'UT99 query'  >/dev/null
    [[ "$WEBADMIN" == "1" ]] && ufw allow "${WEBADMIN_PORT}/tcp" comment 'UT99 webadmin' >/dev/null
  else
    warn "ufw neni aktivni - porty ${PORT}/udp a $((PORT + 1))/udp otevrete ve svem firewallu / u poskytovatele."
  fi
fi

# ----------------------------- souhrn ----------------------------------------
INFO="$UT_DIR/install-info.txt"
as_ut tee "$INFO" >/dev/null <<EOF
UT99 LeagueAS140+ server
  adresar:        $UT_DIR
  konfigurace:    $SYS64/server.ini, MapVoteLA.ini, InstaGibPlus.ini
  log:            $UT_DIR/Logs/server.log
  start URL:      $START_URL
  AS+ balicek:    $PLUS_PKG  (+ $ASSETS_PKG)
  porty:          ${PORT}/udp (hra), $((PORT + 1))/udp (query)$([[ "$WEBADMIN" == "1" ]] && echo ", ${WEBADMIN_PORT}/tcp (webadmin)")
  admin heslo:    $(grep -m1 -i '^AdminPassword=' "$SYS64/server.ini" | cut -d= -f2- | tr -d '\r')
EOF
as_ut chmod 600 "$INFO"

log "Hotovo"
cat "$INFO"
if [[ "$SKIP_SYSTEM" != "1" ]]; then
  cat <<EOF

  sluzba:   systemctl status|restart|stop ${SERVICE_NAME}
            journalctl -u ${SERVICE_NAME} -f
  overeni:  grep -i uplink $UT_DIR/Logs/server.log
EOF
else
  echo; echo "  spusteni: $UT_DIR/start.sh"
fi
