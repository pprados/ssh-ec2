# ssh-ec2
Un utilitaire pour déporter les calculs des data-scientistes sur AWS.

## Qu'est-ce que c'est ?
`ssh-ec2` est un script bash, permettant de faciliter l'utilisation du cloud AWS pour la réalisation de 
calculs complexes avec des instances puissantes, équipées de GPU. L'outil se charge de :
- créer et lancer une instance éphémère EC2 
- répliquer le répertoire courant sur l'instance
- lancer un SSH dans le répertoire
    - soit avec un `bash`
    - soit pour déclencher un traitement
- de récupérer tous les résultats
- et de détruire l'instance.

## Fonctionnalités
Cet outils offre :
- la possibilité d'indiquer quoi faire de l'instance à la fin du traitement
    - La laisser vivante (des frais supplémentaires sont appliqués par Amazon),
    - la sauvegarder et l'arreter (des frais moins élevé sont appliqués par Amazon)
    - l'interrompre et la détuire (pas de frais supplémentaires)
- de choisir l'image AMI à utiliser, le type de l'instance, la clé SSH, la région, etc. 
- Offre différents moyens de gérer le multi-session sur l'instance
    - pas de multi-sessions (par défaut)
    - Tmux
    - Screen
- Synchronise 
    - Avant le traitement, le répertoire courant (hors les fichiers et répertoires indiqués dans `.rsyncignore`)
sur l'instance EC2, avant de lancer le traitement directement dans le répertoire synchronisé
    - Après le traitement, pour récupérer tous les nouveaux fichiers ou les fichiers modifiés
- De limiter les droits accordés à l'instance
- De permettre un accès direct aux fichiers S3 (et au autres services AWS), 
sans devoir injecter les credential dans l'instance (`aws s3 ls s3://mybucket`)
- D'ajouter des tags aux instances
- ...


## Pré-requis sur AWS pour l'administrateur
Pour utiliser l'outil `ssh-ec2`, il faut demander à l'administrateur AWS de créer :
- une stratégie/policy [SshEc2Access](SshEc2Access.policy) pour permettre la création d'instances EC2, 
et le droit de donner un rôle à l'instance ([iam:PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)). 
Elle sera associée à un groupe ou aux utilisateurs souhaitant pouvoir utiliser `ssh-ec2`.
Les ressources accessibles peuvent être restreintes si besoins.
     
- Des rôles, pour le service **EC2**, à associer aux instances qui seront construites par `ssh-ec2`.
Par exemple:
    - Un role [EC2ReadOnlyAccessToS3](./EC2ReadOnlyAccessToS3.png), pour le service **EC2**, 
    avec la stratégie `AmazonEC2ReadOnlyAccess` (utilisé par défaut par `ssh-ec2`)
    ![AmazonEC2ReadOnlyAccess](./EC2ReadOnlyAccessToS3.png?raw=true "EC2ReadOnlyAccessToS3")
    - Un role [EC2FullAccessToS3](EC2FullAccessToS3.png), pour le service **EC2**, 
    avec la stratégie `AmazonEC2FullAccess`
    ![EC2FullAccessToS3](./EC2FullAccessToS3.png?raw=true "EC2FullAccessToS3")
    - Un role pour le service EC2, limité aux certains _buckets_
    - ...
- créer un groupe `SshEc2` avec la stratégie/policy `SshEc2Access`, 
![CreateNewGroup](./CreateNewGroup.png?raw=true "CreateNewGroup")
- puis y associer les utilisateurs habilité à utiliser le service.
![AssociateGroups](./AssociateGroups.png?raw=true "AssociateGroups")


## Pré-requis sur AWS pour l'utilisateur
L'utilisateur de `ssh-ec2` doit :
- appartenir au group `SshEc2`
- installer le [CLI AWS](https://tinyurl.com/yd4ru2nu)
- valoriser une variable TRIGRAM dans son `.bashrc` ou équivalent
```bash
export TRIGRAM=PPR
```
- importer une pair de clé SSH valide avec le nom du trigram dans les différentes régions.
![ImportKeyPair](./ImportKeyPair.png?raw=true "ImportKeyPair")

A défaut, c'est le nom de l'utilisateur Linux (`$USER`) qui est utilisé comme clé 
ou la valeur de la variable d'environement `AWS_KEY_NAME`.


## Utilisation
Le programme est paramétrable via la ligne de commande ou à l'aide de variables d'environements.

Voici les valeurs par défaut des principaux paramètres proposé par l'outil.

| Paramètre       | Valeur par défaut           |
|:----------------|:----------------------------|
| Region          | eu-central-1                |
| Type d'instance | p2.xlarge                   |
| Image           | Deep Learning AMI (Ubuntu)* |
| Profile         | EC2ReadOnlyAccessToS3       |


Plus d'informations sont présentes dans le source de `ssh-ec2`.

Pour avoir un rapide rappel des paramètres de la ligne de commande :
```bash
$ ssh-ec2 --help
ssh-ec2 [-lsr|--leave|--stop|--terminate] [-daf|--detach|--attach|--finish] [--no-rsync] \ 
 [--multi <tmux|screen|none>] \ 
 [-i <pem file>] [-[LR] port:host:port] [cmds*]
```

### Fin de vie de l'instance EC2
Un simple lancement de `ssh-ec2` permet d'avoir une session `bash`
sur une instance EC2 qui sera détruire à la sortie du terminal.

Les paramètres sont interprétés comme une commande à exécuter (comme avec un `ssh` classique).
```bash
ssh-ec2 who am i # Invoke 'who am i' on EC2
```

Pour indiquer le comportement que doit avoir l'instance EC2 à la fin de la session,
il faut utiliser `--leave`, `--stop` ou `--terminate`.
```bash
ssh-ec2 --stop "source activate cntk_p36 ; make train" # Sauve et arrète l'instance après le traitement
```

Il est possible de lancer une commande et de détacher imédiatement le terminal. L'instance reste vivante.
```bash
ssh-ec2 --detach "while sleep 1; do echo thinking; done" # Return immediately
```
un appel avec `--attach` permet de se rattacher au terminal
```bash
ssh-ec2 --attach 
```
Suivant l'utilitaire de multiplexage, il faut utiliser `Ctrl-B d` (tmux) ou `Ctrl-A d` (screen) pour
se détacher de la session en la laissant vivante. Référez-vous à la documentation
de ces outils pour en savoir plus.
`ssh-ec2` se charge d'utiliser au mieux ces outils. 
Par défaut, lors de l'invocation avec un `--detach`, `tmux` est utilisé.

Pour récupérer les résultats d'une instance détachée, il faut s'y rattacher avec 
```bash
ssh-ec2 --finish # Synchronize results 
```

Pour résumer:

| Objectif                                                               | Procédure                           |
|------------------------------------------------------------------------|-------------------------------------|
| Lancer un `make` et attendre le résultat pour continuer                | `ssh-ec2 make`                      |
| Lancer un `make` puis sauver l'état de l'instance et l'arreter         | `ssh-ec2 --stop make`               |
| Lancer une session SSH sur une instance et la garder vivante           | `ssh-ec2 --leave`                   |
| Lancer un `make` sur une instance et la garder vivante avec tmux       | `ssh-ec2 --leave --multi tmux make` |
| Lancer un `make` et le laisser continuer détaché                       | `ssh-ec2 --detach make`             |
| Jeter un oeil sur un traitement détaché                                | `ssh-ec2 --attach`                  |
| Récupérer le résultat d'un `make` détaché puis terminer l'instance EC2 | `ssh-ec2 --finish`                  |
| Récupérer le résultat d'un `make` détaché et garder l'instance EC2     | `ssh-ec2 --finish --leave`          |

### Synchronisation
Parfois, il n'est pas nécessaire de synchroniser les fichiers. 
Le paramètre `--no-rsync` permet cela.

Pour avoir un suivi des fichiers synchronisés, il faut ajouter `--no-quiet` pour voir les détails.

### Paramètres supplémentaires
Il est également possible de faire du reroutage de port.
```bash
ssh-ec2 -L 8888:localhost:8888 "jupyter notebook --NotebookApp.open_browser=False"
```
ou d'indiquer le fichier de clé à utiliser.
```bash
ssh-ec2 -I my_key.pem "who am i"
```
D'autres paramètres plus subtiles sont documentés dans les sources. Vous ne devriez pas
en avoir besoin.

Pour résumer

| Paramètre    | Impact                                                                                 |
|:-------------|:---------------------------------------------------------------------------------------|
| _rien_       | Lance un session SSH                                                                   |
| --help       | Affiche un rapide rappel des paramètres                                                |
| --terminate  | Supprime l'instance EC2 après la session SSH (par défaut)                              |
| --leave      | Garde l'instance EC2 vivante après la session SSH                                      |
| --stop       | Arrete l'instance EC2 après l'avoir sauvegardé, après la session SSH                   |
| --detach     | Lance une commande et rend la main imédiatement                                        |
| --attach     | Se rebranche sur le traitement en cours                                                | 
| --finish     | Se rebranche sur le traitement en cours et synchronise les résultats à la fin          | 
| -L<p:host:p> | transfert un port local sur un port distant de l'instance, le temps de la session SSH. |
| -R<p:host:p> | transfert un port distant sur un port local de l'instance, le temps de la session SSH. |
| --no-rsync   | Ne synchronise pas les fichiers du répertoire local avant le traitement, ni après.     |
| --no-quiet   | Affiche les fichiers synchronisés                                                      |

## Utilisation dans un Makefile
Il suffit de quelques recettes complémentaires dans un fichier `Makefile` pour pouvoir exécuter
un traitement sur AWS.

```
## Makefile
on-ec2-%: ## call make recipe on EC2
	./ssh-ec2 -"source activate cntk_p36 ; make $(*:on-ec2-%=%)"

on-ec2-notebook: ## Start jupyter notebook on EC2
	./ssh-ec2 -L 8888:localhost:8888 "jupyter notebook --NotebookApp.open_browser=False"
```
Avec ces règles, il suffit de préfixer les recettes d'origine pour les exécuter
sur AWS. Par exemple, s'il existe une recette `train` dans le `Makefile`,
```bash
make on-ec2-train # Start 'make train' on EC2 ephemeral instance.
```
permet d'exécuter la recette `make train` sur l'instance EC2.

Pour rappel, les AMI de machines learnings possèdent déjà des environnements pré-installés
avec des versions optimisées des différents frameworks.

Les recettes précédentes activent l'environement conda `cntk_p36` avant le traitement.
Les recettes doivent compléter l'environement si nécessaire.
Il est conseiller de rédiger des règles capables de le détecter
pour installer le nécessaire avant le traitement.

Consultez les exemples [de Makefile ici](TODO) pour Python.

# Contribution
Toutes les contributions et suggestion sont les bienvues.
Contactez moi (ppr@octo.com)