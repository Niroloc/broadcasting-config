# broadcasting-config

Раздача конфига sing-box на устройства через секретный gist. Конфиг шифруется (AES-256, openssl), устройство раз в сутки забирает его, проверяет `sing-box check`, применяет и пишет результат в [`reports.csv`](reports.csv).

## Локально (откуда публикуем)

```sh
cp .env.example .env              # GIST_ID, GITHUB_TOKEN (fine-grained, Gists: RW), KEY
$EDITOR config.json               # конфиг sing-box, в git не попадает
./publish.sh
```

## OpenWrt-роутер

Зависимости — в зависимости от версии:

```sh
# OpenWrt 24.10 и более ранние — opkg
opkg update && opkg install curl openssl-util

# OpenWrt 25.12+ и snapshot — apk
apk update && apk add curl openssl-util
```

Дальше одинаково:

```sh
wget -O /usr/bin/sing-box-sync https://raw.githubusercontent.com/Niroloc/broadcasting-config/main/sync.sh
chmod +x /usr/bin/sing-box-sync
wget -O /etc/sing-box-sync.conf https://raw.githubusercontent.com/Niroloc/broadcasting-config/main/sync.conf.example
chmod 600 /etc/sing-box-sync.conf && vi /etc/sing-box-sync.conf
sing-box-sync                                     # проверка вручную
echo "$((RANDOM%60)) 4 * * * /usr/bin/sing-box-sync" >> /etc/crontabs/root && /etc/init.d/cron restart
printf '/usr/bin/sing-box-sync\n/etc/sing-box-sync.conf\n' >> /etc/sysupgrade.conf
```

`REPORT_TOKEN` — fine-grained PAT только на этот репозиторий, Contents: RW. Если не задать `REPORT_REPO`, результат идёт только в syslog (`logread -e sing-box-sync`).

## Другой Linux

То же самое, но в конфиге указать `TARGET` и `RESTART="systemctl restart sing-box"`, а запуск повесить на cron или systemd-таймер.

## Статусы в reports.csv

`updated` · `unchanged` · `fail` (`download` / `decrypt` / `check`) · `rollback` (sing-box не поднялся после рестарта, вернули прошлый конфиг). `config_sha` — первые 12 символов sha256 конфига, `publish.sh` выводит такой же.
