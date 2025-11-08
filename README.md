# Atrox Gateway — Vagrant & Boxes (Guía para crear y empaquetar)

Última actualización: 2025-11-08

Este README está enfocado en la capa de infraestructura para reproducir, provisionar y empaquetar las máquinas virtuales del proyecto Atrox Gateway usando Vagrant + VirtualBox. Incluye recetas para crear boxes que funcionen sin Internet (offline-ready) y consejos para solucionar problemas frecuentes durante la provisión.

Contenido
- Descripción del layout (Build vs Boxes)
- Requisitos del host
- Variables de entorno críticas
- Flujo recomendado para crear boxes "offline-ready"
- Pasos detallados y comandos
- Troubleshooting específico (ssh-copy-id, munge.key, mounts)
- Sugerencias de automatización y CI

Descripción del layout
----------------------
Este directorio contiene dos áreas principales:

1) `Atrox_Gateway_Build/` — Vagrantfile y `bootstrap-*.sh` para construir VMs desde una imagen base (por ejemplo `ubuntu/focal64`).
   - Objetivo: provisionar todas las VMs (node-app, node-login, node-storage, node-01, node-02) con todo lo necesario.
   - Resultado: VMs completamente provisionadas, apt caches llenos, builds y artefactos en su lugar.

2) `Atrox_Gateway_Boxes/` — Vagrantfile pensada para consumir boxes ya empaquetadas; incluye helpers para ejecutar un `cleanup.sh` y tareas finales.
   - Objetivo: levantar boxes ya empaquetadas para demo; aquí se deshabilita el `synced_folder` para evitar que el host sobrescriba `/opt/atrox-gateway`.

Requisitos del host
-------------------
- Vagrant (>= 2.3.x) y VirtualBox instalados.
- Recursos para pruebas locales: al menos 8 GB RAM y CPUs suficientes si vas a levantar todas las VMs locales.
- Opcional: `vagrant plugin` útiles (e.g., vagrant-disksize) si se necesitan discos más grandes.

Variables de entorno críticas
-----------------------------
- `ATROX_PASSWORD` o `VAGRANT_PASSWORD`: contraseña temporal que se exporta en el host antes de ejecutar `vagrant up`. Usada para crear el usuario `atroxgateway` y para `ssh-copy-id` durante provisión. Ejemplo:

```bash
export ATROX_PASSWORD='MiPassTemporalSegura123'
vagrant up --provider=virtualbox
```

No guardes esta variable en el repositorio. Considera usar un prompt o un archivo `.env` ignorado por git para flujos automatizados.

Flujo recomendado para crear boxes offline-ready
----------------------------------------------
1) Preparar y provisionar VMs con `Atrox_Gateway_Build/Vagrantfile`.
2) Ejecutar todos los tests de humo y validar servicios (nginx, redis, PUNs, Slurm config, NFS mounts).
3) Copiar artefactos necesarios dentro de las VMs: `munge.key`, `packages/frontend/dist`, `node_modules` (si vas a estar offline).
4) Apagar la VM objetivo (`node-app` u otras) y ejecutar `vagrant package` para generar la box.
5) Probar la box empaquetada en un directorio limpio usando `Atrox_Gateway_Boxes/Vagrantfile` o un Vagrantfile de prueba.

Pasos detallados y comandos
---------------------------
El ejemplo abajo asume que estás en `Atrox_Gateway_Build`.

1) Exportar la contraseña temporal en el host

```bash
export ATROX_PASSWORD='MiPassTemporalSegura123'
```

2) Levantar todas las VMs (puede tardar, y necesita Internet para instalar paquetes la primera vez)

```bash
cd Atrox_Gateway_Build
vagrant up --provider=virtualbox
```

3) Validar servicios en `node-app`

```bash
vagrant ssh node-app -c "nginx -t && curl -I http://127.0.0.1/ && redis-cli ping"
```

4) Si todo está OK, limpia caches y temporales dentro de la VM (opcional pero recomendado)

```bash
vagrant ssh node-app -c "sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"
```

5) Apagar la VM y empaquetar la box (en el host):

```bash
vagrant halt node-app
vagrant package --base node-app --output atrox-node-app.box
vagrant box add atrox/atrox-node-app --force atrox-node-app.box
```

6) Probar la box en un directorio nuevo (consumir la box):

```bash
mkdir test-box && cd test-box
# crear un Vagrantfile que use atrox/atrox-node-app o usar Atrox_Gateway_Boxes/Vagrantfile
vagrant init atrox/atrox-node-app
export VAGRANT_PASSWORD='MiPassTemporalSegura123'
vagrant up --provider=virtualbox
```

Troubleshooting específico
--------------------------
1) `ssh-copy-id` falla con "Permission denied"
- Causas comunes:
  - Las máquinas destino no han terminado de provisionarse.
  - `PasswordAuthentication` está deshabilitado en `sshd_config` en la máquina destino.
  - La contraseña usada por `sshpass` no coincide con la contraseña real del usuario en la máquina destino.
- Recomendaciones:
  - En `bootstrap-*.sh` del nodo destino: genera y publica la clave pública del usuario `atroxgateway` localmente, así se evita la necesidad de `ssh-copy-id` remoto desde `node-app`.
  - Añade reintentos/wait loops cuando uses `ssh-copy-id` desde `node-app` (ver ejemplo en `README` principal).
  - Asegúrate de `export ATROX_PASSWORD` en tu host antes de `vagrant up`.

2) `munge.key` no existe / fallan servicios Slurm
- Solución: coloca `shared/munge.key` en `Atrox_Gateway_Build/shared/` y asegúrate que los bootstrap scripts copian `/vagrant/shared/munge.key` a `/etc/munge/munge.key` con permisos 400 y propietario `munge:munge`.

3) Host mounts sobrescriben `/opt/atrox-gateway`
- `Atrox_Gateway_Boxes/Vagrantfile` ya contiene `config.vm.synced_folder ".", "/vagrant", disabled: true` para evitar que el host sobreescriba archivos en el packaging/consumo.

4) `npm install` falla en provisioning (sin Internet)
- Soluciones:
  - Instala `node_modules` durante la fase de build y empaqueta la box con `node_modules` incluidas.
  - O pre-descarga los tarballs y `npm ci` desde un mirror local en la VM.
