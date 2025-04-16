
#Creation root system

#for ARCH in amd64 arm64 armel; do
for ARCH in amd64 arm64 ; do

  # creation du systeme de base
  #debootstrap --arch ${ARCH} --variant=minbase --components=main,contrib,non-free,non-free-firmware --no-check-gpg --no-check-certificate --include=wget,vim,sysvinit-core,rsync,subversion,git,locales,openssh-client,ca-certificates,debian-keyring,dialog,ncurses-bin,curl,less,procps --exclude='systemd*','dbus*',apparmor,nano bookworm ${ARCH}_dir
debootstrap --arch ${ARCH} --variant=minbase --components=main,contrib,non-free,non-free-firmware --no-check-gpg --no-check-certificate --include=wget,sysvinit-core,rsync,subversion,git,locales,openssh-client,ca-certificates,debian-keyring,dialog,ncurses-bin,curl,procps --exclude='systemd*','dbus*',apparmor,nano bookworm ${ARCH}_dir


  # Si jamais on doit utiliser vi dans le container...
  cat > ${ARCH}_dir/etc/vim/vimrc.local <<EOF
let g:skip_defaults_vim = 1
set mouse=
set bg=dark
EOF


  # Les locales
  echo LANG="en_US" > ${ARCH}_dir/etc/default/locale
  sed -i -e 's/^# en_US/en_US/g' -e 's/^# fr_FR/fr_FR/g' ${ARCH}_dir/etc/locale.gen 


  # La timezone
  echo Europe/Paris > ${ARCH}_dir/etc/timezone
  rm -f ${ARCH}_dir/etc/localtime
  ln -sf /usr/share/zoneinfo/Europe/Paris ${ARCH}_dir/etc/localtime


  # APT
  cat > ${ARCH}_dir/etc/apt/sources.list <<EOF
deb [allow-insecure=yes trusted=yes] http://ftp.fr.debian.org/debian/ bookworm main non-free contrib non-free-firmware
deb [allow-insecure=yes trusted=yes] http://ftp.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb [allow-insecure=yes trusted=yes] https://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
#  if [ ${ARCH} == "amd64" ] ; then 
#    cat > ${ARCH}_dir/etc/apt/sources.list.d/myrepo.list <<EOF
#deb [allow-insecure=yes trusted=yes] http://myrepo.mydomain bookworm stuff
#EOF
#  fi

  cat > ${ARCH}_dir/etc/apt/preferences.d/nosystemd <<EOF
Package: systemd
Pin: release *
Pin-Priority: -1

Package: apparmor
Pin: release *
Pin-Priority: -1

Package: dbus
Pin: release *
Pin-Priority: -1
EOF


  cat > ${ARCH}_dir/etc/dpkg/dpkg.cfg.d/99_docker-nodoc  <<EOF

# Delete locales
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/fr*
path-include=/usr/share/locale/en*
path-include=/usr/share/locale/locale.alias

# Delete man pages
path-exclude=/usr/share/man/*

# Delete docs
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright

EOF

  rm -rf ${ARCH}_dir/usr/share/doc/*
  rm -rf ${ARCH}_dir/usr/share/man/*
  mkdir ${ARCH}_dir/usr/share/localesave && cp -dpR ${ARCH}_dir/usr/share/locale/locale.alias ${ARCH}_dir/usr/share/locale/fr* ${ARCH}_dir/usr/share/locale/en* ${ARCH}_dir/usr/share/localesave/ && rm -rf ${ARCH}_dir/usr/share/locale/* && mv ${ARCH}_dir/usr/share/localesave/*  ${ARCH}_dir/usr/share/locale/ && rmdir ${ARCH}_dir/usr/share/localesave


  echo 'APT::Get::AllowUnauthenticated "true" ;' > ${ARCH}_dir/etc/apt/apt.conf.d/80cleancrap

  # DNS - Pas sûr si ca utilise ca ou le DNS host de toute facon
  cat > ${ARCH}_dir/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF


  cat > ${ARCH}_dir/post_inst.sh <<EOF
#!/bin/bash


# Les locales...
locale-gen
update-locale --no-checks LANG="en_US"



# APT
apt -y update
apt-get -y dist-upgrade

# Un peu de cleaning au besoin
# Note : en principe, pas besoin d'init du tout (pas plus que de kernel & co), mais avoir sysvinit light au cas ou, ca évite qu'une dependance installe systemd & co
apt-get -y install sysvinit-core
apt-get -y remove --purge 'systemd*' 'dbus*' 'apparmor*'
apt-get -y autoremove --purge

apt-get clean
apt-get autoclean

# Nettoyage liste APT (90 Mo) et cache (idem)
# Il faudra faire un apt-get update avant prochain usage
rm -rf /var/lib/apt/lists/* 2>/dev/null
rm -rf /var/cache/apt/*pkgcache.bin 2>/dev/null



# Clean des conneries avant de clore l'image
rm -rf /tmp/* /var/tmp/* 2> /dev/null
find /var/log -type f -delete

# La timezone
# Rien a faire a priori, les fichiers suffiront :)

EOF
  chmod 755 ${ARCH}_dir/post_inst.sh


  # Run des commandes ci dessus
  chroot ${ARCH}_dir /post_inst.sh
  # Note : ca ne marche que si chroot est capable de detecter et appeler qemu tout seul, sinon faudrait faire cp /usr/bin/qemu-aarch64-static arm64_dir/ && chroot arm64_dir   /qemu-aarch64-static /post_inst.sh && rm arm64_dir qemu-aarch64-static

  rm -f ${ARCH}_dir/post_inst.sh


  # On en fait une image docker
  cd ${ARCH}_dir/
  tar cpf - . | docker import - MYIMG/debian:bookworm-${ARCH} --platform ${ARCH}
  cd -

done



# Upload sur le serveur & co
docker tag MYIMG/debian:bookworm-amd64 crbrdocker/debian:bookworm-amd64
docker tag MYIMG/debian:bookworm-arm64 crbrdocker/debian:bookworm-arm64
#docker tag MYIMG/debian:bookworm-armel crbrdocker/debian:bookworm-armel
docker push -a crbrdocker/debian

#docker manifest create crbrdocker/debian:bookworm --amend crbrdocker/debian:bookworm-amd64 --amend crbrdocker/debian:bookworm-arm64 --amend crbrdocker/debian:bookworm-armel
docker manifest create crbrdocker/debian:bookworm --amend crbrdocker/debian:bookworm-amd64 --amend crbrdocker/debian:bookworm-arm64

docker manifest push crbrdocker/debian:bookworm

# Cleanup
rm -rf *_dir
docker system prune -a -f
