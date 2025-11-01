#!/usr/bin/env bash
set -e

sudo apt-get update -y
sudo apt-get install -y nfs-kernel-server

echo "Configurando /etc/hosts..."
echo "192.168.56.10 app" | sudo tee -a /etc/hosts
echo "192.168.56.11 node-login" | sudo tee -a /etc/hosts
echo "192.168.56.12 node-storage" | sudo tee -a /etc/hosts
echo "192.168.56.13 node-01" | sudo tee -a /etc/hosts
echo "192.168.56.14 node-02" | sudo tee -a /etc/hosts

sudo useradd -m -s /bin/bash -u 1002 atroxgateway && echo "atroxgateway:P@ssw0rd123!" | sudo chpasswd
sudo usermod -aG sudo atroxgateway

echo "atroxgateway ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/atroxgateway
echo "Defaults:atroxgateway !requiretty" | sudo tee -a /etc/sudoers.d/atroxgateway
sudo chmod 0440 /etc/sudoers.d/atroxgateway

echo "/home    192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo mkdir -p /opt/apps
sudo chown atroxgateway:atroxgateway /opt/apps || true
echo "/opt/apps 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -a
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi
sudo systemctl restart sshd

set -euo pipefail

# Minimal, idempotent installer for Spack + Lmod into /opt/apps (meant to run on node-storage)
# - Instala paquetes necesarios
# - Crea /opt/apps (propiedad de atroxgateway si existe)
# - Instala Lmod into /opt/apps/Lmod
# - Clona Spack into /opt/apps/spack
# - Configura un modules.yaml mínimo para Spack que genere módulos Lmod en /opt/apps/modules

APT_PKGS=(git build-essential curl wget python3 python3-venv lua5.3 liblua5.3-dev libreadline-dev libssl-dev zlib1g-dev libncurses5-dev cmake pkg-config tcl)

echo "Instalando dependencias APT (puede pedir tiempo)..."
sudo apt-get update -y
sudo apt-get install -y "${APT_PKGS[@]}"

sudo mkdir -p /opt/apps
if id -u atroxgateway >/dev/null 2>&1; then
  sudo chown atroxgateway:atroxgateway /opt/apps || true
fi

mkdir -p /tmp/spack_lmod_install
cd /tmp/spack_lmod_install

# ...existing code...
echo "Instalando Lmod en /opt/apps/Lmod (si no existe)..."
if [ ! -d "/opt/apps/Lmod" ]; then
  # Ensure tclsh is available for Lmod configure
  if ! command -v tclsh >/dev/null 2>&1; then
    echo "tclsh no encontrado, instalando paquete 'tcl'..."
    sudo apt-get update -y
    sudo apt-get install -y tcl
  fi

  # Ensure Tcl development headers (tcl.h) are present. Try common package names as fallbacks.
  # Use conditional to avoid set -e exiting on failure of a single apt attempt.
  if ! compgen -G "/usr/include/tcl*.h" >/dev/null 2>&1; then
    echo "tcl.h no encontrado. Intentando instalar paquete devel de Tcl (tcl8.6-dev / tcl-dev)..."
    if ! sudo apt-get install -y tcl8.6-dev >/dev/null 2>&1; then
      if ! sudo apt-get install -y tcl-dev >/dev/null 2>&1; then
        echo "No se pudo instalar paquete tcl devel por apt; como fallback se configurará Lmod para no requerir fastTCLInterp."
        TCL_DEV_INSTALLED=false
      else
        TCL_DEV_INSTALLED=true
      fi
    else
      TCL_DEV_INSTALLED=true
    fi
  else
    TCL_DEV_INSTALLED=true
  fi

  # Ensure lua posix module is available for lua5.3
  if ! lua -e "require('posix')" >/dev/null 2>&1; then
    echo "Modulo lua 'posix' no encontrado. Intentando instalar paquete 'luaposix'..."
    if ! sudo apt-get install -y luaposix >/dev/null 2>&1; then
      echo "Paquete 'luaposix' no disponible via apt. Intentando instalar via luarocks..."
      # Install luarocks if necessary
      if ! command -v luarocks >/dev/null 2>&1; then
        sudo apt-get update -y
        sudo apt-get install -y luarocks || true
      fi
      if command -v luarocks >/dev/null 2>&1; then
        # Prefer installing for lua5.3 if supported
        sudo luarocks --lua-version=5.3 install luaposix || sudo luarocks install luaposix || true
      else
        echo "No se pudo instalar 'luaposix' (ni apt ni luarocks disponibles). Lmod puede fallar si no se instala posix para lua."
      fi
    fi
  fi

  git clone https://github.com/TACC/Lmod.git /tmp/Lmod || true
  cd /tmp/Lmod

  # If Tcl devel headers are missing, configure Lmod to not require fastTCLInterp.
  if [ "${TCL_DEV_INSTALLED:-true}" != "true" ]; then
    echo "Configurando Lmod con --with-fastTCLInterp=no (no se encontraron headers de Tcl)..."
    ./configure --prefix=/opt/apps/Lmod --with-fastTCLInterp=no
  else
    ./configure --prefix=/opt/apps/Lmod
  fi

  make -j"$(nproc)"
  sudo make install
else
  echo "Lmod ya existe en /opt/apps/Lmod, saltando instalación."
fi

# ...existing code...
echo "Instalando Spack en /opt/apps/spack (si no existe)..."
if [ ! -d "/opt/apps/spack" ]; then
  git clone https://github.com/spack/spack.git /opt/apps/spack
else
  echo "Spack ya existe en /opt/apps/spack, saltando clone."
fi

echo "Creando directorio de módulos Lmod en /opt/apps/modules..."
sudo mkdir -p /opt/apps/modules
sudo chown -R atroxgateway:atroxgateway /opt/apps/modules 2>/dev/null || true

SPACK_ETC=/opt/apps/spack/etc/spack
if [ -d "$SPACK_ETC" ]; then
  echo "Creando configuración mínima modules.yaml para Spack -> Lmod"
  sudo mkdir -p "$SPACK_ETC"
  sudo tee "$SPACK_ETC/modules.yaml" > /dev/null <<'MODULES'
modules:
  enable:
    lmod: {}
  lmod:
    roots:
      lmod: /opt/apps/modules
MODULES
fi

echo "Creando /etc/profile.d/lmod.sh para inicializar Lmod en el arranque (si no existe)..."
if [ ! -f /etc/profile.d/lmod.sh ]; then
  sudo tee /etc/profile.d/lmod.sh > /dev/null <<'PROFILE'
# Lmod initialization for all users (installed under /opt/apps)
if [ -f /opt/apps/Lmod/lmod/lmod/init/bash ]; then
  # shellcheck disable=SC1091
  source /opt/apps/Lmod/lmod/lmod/init/bash
  export MODULEPATH=/opt/apps/modules:${MODULEPATH}
fi
PROFILE
  sudo chmod 644 /etc/profile.d/lmod.sh
else
  echo "/etc/profile.d/lmod.sh ya existe, no se sobrescribe."
fi

echo "Limpieza temporal..."
rm -rf /tmp/spack_lmod_install /tmp/Lmod || true

echo "Instalación básica completada. Siguientes pasos sugeridos:\n - En clientes: cerrar y abrir sesión o 'source /etc/profile.d/lmod.sh' para cargar Lmod.\n - Desde cualquier nodo: source /opt/apps/spack/share/spack/setup-env.sh y ejecutar 'spack install' como usuario de builds (por ejemplo atroxgateway) si quieres compilar paquetes.\n - Si quieres que ejecute builds como 'atroxgateway', entra en node-storage: 'vagrant ssh node-storage' y ejecutar: 'sudo -u atroxgateway /opt/apps/spack/bin/spack install <paquete>'"

exit 0