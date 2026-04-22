#!/bin/sh
# =============================================================================
# OpenWrt Mihomo Gateway — uninstaller
# Симметричен install.sh: snapshot.env → UCI symbolic restore, extroot не трогаем.
# =============================================================================
set -e

BACKUP_DIR=/root/openwrt-mihomo-backup
SNAPSHOT_FILE=$BACKUP_DIR/snapshot.env

NIKKI_PROFILE_DIR=/etc/nikki/run/profiles
AGH_DIR=/opt/adguardhome
ZAPRET_HOSTLIST=/opt/zapret/ipset/zapret-hosts-user.txt

FLAG_REMOVE_PACKAGES=0
FLAG_REMOVE_STATE=0
FLAG_RESTORE_CRONTAB=0

log() { printf '[uninstall.sh] %s\n' "$*" >&2; }
warn() { printf '[uninstall.sh][WARN] %s\n' "$*" >&2; }

usage() {
    cat <<'USAGE'
OpenWrt Mihomo Gateway — uninstaller

Usage: sh uninstall.sh [OPTIONS]

  --remove-packages     apk del nikki / luci-app-nikki / zapret / adguardhome
                        (по умолчанию пакеты остаются — только stop+disable+restore)
  --remove-state        Удалить /etc/nikki, /opt/adguardhome, /opt/zapret
                        (AGH работал на extroot; данные журналов удаляются)
  --restore-crontab     Полностью восстановить crontab из snapshot
                        (по умолчанию — только убрать '# mihomo-gateway' строки)
  -h, --help            Справка

extroot + swap НЕ трогаются. ОС/прошивку uninstaller не меняет.
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --remove-packages) FLAG_REMOVE_PACKAGES=1; shift ;;
            --remove-state) FLAG_REMOVE_STATE=1; shift ;;
            --restore-crontab) FLAG_RESTORE_CRONTAB=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) warn "Неизвестный аргумент: $1"; usage; exit 2 ;;
        esac
    done
}

# 1. Cron first (prevent update race)
stop_cron() {
    log "=== 1/8: Cron ==="
    TMP=$(mktemp)
    crontab -l 2>/dev/null > "$TMP" || : > "$TMP"
    grep -v '# mihomo-gateway' "$TMP" > "$TMP.new" || true
    if [ "$FLAG_RESTORE_CRONTAB" -eq 1 ] && [ -f "$BACKUP_DIR/crontab.orig" ]; then
        cp "$BACKUP_DIR/crontab.orig" "$TMP.new"
        log "crontab восстановлен полностью из snapshot"
    fi
    crontab "$TMP.new" 2>/dev/null || crontab - < "$TMP.new"
    rm -f "$TMP" "$TMP.new"
    /etc/init.d/cron restart 2>/dev/null || true
}

# 2. Stop + disable services
stop_services() {
    log "=== 2/8: Stop services ==="
    for _svc in zapret adguardhome nikki; do
        if [ -x "/etc/init.d/$_svc" ]; then
            "/etc/init.d/$_svc" stop 2>/dev/null || true
            "/etc/init.d/$_svc" disable 2>/dev/null || true
        fi
    done
    # Принудительно убрать наши rc.d-симлинки (на случай если --remove-packages=0
    # и init-скрипт остаётся)
    rm -f /etc/rc.d/S*nikki /etc/rc.d/S*adguardhome /etc/rc.d/S*zapret
}

# 3. Remove firewall redirect "Force DNS"
remove_firewall_redirect() {
    log "=== 3/8: Firewall redirect ==="
    _idx=0
    _any=0
    while true; do
        _n=$(uci -q get "firewall.@redirect[$_idx].name" 2>/dev/null) || break
        if [ "$_n" = "Force DNS" ]; then
            uci -q delete "firewall.@redirect[$_idx]"
            _any=1
            continue
        fi
        _idx=$((_idx+1))
    done
    if [ "$_any" -eq 1 ]; then
        uci commit firewall
        service firewall reload 2>/dev/null || true
        log "Force DNS правило удалено"
    else
        log "Force DNS правило не найдено (возможно --no-force-dns при установке)"
    fi
}

# 4. Snapshot-based UCI restore (dnsmasq :54→:53 + lan dhcp_option/dns)
restore_uci() {
    log "=== 4/8: UCI restore из snapshot ==="
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        warn "$SNAPSHOT_FILE отсутствует — UCI значения НЕ восстановлены"
        warn "Вручную: uci set dhcp.@dnsmasq[0].port=53; uci commit dhcp; service dnsmasq restart"
        return 0
    fi
    # shellcheck disable=SC1090
    . "$SNAPSHOT_FILE"

    _restore() {
        _path="$1"; _value="$2"
        if [ "$_value" = "unset" ] || [ -z "$_value" ]; then
            uci -q delete "$_path" || true
        else
            uci -q set "$_path=$_value"
        fi
    }

    _restore "dhcp.@dnsmasq[0].port" "$ORIG_DNSMASQ_PORT"
    _restore "dhcp.@dnsmasq[0].domain" "$ORIG_DNSMASQ_DOMAIN"
    _restore "dhcp.@dnsmasq[0].local" "$ORIG_DNSMASQ_LOCAL"
    _restore "dhcp.@dnsmasq[0].cachesize" "$ORIG_DNSMASQ_CACHESIZE"
    _restore "dhcp.@dnsmasq[0].noresolv" "$ORIG_DNSMASQ_NORESOLV"
    _restore "dhcp.@dnsmasq[0].expandhosts" "$ORIG_DNSMASQ_EXPANDHOSTS"

    # Списки dhcp_option/dns/server — restore каждый элемент через add_list.
    uci -q del dhcp.lan.dhcp_option
    if [ -n "$ORIG_LAN_DHCP_OPT" ] && [ "$ORIG_LAN_DHCP_OPT" != "unset" ]; then
        _IFS_bak="$IFS"; IFS='|'
        for _v in $ORIG_LAN_DHCP_OPT; do
            [ -n "$_v" ] && uci add_list dhcp.lan.dhcp_option="$_v"
        done
        IFS="$_IFS_bak"
    fi

    uci -q del dhcp.lan.dns
    if [ -n "$ORIG_LAN_DNS" ] && [ "$ORIG_LAN_DNS" != "unset" ]; then
        _IFS_bak="$IFS"; IFS='|'
        for _v in $ORIG_LAN_DNS; do
            [ -n "$_v" ] && uci add_list dhcp.lan.dns="$_v"
        done
        IFS="$_IFS_bak"
    fi

    uci -q del dhcp.@dnsmasq[0].server
    if [ -n "$ORIG_DNSMASQ_SERVER" ] && [ "$ORIG_DNSMASQ_SERVER" != "unset" ]; then
        _IFS_bak="$IFS"; IFS='|'
        for _v in $ORIG_DNSMASQ_SERVER; do
            [ -n "$_v" ] && uci add_list dhcp.@dnsmasq[0].server="$_v"
        done
        IFS="$_IFS_bak"
    fi

    uci commit dhcp
    service dnsmasq restart 2>/dev/null || true
    service odhcpd restart 2>/dev/null || true
    log "UCI значения восстановлены"
}

# 5. UCI sections of our packages — clear (nikki/zapret/adguardhome config)
clear_our_uci() {
    log "=== 5/8: Очистка нашего UCI ==="
    for _cfg in nikki zapret adguardhome; do
        if [ -f "/etc/config/$_cfg" ]; then
            # keep file (package may need it on reinstall), but reset enabled=0
            uci -q set "$_cfg.config.enabled=0" 2>/dev/null || :
            uci -q commit "$_cfg" 2>/dev/null || :
        fi
    done
}

# 6. Remove packages (optional)
remove_packages() {
    [ "$FLAG_REMOVE_PACKAGES" -eq 1 ] || { log "=== 6/8: Пакеты — оставлены (нет --remove-packages) ==="; return 0; }
    log "=== 6/8: apk del пакетов ==="
    apk del luci-i18n-nikki-ru luci-app-nikki nikki 2>/dev/null || true
    apk del luci-app-zapret zapret 2>/dev/null || true
    apk del adguardhome 2>/dev/null || true
    log "Пакеты удалены"
}

# 7. Remove state dirs (optional)
remove_state() {
    [ "$FLAG_REMOVE_STATE" -eq 1 ] || { log "=== 7/8: State — оставлены (нет --remove-state) ==="; return 0; }
    log "=== 7/8: Удаление /etc/nikki, $AGH_DIR, /opt/zapret ==="
    rm -rf /etc/nikki "$AGH_DIR" /opt/zapret
}

main() {
    parse_args "$@"
    [ "$(id -u)" -eq 0 ] || { warn "Требуются root"; exit 1; }

    log "OpenWrt Mihomo Gateway — удаление"
    stop_cron
    stop_services
    remove_firewall_redirect
    restore_uci
    clear_our_uci
    remove_packages
    remove_state

    log "=== 8/8: Готово ==="
    log "extroot + swap не тронуты. Backup остаётся в $BACKUP_DIR/"
    log "Для полной очистки: sh uninstall.sh --remove-packages --remove-state --restore-crontab"
}

main "$@"
