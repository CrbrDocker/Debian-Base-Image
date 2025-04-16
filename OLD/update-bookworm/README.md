# Update standard image


## Considerations
A faire pour une petite update, pour une grosse update, regenerer l'image from scratch. CF ci dessus.

## Build
Note : depend de buildx (cross platform build) & la VM de base Debian Bookworm existante.

### Les fichiers
- DockerFileBookwormUpdate : le dockerfile... pour lancer le build
- update-bookworm.sh : fichier d'update de l'image. Il est copie et execute dans l'image pendant le build. Note : on fait ca volontairement plutot que plein de commandes run pour limiter la taille des diffs (enfin j'espere)
- ./need_rebuild.sh : script qui permet de checker les modification et rebuilder au cas ou, si il y a eu des modifications ou des packages ‡ updater. possiblement automatisable periodiquement.


### Build : 

#### Build de test : 
```
docker build --no-cache -f DockerFileBookwormUpdate -t monimagedetest .
```
... et ensuite, on peut la run

PS : penser a tout cleaner prune & co avant de lancer le build final.


#### Build final, push√© sur le repo : 
```
docker buildx build --no-cache --platform linux/amd64,linux/arm64 -f DockerFileBookwormUpdate -t crbrdocker/debian:bookworm . --push
```
Attention, il faut le lancer imperativement dans le repertoire ici, sinon des problemes de path
(note, on doit le pusher avec buildx directement, sinon ca ne met pas l'image a dispo, ca la laisse juste dans le cache de build)

#### Automatisation build :
le script ./need_rebuild.sh peut tout faire. Il faut le lancer imperativement dans le repertoire ici, sinon des problemes de path


