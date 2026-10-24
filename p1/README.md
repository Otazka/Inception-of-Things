# Part 1 — K3s и Vagrant

Целевая среда: **Linux x86_64 + VirtualBox** на школьном компьютере.
На Mac с Apple Silicon можно редактировать файлы и проверять синтаксис,
но запуск этой конфигурации заблокирован: её гостевые системы — x86_64.

| Машина / hostname | Выделенный IP | K3s | CPU | RAM |
| --- | --- | --- | --- | --- |
| `mdogadinS` | `192.168.56.110/24` | server (controller) | 1 | 1024 МБ |
| `mdogadinSW` | `192.168.56.111/24` | agent (worker) | 1 | 1024 МБ |

Первый интерфейс каждой VM использует NAT для интернета и SSH Vagrant.
Второй подключён к общей host-only сети `192.168.56.0/24`.
K3s использует второй интерфейс для адресов узлов и Flannel.
Название интерфейса скрипт находит по IP, без предположений об `eth1`.

## Перед запуском в школе

1. Установить Vagrant и совместимый VirtualBox на **Linux-хосте**.
   Нужны рабочий модуль VirtualBox в ядре и аппаратная виртуализация VT-x/AMD-V.
2. По общему условию subject проект выполняется внутри виртуальной машины.
   Если Linux для проекта сам запущен как VM, включить для него **nested
   virtualization** в наружном гипервизоре: внутри него Vagrant создаёт ещё две VM.
   Если школьный компьютер не разрешает вложенную виртуализацию, потребуется
   настроить среду вместе с администратором.
3. Обеспечить доступ к интернету из хоста и обеих VM: каталог AlmaLinux,
   репозитории пакетов, `get.k3s.io`, GitHub и реестры контейнеров.
4. Убедиться, что адреса `.110` и `.111` не заняты другими лабораторными VM.
5. Проверить `confs/lab.yml`: школьный логин уже установлен в `mdogadin`.

Используются AlmaLinux **10.2**, официальный box **10.2.20261012** и K3s
**v1.36.5+k3s1**. Версии проверены 24 октября 2026 года и зафиксированы
в `confs/lab.yml`, чтобы server и agent получали одинаковый K3s.
Перед более поздней защитой проверить актуальность стабильного Linux и box.
Образ `x86_64_v2` требует процессор уровня x86-64-v2; это не ARM-образ.

Box скачивается из собственного каталога AlmaLinux на S3, явно указанного
в `config.vm.box_url`; HashiCorp registry не используется. Контрольная сумма
образа предоставляется официальным каталогом и проверяется Vagrant.

## Запуск

Из корня репозитория на школьном Linux:

```sh
cd p1
./scripts/up.sh
```

Скрипт проверяет платформу, наличие инструментов, выполняет `vagrant validate`,
запускает server, затем agent и проверяет оба узла. Первый запуск требует времени
на загрузку образа, пакетов и контейнеров.

Эквивалентные команды вручную:

```sh
vagrant validate
vagrant up --provider=virtualbox --no-parallel
./scripts/check.sh
```

При обычной работе не запускать `vagrant` через `sudo`: иначе его VM и ключи
будут принадлежать root.

## Проверка на защите

```sh
vagrant status
vagrant ssh mdogadinS
```

Внутри server:

```sh
hostname
ip a
systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl get pods -A
exit
```

Ожидаются ровно два узла в состоянии `Ready`, с Internal-IP
`192.168.56.110` и `192.168.56.111`. Kubernetes требует имена узлов в нижнем
регистре, поэтому там они называются `mdogadins` и `mdogadinsw`; имена VM и
hostname сохраняют требуемые суффиксы `S` и `SW`. Agent может иметь роль
`<none>` в выводе `kubectl get nodes`: это обычное поведение K3s, не ошибка.

Проверка worker и SSH без пароля:

```sh
vagrant ssh mdogadinSW
hostname
ip a
systemctl status k3s-agent --no-pager
exit
```

`kubectl` устанавливается вместе с K3s на обеих машинах. Административный
kubeconfig настроен для пользователя `vagrant` на server, поэтому после
интерактивного `vagrant ssh mdogadinS` доступен обычный `kubectl` без sudo.
Для неинтерактивной команды можно использовать:

```sh
vagrant ssh mdogadinS -c 'sudo kubectl get nodes -o wide'
```

Vagrant использует SSH-ключи. Его конфигурацию подключения можно посмотреть
через `vagrant ssh-config`; пароль для `vagrant ssh` не нужен.

## Устройство provisioning

- `Vagrantfile` создаёт обе VM и передаёт им один случайный токен через SSH.
- `scripts/provision.sh` подготавливает сеть, модули ядра, отключает swap,
  записывает `/etc/rancher/k3s/config.yaml` и устанавливает systemd-сервис K3s.
- Server запускает управляющие компоненты и SQLite; agent подключается к
  `https://192.168.56.110:6443` с тем же токеном.
- Traefik, ServiceLB и metrics-server отключены в этой части для экономии памяти.
  CoreDNS и стандартная сеть Flannel остаются включены.
- Внутри лабораторных VM firewalld отключён, SELinux переведён в permissive.
  K3s installer пока выбирает EL9 policy RPM для AlmaLinux 10, поэтому его
  установка пропускается. Настройки Linux-хоста скрипт не меняет.
- Токен хранится в `.runtime/cluster-token` с правами `0600`, исключён из Git
  и скопирован в root-only файл внутри каждой VM. Общих папок нет.
- `scripts/check.sh` проверяет SSH, архитектуру, адреса, службы, наличие ровно
  двух узлов и их состояние `Ready`.

## Остановка и повторный запуск

```sh
vagrant halt
./scripts/up.sh
```

Чтобы повторить настройку уже созданных VM:

```sh
vagrant provision mdogadinS
vagrant provision mdogadinSW
./scripts/check.sh
```

Чтобы удалить обе лабораторные VM и создать заново (их данные будут потеряны):

```sh
vagrant destroy
./scripts/up.sh
```

Не удалять `.runtime/cluster-token`, пока существуют VM: это их общий токен.
После удаления **обеих** VM можно удалить и `.runtime`, чтобы при следующем
запуске создать новый токен. На другой компьютер переносится репозиторий;
локальные `.vagrant` и `.runtime` переносить не нужно — там создаётся новый кластер.

## Если запуск не проходит

- **`VT-x/AMD-V` / `VERR_VMX_NO_VMX`**: проверить аппаратную и вложенную
  виртуализацию. ARM-хост не подходит для этого VirtualBox x86_64 lab.
- **`VERR_VMX_IN_VMX_ROOT_MODE`**: проверить конфликт VirtualBox с KVM.
  Не отключать гипервизоры школьного компьютера вслепую; сначала выяснить,
  какие VM их используют.
- **Ошибка host-only сети**: проверить существующие сети через
  `VBoxManage list hostonlyifs`, доступность `192.168.56.0/24` и отсутствие
  конфликтующих VM. Этот диапазон входит в стандартный разрешённый диапазон
  VirtualBox, если администратор не изменил настройки.
- **Server не готов / OOM**: subject советует 1 CPU и 512–1024 МБ, но текущая
  документация K3s указывает минимум 2 CPU и 2 ГБ для server. Здесь установлен
  облегчённый профиль 1 CPU / 1024 МБ по subject; если на школьной машине его
  недостаточно, увеличить `server_memory` до `2048` и при необходимости `cpus`
  до `2` в `confs/lab.yml`, затем выполнить `vagrant reload` и проверку.
- **Worker не присоединился**: проверить server, сеть и общий токен, затем
  повторить `vagrant provision mdogadinSW`.

Диагностика:

```sh
vagrant ssh mdogadinS -c 'sudo journalctl -u k3s -n 100 --no-pager'
vagrant ssh mdogadinSW -c 'sudo journalctl -u k3s-agent -n 100 --no-pager'
```

## Локальные проверки на Mac

```sh
ruby -c Vagrantfile
bash -n scripts/provision.sh
bash -n scripts/up.sh
bash -n scripts/check.sh
```

Эти команды проверяют синтаксис. Полную работоспособность подтверждает только
запуск `./scripts/up.sh` на целевом Linux x86_64 с получением двух `Ready` узлов.

## Документация

- [Официальные AlmaLinux Vagrant boxes](https://wiki.almalinux.org/installation/vagrant-boxes.html)
- [Собственный каталог AlmaLinux вне HCP](https://github.com/AlmaLinux/cloud-images/blob/main/VAGRANT_BUILD_TEST_PUBLISH.md#the-vagrant-box-catalog)
- [K3s: установка и подключение agent](https://docs.k3s.io/quick-start)
- [K3s: конфигурация](https://docs.k3s.io/installation/configuration)
- [K3s: требования и сеть](https://docs.k3s.io/installation/requirements)
