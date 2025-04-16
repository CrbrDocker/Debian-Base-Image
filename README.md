# Debian_Base



## Creation d'une image de base Debian, from scratch.

### Par script
Le script _create_base_system_bookworm.sh_ fait tout tout seul :)


### Manuellement
Tout l'exemple ci dessous utilise bookworm comme exemple.
N'hesite pas  lire le script pour la version totalement  jour.


#### Creation du root system
Pour ca, on va utiliser debootstrap


##### AMD64
c'est le cas facile, c'est la mme plateforme
```
debootstrap --arch=amd64 --variant=minbase --components=main,contrib,non-free,non-free-firmware --no-check-gpg --no-check-certificate --include=wget,vim,sysvinit-core,rsync,subversion,git,locales,openssh-client,ca-certificates,debian-keyring,dialog,ncurses-bin,curl,less,procps --exclude='systemd*','dbus*',apparmor,nano bookworm amd64_dir
```
Nous ajoutons quelques paquets standards qu'on utilise tout le temps dans nos images.


##### ARM64 (Raspberry Pi, ou AppleSilicon)
Il va faloir faire de la cross compilation. Il faut installer qemu et particulirement le paquet qemu-user-static

Selon les versions, une des 2 commandes ci dessous
##### Vieux
```
qemu-debootstrap --arch arm64 --variant=minbase --components=main,contrib,non-free,non-free-firmware --no-check-gpg --no-check-certificate --include=wget,vim,sysvinit-core,rsync,subversion,git,locales,openssh-client,ca-certificates,debian-keyring,dialog,ncurses-bin,curl,less,procps --exclude='systemd*','dbus*',apparmor,nano bookworm arm64_dir
```

##### Normal (désormais, debootstrap est capable d'appeler qemu lui-même)
```
debootstrap --arch arm64 --variant=minbase --components=main,contrib,non-free,non-free-firmware --no-check-gpg --no-check-certificate --include=wget,vim,sysvinit-core,rsync,subversion,git,locales,openssh-client,ca-certificates,debian-keyring,dialog,ncurses-bin,curl,less,procps --exclude='systemd*','dbus*',apparmor,nano bookworm arm64_dir
```

#### Fichiers de conf a mettre a la main
```
for ARCH in amd64 arm64 ; do

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

  # On s'assure que l'image ne va pas tre poluee par des demons qu'on ne lancera pas de toute facon
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

  echo 'APT::Get::AllowUnauthenticated "true" ;' > ${ARCH}_dir/etc/apt/apt.conf.d/80cleancrap



  # Pour gagner de la place dans l'image, on enleve les docs & translations inutiles et on n'autorise pas APT a les remettre
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
  mkdir ${ARCH}_dir/usr/share/localesave && cp -dpR ${ARCH}_dir/usr/share/locale/locale.alias ${ARCH}_dir/usr/share/locale/fr* ${ARCH}_dir/usr/share/locale/en* ${ARCH}_dir/usr/share/localesave/ && rm -rf ${ARCH}_dir/usr/share/locale/* &&
mv ${ARCH}_dir/usr/share/localesave/*  ${ARCH}_dir/usr/share/locale/ && rmdir ${ARCH}_dir/usr/share/localesave



  # DNS - Pas sr si ca utilise ca ou le DNS host de toute facon
  cat > ${ARCH}_dir/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF


done

```


#### prparation d'execution locale

```
for ARCH in amd64 arm64 ; do

  cat > ${ARCH}_dir/post_inst.sh <<EOF
#!/bin/bash


# Les locales...
locale-gen
update-locale --no-checks LANG="en_US"



# APT
apt -y update
apt-get -y dist-upgrade

# Un peu de cleaning au besoin
# Note : en principe, pas besoin d'init du tout (pas plus que de kernel & co), mais avoir sysvinit light au cas ou, ca vite qu'une dependance installe systemd & co
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

done
```



#### Execution locale en chroot

##### AMD64
```
chroot amd64_dir /post_inst.sh
rm amd64_dir/post_inst.sh
```


#### ARM64
Selon les versions, 2 manieres de le faire.

- [ ] Si chroot est rcent et est capable de s'interconnecter tout seul avec qemu : 
```
chroot arm64_dir /post_inst.sh
rm arm64_dir/post_inst.sh
```


- [ ] Si chroot est plus ancien : 
Dans ce cas, on va lancer une version static de l'mulateur pour qu'ensuite il puisse tout lancer
```
cp /usr/bin/qemu-aarch64-static arm64_dir/
chroot arm64_dir   /qemu-aarch64-static /post_inst.sh
rm arm64_dir/post_inst.sh arm64_dir//qemu-aarch64-static
```


Note : Eventuellement  on peut lancer un chroot avec /bin/bash et effectuer des commandes / config dans le systme directement.



#### Creation et upload des images docker 

##### Creation des images en local
(on pourrait directement les crer et uploader en une commande, mais ca permet de tester sans poluer le repo-
```
for ARCH in amd64 arm64 ; do
  cd ${ARCH}_dir/
  tar cpf - . | docker import - MYIMG/debian:bookworm-${ARCH} --platform ${ARCH}
  cd -
done
```

Ici, les images sont crees et disponibles. On peut les instancier avec docker run


##### Upload des images sur repo
(evidement, il faut s'tre logg sur le repo avant avec docker login)
```
docker tag MYIMG/debian:bookworm-amd64 REGISTRY.URL/PATH/debian:bookworm-amd64
docker tag MYIMG/debian:bookworm-arm64 REGISTRY.URL/PATH/debian:bookworm-arm64
docker push -a REGISTRY.URL/PATH/debian
```

##### creation du manifest global multiarch 
(Note : si il existe deja, il est ecras par version plus rcente)
```
docker manifest create REGISTRY.URL/PATH/debian:bookworm --amend REGISTRY.URL/PATH/debian:bookworm-amd64 --amend REGISTRY.URL/PATH/debian:bookworm-arm64
docker manifest inspect REGISTRY.URL/PATH/debian:bookworm
# Note : si le inspect ne m'avait pas donne les versions, je les aurai ajout avec docker manifest anotate
docker manifest push REGISTRY.URL/PATH/debian:bookworm
```




## Update image
### Tout refaire
Meme procedure que pour creer.

### partir de l'image existante
cf autre projet : juste un apt-get upgrade en fait. Ca alourdie un peu l'image a force, donc a faire en connaissance de cause.

