#!/bin/sh
# OpenWrt Mihomo Gateway — uninstaller. Симметричен install.sh:
# snapshot.env → symbolic UCI restore, stop+disable сервисов. extroot/swap
# не трогаются. License: MIT. See README.md / README_RU.md.
set -eu

BACKUP_DIR=/root/openwrt-mihomo-backup
SNAPSHOT_FILE=$BACKUP_DIR/snapshot.env

AGH_DIR=/opt/adguardhome

FLAG_REMOVE_PACKAGES=0
FLAG_REMOVE_STATE=0
FLAG_RESTORE_CRONTAB=0
FLAG_PURGE_CONFIG=0

PKG_MANAGER=""   # apk | opkg; детектится в main()

log()  { printf '[uninstall.sh] %s\n' "$*" >&2; }
warn() { printf '[uninstall.sh][WARN] %s\n' "$*" >&2; }

# Если пакетник не найден — uninstall всё равно полезен (UCI restore,
# остановка сервисов); --remove-packages в этом случае no-op с warn.
detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER=apk
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER=opkg
    else
        PKG_MANAGER=""
    fi
}

pkg_remove() {
    case "$PKG_MANAGER" in
        apk)  apk del "$@" 2>/dev/null || true ;;
        opkg) opkg remove "$@" 2>/dev/null || true ;;
        *)    warn "Пакетный менеджер не найден — пропуск: $*" ;;
    esac
}

usage() {
    cat <<'USAGE'
OpenWrt Mihomo Gateway — uninstaller

Usage: sh uninstall.sh [OPTIONS]

  --remove-packages     Удалить nikki / luci-app-nikki / zapret / adguardhome
                        (apk на 25.x, opkg на 24.10.x; детектится автоматически).
                        По умолчанию пакеты остаются.
  --remove-state        Удалить /etc/nikki, /opt/adguardhome, /opt/zapret.
  --purge-config        Удалить /etc/config/{nikki,zapret,adguardhome}. По
                        умолчанию только выставляем enabled=0 (под reinstall).
  --restore-crontab     Восстановить crontab из snapshot (по умолчанию cron
                        не трогается — install.sh не пишет маркеров).
  -h, --help            Справка.

extroot + swap НЕ трогаются. Прошивку uninstaller не меняет.
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --remove-packages) FLAG_REMOVE_PACKAGES=1; shift ;;
            --remove-state) FLAG_REMOVE_STATE=1; shift ;;
            --purge-config) FLAG_PURGE_CONFIG=1; shift ;;
            --restore-crontab) FLAG_RESTORE_CRONTAB=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) warn "Неизвестный аргумент: $1"; usage; exit 2 ;;
        esac
    done
}

# install.sh свой crontab не модифицирует, поэтому по умолчанию не трогаем.
# --restore-crontab — явный откат к версии из snapshot (если вдруг пакеты
# nikki/zapret/AGH добавили свои job'ы и пользователь хочет pristine state).
stop_cron() {
    if [ "$FLAG_RESTORE_CRONTAB" -ne 1 ]; then
        log "=== 1/8: Cron — не трогаем (нет --restore-crontab) ==="
        return 0
    fi
    log "=== 1/8: Cron restore из snapshot ==="
    if [ ! -f "$BACKUP_DIR/crontab.orig" ]; then
        warn "$BACKUP_DIR/crontab.orig отсутствует — crontab не тронут"
        return 0
    fi
    crontab "$BACKUP_DIR/crontab.orig" 2>/dev/null \
        || crontab - < "$BACKUP_DIR/crontab.orig"
    /etc/init.d/cron restart 2>/dev/null || true
    log "crontab восстановлен"
}

stop_services() {
    log "=== 2/8: Stop services ==="
    for _svc in zapret adguardhome nikki; do
        if [ -x "/etc/init.d/$_svc" ]; then
            "/etc/init.d/$_svc" stop 2>/dev/null || true
            "/etc/init.d/$_svc" disable 2>/dev/null || true
        fi
    done
    # Принудительное снятие rc.d-симлинков — на случай --remove-packages=0
    # и нашего порядка (S50/S60/S99), чтобы service не стартовал при ребуте.
    rm -f /etc/rc.d/S*nikki /etc/rc.d/S*adguardhome /etc/rc.d/S*zapret
}

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
        log "Force DNS правило не найдено"
    fi
}

# Symbolic UCI restore из snapshot.env: значения записываются обратно поверх
# текущего состояния. Файлы конфигурации не перезаписываются — чтобы не
# затереть правки, сделанные пользователем после установки.
restore_uci() {
    log "=== 4/8: UCI restore из snapshot ==="
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        warn "$SNAPSHOT_FILE отсутствует — UCI не восстановлен"
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

    # Списки — через add_list по элементам (splitter: '|').
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
    log "UCI восстановлен"
}

# UCI секции наших пакетов. По умолчанию — только enabled=0 (под reinstall).
# С --purge-config — полное удаление /etc/config/*. Восстанавливается только
# при reinstall пакета или установке из snapshot вручную.
clear_our_uci() {
    if [ "$FLAG_PURGE_CONFIG" -eq 1 ]; then
        log "=== 5/8: Удаление /etc/config/{nikki,zapret,adguardhome} ==="
        for _cfg in nikki zapret adguardhome; do
            rm -f "/etc/config/$_cfg"
        done
        return 0
    fi
    log "=== 5/8: UCI секции наших пакетов → enabled=0 ==="
    for _cfg in nikki zapret adguardhome; do
        if [ -f "/etc/config/$_cfg" ]; then
            uci -q set "$_cfg.config.enabled=0" 2>/dev/null || :
            uci -q commit "$_cfg" 2>/dev/null || :
        fi
    done
}

remove_packages() {
    [ "$FLAG_REMOVE_PACKAGES" -eq 1 ] || { log "=== 6/8: Пакеты — оставлены (нет --remove-packages) ==="; return 0; }
    if [ -z "$PKG_MANAGER" ]; then
        warn "=== 6/8: Пакетный менеджер не найден — удаление пропущено ==="
        return 0
    fi
    log "=== 6/8: $PKG_MANAGER remove пакетов ==="
    pkg_remove luci-i18n-nikki-ru luci-app-nikki nikki
    pkg_remove luci-app-zapret zapret
    pkg_remove adguardhome
}

remove_state() {
    [ "$FLAG_REMOVE_STATE" -eq 1 ] || { log "=== 7/8: State — оставлен (нет --remove-state) ==="; return 0; }
    log "=== 7/8: Удаление /etc/nikki, $AGH_DIR, /opt/zapret ==="
    rm -rf /etc/nikki "$AGH_DIR" /opt/zapret
}

main() {
    parse_args "$@"
    [ "$(id -u)" -eq 0 ] || { warn "Требуются root"; exit 1; }

    detect_pkg_manager
    log "OpenWrt Mihomo Gateway — удаление (pkg=${PKG_MANAGER:-none})"
    stop_cron
    stop_services
    remove_firewall_redirect
    restore_uci
    clear_our_uci
    remove_packages
    remove_state

    log "=== 8/8: Готово ==="
    log "extroot + swap не тронуты. Backup остаётся в $BACKUP_DIR/"
    log "Полная очистка: sh uninstall.sh --remove-packages --remove-state --purge-config --restore-crontab"
}

main "$@"
