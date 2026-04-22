#!/bin/sh
# OpenWrt Mihomo Gateway Installer — mihomo (via nikki) + zapret + AdGuard Home + Force-DNS.
# Target: OpenWrt releases in SUPPORTED_RELEASES (opkg on 24.10.x, apk on 25.x).
# BusyBox ash compatible. License: MIT. See README.md / README_RU.md.
set -eu

# --- constants ---
BACKUP_DIR=/root/openwrt-mihomo-backup
SNAPSHOT_FILE=$BACKUP_DIR/snapshot.env

NIKKI_PROFILE_DIR=/etc/nikki/run/profiles
NIKKI_PROFILE_NAME=main
NIKKI_PROFILE_FILE=$NIKKI_PROFILE_DIR/$NIKKI_PROFILE_NAME.yaml

AGH_DIR=/opt/adguardhome
AGH_CONF=$AGH_DIR/AdGuardHome.yaml

ZAPRET_HOSTLIST=/opt/zapret/ipset/zapret-hosts-user.txt

# Tested releases. Extend via env: SUPPORTED_RELEASES="25.12.3" sh install.sh
SUPPORTED_RELEASES="${SUPPORTED_RELEASES:-24.10.0 24.10.1 24.10.2 25.04.0 25.12.0 25.12.1 25.12.2}"
MIN_OVERLAY_KB=$((2 * 1024 * 1024))    # 2 GiB
MIN_SWAP_KB=$((1 * 1024 * 1024))       # 1 GiB
MIN_RAM_KB=200000                       # 200 MB

# Architectures for which nikki and zapret publish packages. Silent apk/opkg "no
# such package" is hard to diagnose, so refuse on unknown DISTRIB_ARCH early.
# Env-override: SUPPORTED_ARCHES="..." sh install.sh
SUPPORTED_ARCHES="${SUPPORTED_ARCHES:-mipsel_24kc mips_24kc aarch64_cortex-a53 aarch64_cortex-a72 aarch64_generic arm_cortex-a7 arm_cortex-a7_neon-vfpv4 arm_cortex-a9 arm_cortex-a9_vfpv3-d16 arm_cortex-a15_neon-vfpv4 x86_64 i386_pentium4 i386_pentium-mmx}"

DETECTED_RELEASE=""
DETECTED_ARCH=""
DETECTED_TARGET=""
PKG_MANAGER=""   # apk | opkg

# Remote scripts we execute with `sh` — pinned URLs (SEC).
NIKKI_FEED_URL='https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh'
ZAPRET_INSTALLER_URL='https://raw.githubusercontent.com/remittor/zapret-openwrt/zap1/zapret/update-pkg.sh'

# Starting NFQWS strategy. May need per-ISP tuning via /opt/zapret/blockcheck.sh.
DEFAULT_NFQWS_OPT='--filter-tcp=80 --dpi-desync=fake,multisplit --dpi-desync-fooling=md5sig <HOSTLIST> --new
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq,md5sig --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin <HOSTLIST> --new
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin <HOSTLIST>'

# --- CLI defaults ---
VLESS_URL=""

# Priority: --vless-* override > URL value > fallback default.
# URL-поля парсятся через _set_if_empty, т.е. не перезаписывают то,
# что уже задано override-флагом.
VLESS_SERVER=""
VLESS_PORT=""
VLESS_UUID=""
VLESS_PUBKEY=""
VLESS_SID=""
VLESS_SNI=""
VLESS_FLOW=""
VLESS_FP=""
VLESS_NETWORK=""
VLESS_SECURITY=""

VLESS_PORT_DEFAULT=443
VLESS_SNI_DEFAULT="www.google.com"
VLESS_FLOW_DEFAULT="xtls-rprx-vision"
VLESS_FP_DEFAULT="chrome"
VLESS_NETWORK_DEFAULT="tcp"
VLESS_SECURITY_DEFAULT="reality"

NFQWS_OPT=""
LAN_IP=""

FLAG_NO_ADGUARD=0
FLAG_NO_ZAPRET=0
FLAG_NO_I18N=0
FLAG_NO_FORCE_DNS=0
FLAG_FORCE_CONFIG=0
FLAG_NON_INTERACTIVE=0

# --- logging ---
# INSTALL_STARTED=1 после snapshot — die() печатает hint только после первой мутации.
INSTALL_STARTED=0
log()  { printf '[install.sh] %s\n' "$*" >&2; }
warn() { printf '[install.sh][WARN] %s\n' "$*" >&2; }
die() {
    printf '[install.sh][ERROR] %s\n' "$*" >&2
    if [ "$INSTALL_STARTED" = "1" ]; then
        printf '[install.sh] Установка прервана после начала мутаций. Откат: sh uninstall.sh\n' >&2
    fi
    exit 1
}
# refuse() — ошибка до первой мутации, отдельный exit code 2.
refuse() {
    printf '[install.sh][REFUSE] %s\n' "$*" >&2
    exit 2
}

usage() {
    cat <<USAGE
OpenWrt Mihomo Gateway Installer
Релизы: $SUPPORTED_RELEASES
Пакетник: apk (25.x) или opkg (24.10.x), детектится автоматически.

Usage: sh install.sh [OPTIONS]

VLESS:
  --vless-url URL       vless://UUID@host:port?type=tcp&security=reality
                                &pbk=...&sni=...&sid=...&flow=xtls-rprx-vision&fp=chrome#label
                        Без флага — промпт (кроме --non-interactive).

  Override отдельных полей (перезаписывают значения из URL):
  --vless-server HOST   --vless-port N
  --vless-uuid UUID     --vless-pubkey KEY
  --vless-sid HEX       --vless-sni HOST
  --vless-flow NAME     --vless-fp NAME

Zapret:
  --nfqws-opt "..."     Строка NFQWS_OPT (дефолт — стартовая из README).
  --no-zapret           Не устанавливать zapret.

AdGuard Home:
  --no-adguard          Не устанавливать AGH.
  --force-config        Перезаписать существующий AdGuardHome.yaml и nikki-профиль.

Прочее:
  --no-force-dns        Не добавлять firewall-правило Force DNS.
  --no-i18n             Не ставить luci-i18n-nikki-ru.
  --non-interactive     Без промптов; отсутствие --vless-url = die.
  -h, --help            Справка.

Env:
  SUPPORTED_RELEASES="X.Y.Z ..."   Расширить allowlist релизов.
  SUPPORTED_ARCHES="..."           Расширить allowlist архитектур.

Exit codes:
  0 — успех, self-test пройден
  1 — ошибка после начала мутаций (см. hint про uninstall.sh)
  2 — preflight refuse (release/arch/pkg/extroot/conflicts/VLESS URL)
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --vless-url)    VLESS_URL="$2"; shift 2 ;;
            --vless-server) VLESS_SERVER="$2"; shift 2 ;;
            --vless-port)   VLESS_PORT="$2"; shift 2 ;;
            --vless-uuid)   VLESS_UUID="$2"; shift 2 ;;
            --vless-pubkey) VLESS_PUBKEY="$2"; shift 2 ;;
            --vless-sid)    VLESS_SID="$2"; shift 2 ;;
            --vless-sni)    VLESS_SNI="$2"; shift 2 ;;
            --vless-flow)   VLESS_FLOW="$2"; shift 2 ;;
            --vless-fp)     VLESS_FP="$2"; shift 2 ;;
            --nfqws-opt)    NFQWS_OPT="$2"; shift 2 ;;
            --no-zapret)    FLAG_NO_ZAPRET=1; shift ;;
            --no-adguard)   FLAG_NO_ADGUARD=1; shift ;;
            --no-i18n)      FLAG_NO_I18N=1; shift ;;
            --no-force-dns) FLAG_NO_FORCE_DNS=1; shift ;;
            --force-config) FLAG_FORCE_CONFIG=1; shift ;;
            --non-interactive) FLAG_NON_INTERACTIVE=1; shift ;;
            -h|--help)      usage; exit 0 ;;
            *) warn "Неизвестный аргумент: $1"; usage; exit 2 ;;
        esac
    done

    # Force DNS без AGH — DNAT lan:53 → LAN_IP:53, но на LAN_IP:53 никто не
    # слушает (dnsmasq на :54, mihomo на :1053). DNS у клиентов сломается.
    if [ "$FLAG_NO_ADGUARD" -eq 1 ] && [ "$FLAG_NO_FORCE_DNS" -eq 0 ]; then
        refuse "--no-adguard несовместим с включённым Force DNS. Добавь --no-force-dns явно."
    fi
}

# --- VLESS URL parser (BusyBox ash) ---
_urldecode() {
    # BusyBox sed не поддерживает \xHH в замене: sed вставляет литеральную
    # backslash-x форму, printf %b её интерпретирует.
    printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

_set_if_empty() {
    eval "_cur=\$$1"
    [ -n "$_cur" ] && return 0
    eval "$1=\"\$2\""
}

parse_vless_url() {
    _url="$1"
    case "$_url" in
        vless://*) _s="${_url#vless://}" ;;
        *) die "Ожидался URL вида vless://..., получено: $_url" ;;
    esac
    _s="${_s%%#*}"
    case "$_s" in
        *\?*)
            _auth="${_s%%\?*}"
            _query="${_s#*\?}"
            ;;
        *)
            _auth="$_s"
            _query=""
            ;;
    esac
    case "$_auth" in
        *@*) : ;;
        *) die "Некорректный VLESS URL: нет '@' (ожидался UUID@host:port)" ;;
    esac
    _uuid="${_auth%%@*}"
    _hp="${_auth#*@}"
    # IPv6-брекеты не поддерживаются — VLESS-панели обычно отдают IPv4/домен.
    case "$_hp" in
        *:*)
            _host="${_hp%:*}"
            _port="${_hp##*:}"
            ;;
        *)
            _host="$_hp"
            _port=443
            ;;
    esac

    _set_if_empty VLESS_UUID   "$_uuid"
    _set_if_empty VLESS_SERVER "$_host"
    _set_if_empty VLESS_PORT   "$_port"

    _IFS_bak="$IFS"; IFS='&'
    for _kv in $_query; do
        [ -z "$_kv" ] && continue
        _k="${_kv%%=*}"
        _v="${_kv#*=}"
        [ "$_v" = "$_kv" ] && continue
        _v_dec=$(_urldecode "$_v")
        case "$_k" in
            type)       _set_if_empty VLESS_NETWORK  "$_v_dec" ;;
            security)   _set_if_empty VLESS_SECURITY "$_v_dec" ;;
            pbk)        _set_if_empty VLESS_PUBKEY   "$_v_dec" ;;
            sni)        _set_if_empty VLESS_SNI      "$_v_dec" ;;
            sid)        _set_if_empty VLESS_SID      "$_v_dec" ;;
            flow)       _set_if_empty VLESS_FLOW     "$_v_dec" ;;
            fp)         _set_if_empty VLESS_FP       "$_v_dec" ;;
            encryption|spx|allowInsecure|headerType) : ;;
            *) warn "parse_vless_url: неизвестный параметр '$_k' — пропуск" ;;
        esac
    done
    IFS="$_IFS_bak"
}

# --- package manager dispatch ---
detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER=apk
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER=opkg
    else
        refuse "Не найден ни apk, ни opkg — это не похоже на OpenWrt"
    fi
}

pkg_update() {
    case "$PKG_MANAGER" in
        apk)  apk update ;;
        opkg) opkg update ;;
        *)    die "PKG_MANAGER не задан (внутренняя ошибка)" ;;
    esac
}

pkg_install() {
    case "$PKG_MANAGER" in
        apk)  apk add --no-interactive "$@" ;;
        opkg) opkg install "$@" ;;
        *)    die "PKG_MANAGER не задан" ;;
    esac
}

# Для nikki feed: ключ подписи может не быть в системе.
pkg_install_untrusted() {
    case "$PKG_MANAGER" in
        apk)  apk add --no-interactive --allow-untrusted "$@" ;;
        opkg) opkg install "$@" ;;
        *)    die "PKG_MANAGER не задан" ;;
    esac
}

# --- Step 1: preflight release + arch + pkg manager ---
preflight_release() {
    log "=== Step 1/12: Preflight — OpenWrt release + architecture + pkg manager ==="
    [ "$(id -u)" -eq 0 ] || refuse "Требуются права root"
    [ -f /etc/openwrt_release ] || refuse "Это не OpenWrt (нет /etc/openwrt_release)"

    # shellcheck disable=SC1091
    . /etc/openwrt_release
    _release="${DISTRIB_RELEASE:-unknown}"
    _arch="${DISTRIB_ARCH:-unknown}"
    _target="${DISTRIB_TARGET:-unknown}"

    _rel_ok=0
    for _r in $SUPPORTED_RELEASES; do
        [ "$_r" = "$_release" ] && { _rel_ok=1; break; }
    done
    if [ "$_rel_ok" -eq 0 ]; then
        refuse "OpenWrt $_release не в SUPPORTED_RELEASES.
Поддерживаются: $SUPPORTED_RELEASES
Расширение: SUPPORTED_RELEASES=\"$_release\" sh install.sh"
    fi

    _arch_ok=0
    for _a in $SUPPORTED_ARCHES; do
        [ "$_a" = "$_arch" ] && { _arch_ok=1; break; }
    done
    if [ "$_arch_ok" -eq 0 ]; then
        refuse "Архитектура '$_arch' не в allowlist'е nikki+zapret.
Поддерживаются: $SUPPORTED_ARCHES
Расширение: SUPPORTED_ARCHES=\"$_arch\" sh install.sh"
    fi
    DETECTED_RELEASE="$_release"
    DETECTED_ARCH="$_arch"
    DETECTED_TARGET="$_target"

    detect_pkg_manager

    _ram_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    [ "$_ram_kb" -ge "$MIN_RAM_KB" ] \
        || refuse "Недостаточно RAM: ${_ram_kb} kB < ${MIN_RAM_KB} kB"

    log "Окружение: OpenWrt $_release / $_arch / target=$_target / pkg=$PKG_MANAGER / RAM=${_ram_kb}kB"
}

# --- Step 2: extroot + swap ---
preflight_extroot() {
    log "=== Step 2/12: Preflight — extroot + swap ==="

    # /overlay должен быть на отдельном блочном устройстве: если остался на
    # rootfs_data (внутренний NAND/NOR), место кончится при первой же установке.
    _overlay_src=$(awk '$2 == "/overlay" {print $1; exit}' /proc/mounts 2>/dev/null)
    [ -n "$_overlay_src" ] \
        || refuse "/overlay не смонтирован — extroot обязателен (README §Подготовка)"
    case "$_overlay_src" in
        /dev/sd[a-z][0-9]*|/dev/mmcblk[0-9]*p[0-9]*|/dev/nvme[0-9]*n[0-9]*p[0-9]*) : ;;
        *) refuse "/overlay смонтирован с '$_overlay_src' — ожидается USB/SD/NVMe (extroot не настроен)" ;;
    esac

    _overlay_kb=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $2}')
    if [ -z "$_overlay_kb" ] || [ "$_overlay_kb" -lt "$MIN_OVERLAY_KB" ]; then
        refuse "/overlay слишком мал: ${_overlay_kb:-0} kB < ${MIN_OVERLAY_KB} kB"
    fi

    _swap_kb=$(awk 'NR>1 {sum+=$3} END{print sum+0}' /proc/swaps 2>/dev/null)
    [ "$_swap_kb" -ge "$MIN_SWAP_KB" ] \
        || refuse "Swap не активен или мал: ${_swap_kb:-0} kB < ${MIN_SWAP_KB} kB"

    log "extroot: $_overlay_src → /overlay = ${_overlay_kb} kB; swap = ${_swap_kb} kB"
}

# --- Step 3: conflict probes ---
preflight_conflicts() {
    log "=== Step 3/12: Preflight — conflict probes ==="
    _conflicts=""

    for _proc in xray sing-box mihomo adguardhome v2ray hysteria; do
        if pidof "$_proc" >/dev/null 2>&1; then
            _conflicts="${_conflicts}
  - запущен процесс: $_proc"
        fi
    done
    for _init in /etc/init.d/podkop /etc/init.d/passwall /etc/init.d/passwall2 /etc/init.d/passwall_server /etc/init.d/xray-tproxy; do
        [ -e "$_init" ] && _conflicts="${_conflicts}
  - найден init-скрипт: $_init"
    done

    _lan=$(uci -q get network.lan.device 2>/dev/null || uci -q get network.lan.ifname 2>/dev/null || echo "")
    case "$_lan" in
        br-lan) : ;;
        "") _conflicts="${_conflicts}
  - пустой network.lan.device (ожидался br-lan)" ;;
        *) _conflicts="${_conflicts}
  - нестандартный LAN: network.lan.device=$_lan (ожидалось br-lan)" ;;
    esac

    # :53 должен держать dnsmasq или никто. Сторонний резолвер в стеке → refuse.
    _port53_listening=0
    if command -v ss >/dev/null 2>&1; then
        ss -lntu 2>/dev/null | awk 'NR>1 && $4 ~ /:53$/ {f=1; exit} END{exit !f}' \
            && _port53_listening=1
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lntu 2>/dev/null | awk 'NR>2 && $4 ~ /:53$/ {f=1; exit} END{exit !f}' \
            && _port53_listening=1
    fi
    if [ "$_port53_listening" -eq 1 ] && ! pidof dnsmasq >/dev/null 2>&1; then
        _conflicts="${_conflicts}
  - :53 занят, но dnsmasq не запущен (сторонний DNS в стеке)"
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 10 https://github.com >/dev/null 2>&1 \
            || _conflicts="${_conflicts}
  - нет интернета (curl https://github.com не прошёл)"
    else
        # curl будет поставлен в install_base_packages — пока fallback на wget.
        wget -q --spider --timeout=10 https://github.com 2>/dev/null \
            || _conflicts="${_conflicts}
  - нет интернета (wget https://github.com не прошёл)"
    fi

    if [ -n "$_conflicts" ]; then
        printf '[install.sh][REFUSE] Обнаружены конфликты или проблемы среды:%s\n' "$_conflicts" >&2
        exit 2
    fi

    log "Среда чистая — конфликтов нет"
}

# --- Step 4: collect + parse + validate VLESS params ---
collect_vless_input() {
    log "=== Step 4/12: Сбор и разбор VLESS URL ==="

    if [ -z "$VLESS_URL" ]; then
        # Full-override режим: если хоть одно поле задано флагом — URL не нужен.
        if [ -z "$VLESS_SERVER" ] && [ -z "$VLESS_UUID" ] && [ -z "$VLESS_PUBKEY" ]; then
            [ "$FLAG_NON_INTERACTIVE" -eq 1 ] \
                && die "--non-interactive: требуется --vless-url или полный --vless-* override"
            printf "VLESS URL (vless://UUID@host:port?type=tcp&security=reality&pbk=...&sni=...&sid=...&flow=...&fp=chrome#label):\n> "
            read -r VLESS_URL
            [ -n "$VLESS_URL" ] || die "Пустой URL"
        fi
    fi

    [ -n "$VLESS_URL" ] && parse_vless_url "$VLESS_URL"

    [ -n "$VLESS_PORT" ]     || VLESS_PORT="$VLESS_PORT_DEFAULT"
    [ -n "$VLESS_SNI" ]      || VLESS_SNI="$VLESS_SNI_DEFAULT"
    [ -n "$VLESS_FLOW" ]     || VLESS_FLOW="$VLESS_FLOW_DEFAULT"
    [ -n "$VLESS_FP" ]       || VLESS_FP="$VLESS_FP_DEFAULT"
    [ -n "$VLESS_NETWORK" ]  || VLESS_NETWORK="$VLESS_NETWORK_DEFAULT"
    [ -n "$VLESS_SECURITY" ] || VLESS_SECURITY="$VLESS_SECURITY_DEFAULT"

    # Строгие allowlist'ы (SEC: значения подставляются в YAML без escaping'a).
    case "$VLESS_SERVER" in
        "") die "VLESS server не определён" ;;
        *[!A-Za-z0-9.:_-]*) die "VLESS_SERVER: допустимы A-Z a-z 0-9 . : _ - (получено: $VLESS_SERVER)" ;;
    esac
    case "$VLESS_PORT" in
        ""|*[!0-9]*) die "VLESS_PORT: только цифры (получено: $VLESS_PORT)" ;;
    esac
    if ! { [ "$VLESS_PORT" -ge 1 ] 2>/dev/null && [ "$VLESS_PORT" -le 65535 ] 2>/dev/null; }; then
        die "VLESS_PORT вне 1..65535: $VLESS_PORT"
    fi
    case "$VLESS_UUID" in
        "") die "VLESS UUID не определён" ;;
        *[!A-Za-z0-9-]*) die "VLESS_UUID: только A-Z a-z 0-9 -" ;;
    esac
    case "$VLESS_PUBKEY" in
        "") die "Reality public-key не определён (pbk= в URL или --vless-pubkey)" ;;
        *[!A-Za-z0-9_-]*) die "VLESS_PUBKEY: допустимы A-Z a-z 0-9 _ - (base64url)" ;;
    esac
    case "$VLESS_SID" in
        "") die "Reality short-id не определён (sid= в URL или --vless-sid)" ;;
        *[!A-Fa-f0-9]*) die "VLESS_SID: только hex" ;;
    esac
    case "$VLESS_SNI" in
        "") die "SNI не определён" ;;
        *[!A-Za-z0-9.-]*) die "VLESS_SNI: только домен (a-z 0-9 . -)" ;;
    esac
    case "$VLESS_FLOW" in
        ""|*[!A-Za-z0-9._-]*) die "VLESS_FLOW: только A-Z a-z 0-9 . _ -" ;;
    esac
    case "$VLESS_FP" in
        ""|*[!A-Za-z0-9._-]*) die "VLESS_FP: только A-Z a-z 0-9 . _ -" ;;
    esac
    [ "$VLESS_SECURITY" = "reality" ] \
        || die "Поддерживается только security=reality (получено: $VLESS_SECURITY)"
    [ "$VLESS_NETWORK" = "tcp" ] \
        || warn "type=$VLESS_NETWORK не tcp — профиль сгенерируется, но тестирована только type=tcp"

    if [ -z "$NFQWS_OPT" ]; then
        NFQWS_OPT="$DEFAULT_NFQWS_OPT"
        log "NFQWS_OPT: дефолтная стратегия (может требовать blockcheck-настройки)"
    fi

    # Маска UUID для лога — показываем 4 первых и 4 последних символа.
    _uuid_len=$(printf '%s' "$VLESS_UUID" | wc -c | awk '{print $1}')
    if [ "$_uuid_len" -ge 8 ]; then
        _uuid_prefix=$(printf '%s' "$VLESS_UUID" | cut -c1-4)
        _uuid_suffix=$(printf '%s' "$VLESS_UUID" | awk '{print substr($0,length-3)}')
        _uuid_masked="${_uuid_prefix}...${_uuid_suffix}"
    else
        _uuid_masked="***"
    fi

    log "VLESS параметры собраны:"
    log "  server       = $VLESS_SERVER:$VLESS_PORT"
    log "  uuid         = $_uuid_masked"
    log "  sni          = $VLESS_SNI"
    log "  flow         = $VLESS_FLOW / fp=$VLESS_FP / network=$VLESS_NETWORK"
    log "  zapret       = $( [ "$FLAG_NO_ZAPRET" -eq 1 ] && echo skip || echo install )"
    log "  adguardhome  = $( [ "$FLAG_NO_ADGUARD" -eq 1 ] && echo skip || echo install )"
    log "  force-dns    = $( [ "$FLAG_NO_FORCE_DNS" -eq 1 ] && echo no || echo yes )"
    log "  i18n-nikki   = $( [ "$FLAG_NO_I18N" -eq 1 ] && echo no || echo yes )"

    if [ "$FLAG_NON_INTERACTIVE" -ne 1 ]; then
        printf "Продолжить установку? [Y/n]: "
        read -r ans
        case "$ans" in
            n|N|no|No) refuse "Установка отменена пользователем" ;;
        esac
    fi
}

# --- Step 5: snapshot state ---
snapshot_state() {
    log "=== Step 5/12: Pre-install state snapshot ==="
    umask 077
    mkdir -p "$BACKUP_DIR"
    # chmod 700 — snapshot.env содержит старые UCI-значения, в т.ч. возможные
    # DNS/DHCP-записи от предыдущей конфигурации. Исключаем чтение от nobody.
    chmod 700 "$BACKUP_DIR" 2>/dev/null || warn "Не удалось chmod 700 $BACKUP_DIR"
    INSTALL_STARTED=1

    if [ -f "$SNAPSHOT_FILE" ] && [ "$FLAG_FORCE_CONFIG" -ne 1 ]; then
        warn "Snapshot уже существует — сохраняю pristine state (перезапись: --force-config)"
        return 0
    fi

    _orig_dnsmasq_port=$(uci -q get "dhcp.@dnsmasq[0].port" || echo unset)
    _orig_dnsmasq_domain=$(uci -q get "dhcp.@dnsmasq[0].domain" || echo unset)
    _orig_dnsmasq_local=$(uci -q get "dhcp.@dnsmasq[0].local" || echo unset)
    _orig_dnsmasq_cachesize=$(uci -q get "dhcp.@dnsmasq[0].cachesize" || echo unset)
    _orig_dnsmasq_noresolv=$(uci -q get "dhcp.@dnsmasq[0].noresolv" || echo unset)
    _orig_dnsmasq_expandhosts=$(uci -q get "dhcp.@dnsmasq[0].expandhosts" || echo unset)

    # Списки — как pipe-separated; пустая option → unset.
    _orig_lan_dhcp_opt=$(uci -q -d'|' get dhcp.lan.dhcp_option 2>/dev/null || echo unset)
    _orig_lan_dns=$(uci -q -d'|' get dhcp.lan.dns 2>/dev/null || echo unset)
    _orig_dnsmasq_server=$(uci -q -d'|' get "dhcp.@dnsmasq[0].server" 2>/dev/null || echo unset)

    cat > "$SNAPSHOT_FILE" <<EOF
ORIG_DNSMASQ_PORT='$_orig_dnsmasq_port'
ORIG_DNSMASQ_DOMAIN='$_orig_dnsmasq_domain'
ORIG_DNSMASQ_LOCAL='$_orig_dnsmasq_local'
ORIG_DNSMASQ_CACHESIZE='$_orig_dnsmasq_cachesize'
ORIG_DNSMASQ_NORESOLV='$_orig_dnsmasq_noresolv'
ORIG_DNSMASQ_EXPANDHOSTS='$_orig_dnsmasq_expandhosts'
ORIG_LAN_DHCP_OPT='$_orig_lan_dhcp_opt'
ORIG_LAN_DNS='$_orig_lan_dns'
ORIG_DNSMASQ_SERVER='$_orig_dnsmasq_server'
INSTALL_DATE='$(date -Iseconds 2>/dev/null || date)'
INSTALL_FLAGS='no_adguard=$FLAG_NO_ADGUARD no_zapret=$FLAG_NO_ZAPRET no_i18n=$FLAG_NO_I18N no_force_dns=$FLAG_NO_FORCE_DNS'
INSTALL_RELEASE='$DETECTED_RELEASE'
INSTALL_ARCH='$DETECTED_ARCH'
INSTALL_PKG_MANAGER='$PKG_MANAGER'
EOF

    for _src in /etc/config/network /etc/config/dhcp /etc/config/firewall /etc/hosts; do
        [ -f "$_src" ] || continue
        cp -a "$_src" "$BACKUP_DIR/$(basename "$_src").orig" 2>/dev/null \
            || warn "Не удалось скопировать $_src"
    done
    if command -v nft >/dev/null 2>&1; then
        nft list ruleset > "$BACKUP_DIR/nftables.ruleset" 2>/dev/null || : > "$BACKUP_DIR/nftables.ruleset"
    fi
    crontab -l 2>/dev/null > "$BACKUP_DIR/crontab.orig" || : > "$BACKUP_DIR/crontab.orig"

    chmod 600 "$BACKUP_DIR"/* 2>/dev/null || :
    log "Snapshot: $BACKUP_DIR/ (network/dhcp/firewall/hosts/nftables/crontab + snapshot.env)"
}

# --- Step 6: base packages ---
install_base_packages() {
    log "=== Step 6/12: Установка базовых пакетов ($PKG_MANAGER) ==="
    pkg_update 2>&1 | tail -5 || warn "$PKG_MANAGER update вернул предупреждения"
    pkg_install curl ca-bundle block-mount e2fsprogs kmod-fs-ext4 \
        kmod-usb-storage kmod-usb-storage-uas kmod-usb3 \
        || die "Ошибка $PKG_MANAGER install (базовые пакеты)"
}

# --- Step 7: nikki (mihomo) ---
fetch_script() {
    _url="$1"
    _out=$(mktemp)
    curl -fsSL --max-time 60 --proto '=https' --proto-redir '=https' "$_url" -o "$_out" \
        || { rm -f "$_out"; die "Не удалось скачать $_url"; }
    [ -s "$_out" ] || { rm -f "$_out"; die "Скачан пустой файл: $_url"; }
    printf '%s' "$_out"
}

install_nikki() {
    log "=== Step 7/12: nikki (mihomo) ==="
    _feed_script=$(fetch_script "$NIKKI_FEED_URL")
    log "Запуск nikki feed.sh (добавляет репозиторий $PKG_MANAGER)"
    ash "$_feed_script" || { rm -f "$_feed_script"; die "nikki feed.sh вернул ошибку (возможно, $PKG_MANAGER не поддержан upstream'ом)"; }
    rm -f "$_feed_script"

    pkg_update 2>&1 | tail -5 || warn "$PKG_MANAGER update после добавления nikki feed"
    _nikki_pkgs="nikki luci-app-nikki"
    [ "$FLAG_NO_I18N" -eq 0 ] && _nikki_pkgs="$_nikki_pkgs luci-i18n-nikki-ru"
    # shellcheck disable=SC2086
    pkg_install_untrusted $_nikki_pkgs \
        || die "Ошибка установки nikki (подпись feed'а или отсутствие пакетов под $PKG_MANAGER)"
    log "nikki установлен: $_nikki_pkgs"
}

# --- Step 8: zapret ---
install_zapret() {
    [ "$FLAG_NO_ZAPRET" -eq 1 ] && { log "=== Step 8/12: zapret — пропущено (--no-zapret) ==="; return 0; }
    log "=== Step 8/12: zapret (remittor) ==="
    _zapret_script=$(fetch_script "$ZAPRET_INSTALLER_URL")
    log "Запуск remittor update-pkg.sh -u 1"
    sh "$_zapret_script" -u 1 || { rm -f "$_zapret_script"; die "remittor update-pkg.sh вернул ошибку"; }
    rm -f "$_zapret_script"
    command -v nfqws >/dev/null 2>&1 || die "nfqws не найден после установки zapret"
}

# --- Step 9: AdGuard Home ---
install_adguard() {
    [ "$FLAG_NO_ADGUARD" -eq 1 ] && { log "=== Step 9/12: AdGuard Home — пропущено (--no-adguard) ==="; return 0; }
    log "=== Step 9/12: AdGuard Home ==="
    pkg_install adguardhome || die "Ошибка $PKG_MANAGER install adguardhome"
    command -v AdGuardHome >/dev/null 2>&1 \
        || [ -x /usr/bin/AdGuardHome ] || [ -x /usr/sbin/AdGuardHome ] \
        || warn "Бинарник AdGuardHome не найден в PATH — пакет установлен, проверь службу"
}

# --- Step 10: configure services ---
configure_nikki() {
    log "--- Nikki profile + UCI ---"
    mkdir -p "$NIKKI_PROFILE_DIR"

    if [ -f "$NIKKI_PROFILE_FILE" ] && [ "$FLAG_FORCE_CONFIG" -ne 1 ]; then
        warn "$NIKKI_PROFILE_FILE существует — пропускаю (--force-config для перезаписи)"
    else
        _tmp=$(mktemp)
        cat > "$_tmp" <<EOF
mixed-port: 7890
tproxy-port: 7891
redir-port: 7892
allow-lan: true
mode: rule
log-level: warning
external-controller: 127.0.0.1:9090
secret: ""

dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '+.local'
    - '+.internal'
    - 'time.*.com'
    - 'time.*.gov'
    - '*.ntp.org'
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver-policy:
    '+.ru,+.рф,+.su,+.by,+.kz':
      - https://dns.yandex.ru/dns-query
      - https://common.dot.dns.yandex.ru
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
  fallback:
    - tls://dns.adguard-dns.com

proxies:
  - name: "VLESS-REALITY"
    type: vless
    server: $VLESS_SERVER
    port: $VLESS_PORT
    uuid: $VLESS_UUID
    network: tcp
    tls: true
    udp: true
    flow: $VLESS_FLOW
    servername: $VLESS_SNI
    reality-opts:
      public-key: $VLESS_PUBKEY
      short-id: $VLESS_SID
    client-fingerprint: chrome

proxy-groups:
  - name: "PROXY"
    type: select
    proxies: [VLESS-REALITY, DIRECT]
  - name: "YOUTUBE"
    type: select
    proxies: [DIRECT, VLESS-REALITY]
  - name: "FINAL"
    type: select
    proxies: [VLESS-REALITY, DIRECT]

rule-providers:
  ru-blocked:
    type: http
    behavior: domain
    format: text
    url: "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-custom-routing-list/main/release/mihomo/ru-blocked.list"
    path: ./rule-sets/ru-blocked.list
    interval: 86400

rules:
  - GEOIP,LAN,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve

  - DOMAIN-SUFFIX,youtube.com,YOUTUBE
  - DOMAIN-SUFFIX,googlevideo.com,YOUTUBE
  - DOMAIN-SUFFIX,ytimg.com,YOUTUBE
  - DOMAIN-SUFFIX,youtu.be,YOUTUBE
  - DOMAIN-SUFFIX,ggpht.com,YOUTUBE
  - DOMAIN-SUFFIX,yt3.ggpht.com,YOUTUBE
  - DOMAIN-SUFFIX,yt4.ggpht.com,YOUTUBE

  - DOMAIN-SUFFIX,ru,DIRECT
  - DOMAIN-SUFFIX,su,DIRECT
  - DOMAIN-SUFFIX,рф,DIRECT
  - GEOIP,RU,DIRECT

  - RULE-SET,ru-blocked,PROXY

  - MATCH,FINAL
EOF
        mv "$_tmp" "$NIKKI_PROFILE_FILE"
        chmod 600 "$NIKKI_PROFILE_FILE"
        log "Записан $NIKKI_PROFILE_FILE"
    fi

    # luci-app-nikki схема: config 'nikki' section 'config'. Режим redir_tun —
    # баланс TCP/UDP для слабых CPU (TProxy TCP + TUN для UDP).
    uci -q set nikki.config=nikki 2>/dev/null || uci -q add nikki nikki >/dev/null 2>&1 || :
    uci set nikki.config.enabled='1'
    uci set nikki.config.profile="$NIKKI_PROFILE_NAME"
    uci set nikki.config.mode='redir_tun'
    uci commit nikki 2>/dev/null || warn "uci commit nikki — проверь схему пакета в LuCI"
}

configure_zapret() {
    [ "$FLAG_NO_ZAPRET" -eq 1 ] && return 0
    log "--- Zapret UCI ---"
    uci -q batch <<EOF
set zapret.config=zapret
set zapret.config.enabled='1'
set zapret.config.mode='nfqws'
set zapret.config.mode_filter='hostlist'
set zapret.config.nfqws_tcp_port='80,443'
set zapret.config.nfqws_udp_port='443'
set zapret.config.disable_ipv6='1'
EOF
    uci set zapret.config.nfqws_opt="$NFQWS_OPT"
    uci commit zapret 2>/dev/null || warn "uci commit zapret — проверь схему в LuCI"

    mkdir -p "$(dirname "$ZAPRET_HOSTLIST")"
    cat > "$ZAPRET_HOSTLIST" <<'EOF'
youtube.com
googlevideo.com
ytimg.com
youtu.be
ggpht.com
yt3.ggpht.com
yt4.ggpht.com
googleapis.com
gvt1.com
gvt2.com
EOF
    log "zapret hostlist: $ZAPRET_HOSTLIST ($(wc -l < "$ZAPRET_HOSTLIST") записей)"
}

# dnsmasq переводится на :54, :53 освобождается для AGH. DHCP-клиентам раздаётся
# $LAN_IP как DNS (option 6) и gateway (option 3), см.
# https://openwrt.org/docs/guide-user/services/dns/adguard-home
migrate_dnsmasq_to_agh() {
    [ "$FLAG_NO_ADGUARD" -eq 1 ] && return 0
    log "--- dnsmasq → :54, AGH займёт :53 ---"

    _dev=$(uci -q get network.lan.device || echo br-lan)
    _lan_ip=$(/sbin/ip -o -4 addr list "$_dev" 2>/dev/null | awk 'NR==1{split($4,a,"/"); print a[1]; exit}')
    [ -n "$_lan_ip" ] || _lan_ip=$(uci -q get network.lan.ipaddr || echo 192.168.1.1)
    LAN_IP="$_lan_ip"
    log "LAN_IP=$LAN_IP (interface=$_dev)"

    uci -q batch <<EOF
set dhcp.@dnsmasq[0].port=54
set dhcp.@dnsmasq[0].domain=lan
set dhcp.@dnsmasq[0].local=/lan/
set dhcp.@dnsmasq[0].expandhosts=1
set dhcp.@dnsmasq[0].cachesize=0
set dhcp.@dnsmasq[0].noresolv=1
EOF
    # Предупреждаем о перезаписи существующих кастомных DHCP/DNS-опций. Они
    # сохранены в snapshot.env и восстанавливаются uninstall.sh'ом.
    if [ -n "$(uci -q get dhcp.lan.dhcp_option 2>/dev/null)" ]; then
        warn "dhcp.lan.dhcp_option заменяется нашим (3,6,15). Прежние — в snapshot.env"
    fi
    if [ -n "$(uci -q get dhcp.lan.dns 2>/dev/null)" ]; then
        warn "dhcp.lan.dns сбрасывается. Прежние — в snapshot.env"
    fi
    if [ -n "$(uci -q get 'dhcp.@dnsmasq[0].server' 2>/dev/null)" ]; then
        warn "dhcp.@dnsmasq[0].server сбрасывается. Прежние — в snapshot.env"
    fi
    uci -q del dhcp.@dnsmasq[0].server
    uci -q del dhcp.lan.dhcp_option
    uci -q del dhcp.lan.dns
    uci add_list dhcp.lan.dhcp_option="3,$LAN_IP"
    uci add_list dhcp.lan.dhcp_option="6,$LAN_IP"
    uci add_list dhcp.lan.dhcp_option="15,lan"
    uci commit dhcp

    service dnsmasq restart 2>/dev/null || warn "dnsmasq restart: проверь вручную"
    service odhcpd restart 2>/dev/null || :
    log "dnsmasq переведён на :54"
}

configure_adguard() {
    [ "$FLAG_NO_ADGUARD" -eq 1 ] && return 0
    log "--- AdGuard Home config ---"
    mkdir -p "$AGH_DIR"

    uci set adguardhome.config.workdir="$AGH_DIR" 2>/dev/null || :
    uci commit adguardhome 2>/dev/null || :

    if [ -f "$AGH_CONF" ] && [ "$FLAG_FORCE_CONFIG" -ne 1 ]; then
        warn "$AGH_CONF существует — пропускаю (--force-config для перезаписи)"
        return 0
    fi

    # users=[] → AGH поднимает мастер на :3000 при первом заходе (BusyBox без
    # bcrypt, сгенерировать пароль заранее не можем). Остальное пре-сидим.
    _tmp=$(mktemp)
    cat > "$_tmp" <<EOF
bind_host: 0.0.0.0
bind_port: 3000
users: []
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ru
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  statistics_interval: 720h
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 24h
  querylog_size_memory: 1000
  anonymize_client_ip: false
  protection_enabled: true
  blocking_mode: default
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_response_ttl: 10
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  ratelimit: 20
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
    - "[/lan/]127.0.0.1:54"
    - "[/pool.ntp.org/]1.1.1.1"
    - "[/pool.ntp.org/]1.0.0.1"
    - "127.0.0.1:1053"
  upstream_dns_file: ""
  bootstrap_dns:
    - 1.1.1.1
    - 8.8.8.8
  fallback_dns: []
  upstream_mode: load_balance
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: false
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_prefer_ipv6: false
  upstream_timeout: 10s
  private_networks: []
  use_private_ptr_resolvers: true
  local_ptr_upstreams:
    - 127.0.0.1:54
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: true
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt
    name: AdGuard Russian filter
    id: 4
  - enabled: true
    url: https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt
    name: HaGeZi Encrypted DNS/VPN/TOR/Proxy Bypass
    id: 10
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
tls:
  enabled: false
querylog:
  ignored:
    - "*.arpa"
  interval: 24h
  size_memory: 1000
  enabled: true
  file_enabled: true
statistics:
  ignored:
    - "*.arpa"
  interval: 720h
  enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log:
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 20
EOF
    mv "$_tmp" "$AGH_CONF"
    chmod 600 "$AGH_CONF"
    log "Записан $AGH_CONF (мастер: http://$LAN_IP:3000)"
}

install_dns_interception() {
    [ "$FLAG_NO_FORCE_DNS" -eq 1 ] && { log "--- DNS interception — пропущено (--no-force-dns) ---"; return 0; }
    log "--- Firewall redirect: Force DNS ---"
    _lan_ip="${LAN_IP:-$(uci -q get network.lan.ipaddr || echo 192.168.1.1)}"

    # Удаляем старые redirect'ы с нашим именем (идемпотентность). После delete
    # индексы сдвигаются, поэтому не инкрементим _idx на continue.
    _idx=0
    while true; do
        _n=$(uci -q get "firewall.@redirect[$_idx].name" 2>/dev/null) || break
        if [ "$_n" = "Force DNS" ]; then
            uci -q delete "firewall.@redirect[$_idx]"
            continue
        fi
        _idx=$((_idx+1))
    done

    uci -q add firewall redirect >/dev/null
    uci -q batch <<EOF
set firewall.@redirect[-1].name='Force DNS'
set firewall.@redirect[-1].src='lan'
set firewall.@redirect[-1].src_dport='53'
set firewall.@redirect[-1].target='DNAT'
set firewall.@redirect[-1].proto='tcpudp'
set firewall.@redirect[-1].family='ipv4'
set firewall.@redirect[-1].dest_ip='$_lan_ip'
set firewall.@redirect[-1].dest_port='53'
EOF
    uci commit firewall
    service firewall reload 2>/dev/null || warn "firewall reload — проверь вручную"
    log "Force DNS: lan:53 → $_lan_ip:53"
}

# Порядок: nikki должен подняться раньше AGH, чтобы при первом форвард-запросе
# AGH :53 → mihomo :1053 был доступен. Zapret — последним (сеть уже поднята).
fix_service_order() {
    log "--- Порядок запуска служб ---"
    if [ "$FLAG_NO_ADGUARD" -eq 0 ] && [ -x /etc/init.d/adguardhome ]; then
        rm -f /etc/rc.d/S*adguardhome
        ln -sf /etc/init.d/adguardhome /etc/rc.d/S60adguardhome
    fi
    if [ -x /etc/init.d/nikki ]; then
        rm -f /etc/rc.d/S*nikki
        ln -sf /etc/init.d/nikki /etc/rc.d/S50nikki
    fi
    if [ "$FLAG_NO_ZAPRET" -eq 0 ] && [ -x /etc/init.d/zapret ]; then
        rm -f /etc/rc.d/S*zapret
        ln -sf /etc/init.d/zapret /etc/rc.d/S99zapret
    fi
    log "S50nikki → S60adguardhome → S99zapret"
}

enable_and_start_services() {
    log "=== Step 11/12: Enable + start services ==="
    if [ -x /etc/init.d/nikki ]; then
        /etc/init.d/nikki enable 2>/dev/null || :
        /etc/init.d/nikki restart || warn "nikki restart вернул ошибку — logread"
    fi
    if [ "$FLAG_NO_ADGUARD" -eq 0 ] && [ -x /etc/init.d/adguardhome ]; then
        /etc/init.d/adguardhome enable 2>/dev/null || :
        /etc/init.d/adguardhome restart || warn "adguardhome restart — logread"
    fi
    if [ "$FLAG_NO_ZAPRET" -eq 0 ] && [ -x /etc/init.d/zapret ]; then
        /etc/init.d/zapret enable 2>/dev/null || :
        /etc/init.d/zapret restart || warn "zapret restart — logread"
    fi
    # 3 сек на привязку сокетов перед self-test'ом.
    sleep 3
}

# --- Step 12: self-test ---
selftest() {
    log "=== Step 12/12: Self-test ==="
    _fail=0
    _report=""

    _check() {
        _name="$1"; shift
        if "$@" >/dev/null 2>&1; then
            _report="${_report}
  [PASS] $_name"
        else
            _report="${_report}
  [FAIL] $_name"
            _fail=$((_fail+1))
        fi
    }

    _check_port() {
        _name="$1"; _port="$2"
        if command -v ss >/dev/null 2>&1; then
            _out=$(ss -lntu 2>/dev/null | awk -v p=":$_port" '$4 ~ p {f=1; exit} END{exit !f}' && echo ok)
        else
            _out=$(netstat -lntu 2>/dev/null | awk -v p=":$_port" '$4 ~ p {f=1; exit} END{exit !f}' && echo ok)
        fi
        if [ "$_out" = "ok" ]; then
            _report="${_report}
  [PASS] $_name"
        else
            _report="${_report}
  [FAIL] $_name (:$_port не слушается)"
            _fail=$((_fail+1))
        fi
    }

    _check "service nikki running" pidof mihomo
    _check_port "dnsmasq :54" 54
    _check_port "mihomo DNS :1053" 1053
    _check_port "mihomo external-controller :9090" 9090

    if [ "$FLAG_NO_ADGUARD" -eq 0 ]; then
        _check "AdGuardHome running" pidof AdGuardHome
        _check_port "AdGuardHome :53" 53
        _check_port "AdGuardHome admin :3000" 3000
    fi
    if [ "$FLAG_NO_ZAPRET" -eq 0 ]; then
        _check "nfqws running" pidof nfqws
        # Проверяем, что zapret понял плейсхолдер <HOSTLIST> и подставил путь
        # к hostlist-файлу в аргументы nfqws. Если remittor сменит формат,
        # nfqws запустится, но без фильтра — YouTube работать не будет.
        if pidof nfqws >/dev/null 2>&1; then
            if pgrep -af nfqws 2>/dev/null | grep -q -- '--hostlist'; then
                _report="${_report}
  [PASS] nfqws запущен с --hostlist (плейсхолдер <HOSTLIST> подставлен)"
            else
                _report="${_report}
  [FAIL] nfqws запущен БЕЗ --hostlist. Проверь формат NFQWS_OPT и /opt/zapret/config"
                _fail=$((_fail+1))
            fi
        fi
    fi
    if [ "$FLAG_NO_FORCE_DNS" -eq 0 ]; then
        _check "firewall: Force DNS redirect" \
            sh -c 'uci show firewall | grep -q "name=.Force DNS."'
    fi

    printf '[install.sh] Self-test:%s\n' "$_report" >&2

    [ "$_fail" -eq 0 ] || die "Self-test: $_fail проверок провалено. См. logread и README."
    log "Self-test: все проверки пройдены"
}

print_summary() {
    _lan_ip="${LAN_IP:-$(uci -q get network.lan.ipaddr || echo 192.168.1.1)}"
    cat >&2 <<EOF

------------------------------------------------------------------------
Установка OpenWrt Mihomo Gateway завершена.
Окружение: OpenWrt $DETECTED_RELEASE / $DETECTED_ARCH / target=$DETECTED_TARGET / pkg=$PKG_MANAGER

Пост-установка (вручную):
  1. AdGuard Home wizard: http://${_lan_ip}:3000
     Admin-interface на ${_lan_ip}:8080, DNS bind на all interfaces:53, задать пароль.
  2. Если YouTube тормозит или не открывается:
     service zapret stop
     /opt/zapret/blockcheck.sh   # 10–20 минут подбора
     → обновить NFQWS_OPT в LuCI → Services → Zapret

Проверка с клиента LAN:
  nslookup youtube.com ${_lan_ip}     # fake-IP 198.18.x.x (mihomo)
  nslookup yandex.ru ${_lan_ip}       # реальный IP
  curl https://ifconfig.me            # IP VPS, если идёт в PROXY
  curl https://yandex.ru/internet     # ваш домашний IP

Откат: sh uninstall.sh
Backup: ${BACKUP_DIR}/
------------------------------------------------------------------------
EOF
}

main() {
    parse_args "$@"
    preflight_release
    preflight_extroot
    preflight_conflicts
    collect_vless_input
    snapshot_state
    install_base_packages
    install_nikki
    install_zapret
    install_adguard
    log "=== Step 10/12: Конфигурация сервисов ==="
    configure_nikki
    configure_zapret
    migrate_dnsmasq_to_agh
    configure_adguard
    install_dns_interception
    fix_service_order
    enable_and_start_services
    selftest
    print_summary
}

main "$@"
