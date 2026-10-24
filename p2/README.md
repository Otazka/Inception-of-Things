# Part 2 — K3s и три приложения

## Что требуется

Эта часть запускается отдельно от `p1`. Vagrant создаёт одну VM с именем
`mdogadinS` и адресом `192.168.56.110`. В ней устанавливается K3s в режиме
server. На кластер разворачиваются три небольших HTTP-приложения на базе
`nginx:1.29-alpine`:

| Приложение | Реплики | Host в запросе |
| --- | ---: | --- |
| app1 | 1 | `app1.com` |
| app2 | 3 | `app2.com` |
| app3 | 1 | любой другой Host или без Host |

Traefik, встроенный в K3s, принимает HTTP на адресе
`192.168.56.110`. Ingress направляет запросы `app1.com` и `app2.com` в
соответствующие сервисы, а `defaultBackend` направляет остальные запросы в
app3.

## Требования к хосту

Запуск рассчитан на школьный Linux-хост с архитектурой x86_64, Vagrant и
VirtualBox. На Mac с Apple Silicon файлы можно редактировать и проверять
синтаксис, но запустить эту x86_64 VM нельзя. Нужен доступ VM в интернет для
загрузки пакетов, K3s и образа nginx.

Внутри репозитория `p1` и `p2` используют один IP-адрес. Перед запуском
убедитесь, что VM из `p1` остановлена или удалена:

```sh
cd ../p1
vagrant halt
cd ../p2
```

Не запускайте `vagrant` через `sudo`: ключи и VM должны принадлежать вашему
пользователю.

## Запуск

Из каталога `p2`:

```sh
./scripts/up.sh
```

Скрипт проверяет Linux x86_64, наличие Vagrant и VirtualBox, валидирует
Vagrantfile, создаёт VM, передаёт в неё `apps.yaml` по SSH и запускает
проверку. Первый запуск занимает больше времени: скачиваются box, пакеты K3s
и контейнерный образ.

Эквивалентный ручной запуск:

```sh
vagrant validate
vagrant up --provider=virtualbox
./scripts/check.sh
```

Повторное применение provisioning:

```sh
vagrant provision
./scripts/check.sh
```

Полное удаление VM (данные кластера будут потеряны):

```sh
vagrant destroy
```

## Проверка результата

Внутри server:

```sh
vagrant ssh mdogadinS
hostname
ip a
systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl -n iot get deployments,pods,services,ingress
kubectl -n iot get deployment app2
exit
```

Ожидаются один узел `Ready`, три Deployment и пять pod: один pod app1,
три pod app2 и один pod app3. В объекте Deployment app2 поле `REPLICAS`
должно показывать `3/3`.

Ingress нужно показать на защите отдельно:

```sh
vagrant ssh mdogadinS -c 'sudo kubectl -n iot describe ingress iot'
```

Проверка маршрутизации с хоста:

```sh
curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl -H 'Host: other.example' http://192.168.56.110/
```

В первом ответе должна встречаться строка `Application 1`, во втором —
`Application 2`, в третьем — `Application 3`. В браузере можно открыть IP,
но для выбора app1/app2 нужен именно HTTP-заголовок `Host`; его удобно
проверять через `curl`.

## Как устроена конфигурация

### Vagrant и provisioning

`Vagrantfile` использует тот же официальный AlmaLinux box, что и `p1`, но
описывает только одну VM. Общие папки отключены, поэтому `apps.yaml`
передаётся отдельным Vagrant file provisioner в `/tmp`. Это не оставляет
зависимости от каталога репозитория внутри гостя.

`scripts/provision.sh`:

1. устанавливает `curl`, сертификаты и сетевые утилиты;
2. отключает firewalld, swap и переводит SELinux в permissive для изолированной
   учебной VM;
3. включает модули и sysctl, необходимые контейнерной сети;
4. определяет интерфейс с адресом `192.168.56.110`, не предполагая имя
   `eth1`;
5. устанавливает зафиксированную версию K3s и ждёт готовности API;
6. применяет манифесты, ждёт rollout всех Deployment и настраивает kubeconfig
   пользователя `vagrant`.

### Kubernetes-манифесты

`confs/apps.yaml` содержит namespace `iot`, три ConfigMap с HTML-страницами,
три Deployment, три ClusterIP Service и один Ingress.

ConfigMap монтируется в `index.html` контейнера nginx через `subPath`, поэтому
приложения различимы при проверке. Service скрывает pod-адреса и даёт
стабильную точку назначения для Traefik. У app2 явно указано
`spec.replicas: 3`.

Ingress использует API `networking.k8s.io/v1`, класс `traefik`, два host-based
правила и явный `defaultBackend`. Поэтому выбор приложения выполняется
маршрутизатором, а не скриптом или отдельным прокси.

## Полезная диагностика

```sh
vagrant ssh mdogadinS -c 'sudo journalctl -u k3s -n 100 --no-pager'
vagrant ssh mdogadinS -c 'sudo kubectl -n iot get pods -o wide'
vagrant ssh mdogadinS -c 'sudo kubectl -n iot describe ingress iot'
vagrant ssh mdogadinS -c 'sudo kubectl -n kube-system get pods,svc'
```

- Если VM не стартует, проверьте VT-x/AMD-V, вложенную виртуализацию и
  работоспособность kernel-модуля VirtualBox.
- Если pod имеют `Pending` или `ImagePullBackOff`, проверьте интернет внутри VM.
- Если все Host-запросы возвращают app3, проверьте точное написание заголовка
  `Host` и состояние Traefik в namespace `kube-system`.
- Если server не становится `Ready`, сначала посмотрите журнал `k3s`; при
  нехватке памяти можно увеличить `server_memory` в `confs/lab.yml` до `2048`.

## Локальная проверка файлов

На любом компьютере без запуска VM:

```sh
ruby -c Vagrantfile
bash -n scripts/provision.sh
bash -n scripts/check.sh
bash -n scripts/up.sh
```

Эти команды проверяют синтаксис. Работу Kubernetes и HTTP-маршрутизации
подтверждает только `./scripts/up.sh` на Linux x86_64.
