# ssh-ec2
Un utilitaire pour augmenter la puissance de sa machine, grâce à AWS.

## Qu'est-ce que c'est ?
`ssh-ec2` est un script `bash`, permettant de faciliter l'utilisation du cloud AWS pour la réalisation de 
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
- la possibilité d'indiquer le cycle de vie de l'instance à la fin du traitement
    - l'interrompre et la détuire (pas de frais supplémentaires)
    - la laisser vivante (des frais supplémentaires sont appliqués par Amazon),
    - la sauvegarder et l'arreter (des frais moins élevés sont appliqués par Amazon)
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
sans devoir injecter les *credentials* dans l'instance (`aws s3 ls s3://mybucket`)
- D'ajouter des tags aux instances
- ...

Il permet d'ignorer :
- l'AMI spécifique à la région pour l'image à utiliser
- l'adresse IP de l'instance
- le `user` à utiliser pour se connecter (`ubuntu`, `ec2-user`, ...)
- le changement de répertoire un fois connecté (`cd prj`)
- l'activation de `tmux` ou de `screen` pour reprendre la main (`tmux a`)
- la synchronisation des fichiers

## Installation
Pour installer l'outil, il faut clonner le repo
```bash
$ cd src
$ git clone https://gitlab.octo.com/pprados/ssh-ec2.git
$ cd ssh-ec2
```
Puis installer:
- soit un lien symbolique vers le source (`make install-with-ln`) pour 
bénéficier des mises à jours du repo (mais il ne faut plus supprimer les sources)
- soit faire un copie dans `/usr/bin` (`make install`)

## Pré-requis sur AWS pour l'utilisateur
L'utilisateur de `ssh-ec2` doit :
- avoir un compte AWS
- appartenir au group `SshEc2`
- installer le [CLI AWS](https://tinyurl.com/yd4ru2nu)

    ```bash
    $ pip3 install awscli --upgrade --user
    $ aws --version    
    ```
    
- [créer une paire de clé](https://help.bittitan.com/hc/en-us/articles/115008255268-How-do-I-find-my-AWS-Access-Key-and-Secret-Access-Key-)
- [configurer](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) aws

```bash
$ aws configure
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: eu-west-1
Default output format [None]: json
```
- Valoriser une variable `TRIGRAM` dans son `.bashrc` ou équivalent 

```bash
$ echo export TRIGRAM=PPR >>~/.bashrc
$ . ~/.bashrc
```
- Créer une [pair de clé SSH](https://docs.aws.amazon.com/fr_fr/AWSEC2/latest/UserGuide/ec2-key-pairs.html)

```bash
$ ssh-keygen -f ~/.ssh/$TRIGRAM -t rsa -b 2048
Generating public/private ecdsa key pair.
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
Your identification has been saved in /home/pprados/.ssh/PPR.pem.
Your public key has been saved in /home/pprados/.ssh/PPR.pem.pub.
The key fingerprint is:
SHA256:taVlVEajMhxDRCjAdvM2EMn8Es0UpJKiohS/fJqr2m4 pprados@PPR-OCTO
The key's randomart image is:
+---[ECDSA 521]---+
|   ..+.B+** .o=  |
|    o.X.+. + o . |
| ...o..B  = =    |
| .o. .. =. O     |
|o. .   oS.o      |
|+ . .            |
|.  o .           |
| .E +            |
|o+++.            |
+----[SHA256]-----+
```
- Récupérer la clé publique

```bash
$ ssh-keygen -f ~/.ssh/$TRIGRAM -y
Enter passphrase: 
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDI4u+M0rW2/yKAMqXtJVsPEzH3O1tSIXRkDKoMLvJFiw/uAEkgHagfjuTd
EStGm5JcYLXKIuWULPUwt5RNpfClOScm3dC1+a3Z0eALDIr9b2LY3zjhFzAMlaeGcfMickiiuS3oQTn7+2CDAkQ8prv7Tg9D
2WWetHjrc+SdkXyTFQ==
```
- La copier dans le press-papier
- Importer la pair de clé SSH avec le nom du trigram dans les différentes régions.

![ImportKeyPair](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/ImportKeyPair.png?raw=true "ImportKeyPair")

- Normalement, toutes les clés dans `~/.ssh` sont automatiquement disponibles avec les sessions X/Gnome.
Sinon, consultez la document de [ssh-agent](https://www.ssh.com/ssh/agent)

A défaut de `TRIGRAM`, c'est le nom de l'utilisateur Linux (`$USER`) qui est utilisé comme clé 
ou la valeur de la variable d'environnement `AWS_KEY_NAME`.

## Pré-requis sur AWS pour l'administrateur
Pour utiliser l'outil `ssh-ec2`, il faut demander à l'administrateur AWS de créer :
- une stratégie/policy [SshEc2Access](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/SshEc2Access.policy) pour permettre 
la création d'instances EC2, 
et le droit de donner un rôle à l'instance ([iam:PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)). 
Elle sera associée à un groupe ou aux utilisateurs souhaitant pouvoir utiliser `ssh-ec2`.
Les ressources accessibles peuvent être restreintes si besoins.
     
- Des rôles, pour le service **EC2**, à associer aux instances EC2 qui seront construites par `ssh-ec2`.
Par exemple:
- Dans IAM
    - Un role [EC2ReadOnlyAccessToS3](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/EC2ReadOnlyAccessToS3.png), 
    pour le service **EC2**, avec la stratégie `AmazonEC2ReadOnlyAccess` (utilisé par défaut par `ssh-ec2`)

    ![AmazonEC2ReadOnlyAccess](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/EC2ReadOnlyAccessToS3.png)
    - Un role [EC2FullAccessToS3](EC2FullAccessToS3.png), pour le service **EC2**, 
    avec la stratégie `AmazonEC2FullAccess`

    ![EC2FullAccessToS3](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/EC2FullAccessToS3.png)
    - Un role pour le service EC2, limité aux certains _buckets_
    - ...
    - Un groupe `SshEc2` avec la stratégie/policy `SshEc2Access`, 

![CreateNewGroup](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/CreateNewGroup.png)
    - puis y associer les utilisateurs habilités à utiliser l'outil.

![AssociateGroups](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/AssociateGroups.png)
- Dans EC2 sur chaque région
    - Créer un group de sécurité `SshEC2`. Il sera associé aux instances EC2 créées.

![CreateSecurityGroup](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/CreateSecurityGroup.png)


## Utilisation
Le programme est paramétrable via la ligne de commande ou à l'aide de variables d'environements.

Voici les valeurs par défaut des principaux paramètres proposé par l'outil.

| Paramètre                                 | Valeur par défaut           |
|:------------------------------------------|:----------------------------|
| Region (`AWS_REGION`)                     | eu-central-1                |
| Type d'instance (`AWS_INSTANCE_TYPE`)     | p2.xlarge                   |
| Image (`AWS_IMAGE_NAME`)                  | Deep Learning AMI (Ubuntu)* |
| Profile (`AWS_IAM_INSTANCE_PROFILE`)      | EC2ReadOnlyAccessToS3       |
| Initialisation de la VM (`AWS_USER_DATA`) | ''                          |

Notez que pour ajouter un script d'initialisation de la VM, il faut :
- soit utiliser un fichier (`file://....sh`)
- soit utiliser un script complet AVEC shebang

```bash
export AWS_USER_DATA='#!/usr/bin/env bash
source activate $(VENV_AWS)
conda install 'make>=4' -y'
echo -e "$AWS_USER_DATA"
```

Vous pouvez modifier les valeurs par défaut en déclarant des variables d'environnement

```bash
export AWS_INSTANCE_TYPE=t2.small
export AWS_IMAGE_NAME="Deep Learning AMI (Amazon Linux)*"
export AWS_REGION=eu-west-1
```
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

#### Utilisation synchrone
Les paramètres sont interprétés comme une commande à exécuter (comme avec un `ssh` classique).
```bash
ssh-ec2 who am i # Invoke 'who am i' on EC2

----------------------------------------------------------
EC2 Name: PPR-ssh-ec2
Region:   eu-central-1
Type:     p2.xlarge
Image Id: ami-002b6c63ff04afa5f (Deep Learning AMI (Ubuntu)*)
Key name: PPR
Tags:     User=pprados, Name=PPR-ssh-ec2, Trigram=PPR, Hostname=PPR-OCTO
----------------------------------------------------------
Synchronizes current directory (except files in .rsyncignore)... 
ssh ubuntu@52.57.165.31 ...
ubuntu   pts/0        2019-03-11 15:31 (82.238.92.100)
Synchronizes result... done
```

Pour indiquer le comportement que doit avoir l'instance EC2 à la fin de la session,
il faut utiliser 
- `--leave` (ou `-l`) pour laisser instance vivante
- `--stop` (ou `-s`) pour la sauvegarder et l'arréter
- ou `--terminate` (ou `-t` - par défaut) pour la supprimer.

```bash
ssh-ec2 --stop "source activate cntk_p36 ; make train" # Sauve et arrète l'instance après le traitement
```

Il est possible de rattraper une instance qui à vocation a être interrompu avec un `--stop` ou un `--terminate`.
Pour cela, il faut lancer en parallèle une autre session avec une autre règle de terminaison, avant d'interrompre la première.
Le programme applique la gestion du cycle de vie de l'instance EC2 
s'il est le dernier à y avoir accès.

#### Utilisation asynchrone
Il est possible de lancer une commande et de détacher imédiatement le terminal. L'instance reste vivante.
```bash
ssh-ec2 --detach "while sleep 1; do echo thinking; done" # Return immediately
```
un appel avec `--attach` permet de se rattacher au terminal
```bash
ssh-ec2 --attach 
```
Suivant l'utilitaire de multiplexage, il faut utiliser `Ctrl-B d` (tmux) ou `Ctrl-A d` (screen) pour
se détacher de la session en la laissant vivante. 
Référez-vous à la documentation de ces outils pour en savoir plus.
`ssh-ec2` se charge d'utiliser au mieux ces outils. 
Par défaut, lors de l'invocation avec un `--detach`, `tmux` est utilisé.

Pour récupérer les résultats d'une instance détachée, il faut s'y rattacher avec 
```bash
ssh-ec2 --finish # Synchronize results at end 
```
au terme de cette session, les fichiers sont récupérés et l'instance EC2 suit
son cycle de vie.

| Objectif                                                                   | Procédure                             |
|----------------------------------------------------------------------------|---------------------------------------|
| Lancer un `make` et attendre le résultat pour continuer                    | `ssh-ec2 make`                        |
| Lancer un `make` puis sauver l'état de l'instance et l'arreter             | `ssh-ec2 --stop make`                 |
| Lancer une session SSH sur une instance et la garder vivante               | `ssh-ec2 --leave`                     |
| Lancer un `make` sur une instance et la garder vivante avec tmux           | `ssh-ec2 --leave --multi tmux make`   |
| Lancer un `make` et le laisser continuer détaché                           | `ssh-ec2 --detach make`               |
| Jeter un oeil sur un traitement détaché                                    | `ssh-ec2 --attach`                    |
| Récupérer le résultat d'un traitement détaché puis terminer l'instance EC2 | `ssh-ec2 --finish`                    |
| Récupérer le résultat d'un traitement détaché et garder l'instance EC2     | `ssh-ec2 --finish --leave`            |
| Rattraper une session qui va être tuée à la fin du traitement              | Dans un autre shell `ssh-ec2 --leave` |
| Forcer la suppression d'une instance                                       | `ssh-ec2 clear` |

### Synchronisation
Parfois, il n'est pas nécessaire de synchroniser les fichiers. 
Le paramètre `--no-rsync` permet cela.

Pour avoir un suivi des fichiers synchronisés, il faut ajouter `--verbose` pour voir les détails.

### Paramètres supplémentaires
Il est également possible de faire du reroutage de port.
```bash
ssh-ec2 -L 8888:localhost:8888 "jupyter notebook --NotebookApp.open_browser=False"
```
ou d'indiquer le fichier local de clé à utiliser.
```bash
ssh-ec2 -I my_key.pem "who am i"
```
D'autres paramètres plus subtiles sont documentés dans les sources. Vous ne devriez pas
en avoir besoin.

Pour résumer

| Paramètre     | Impact                                                                                 |
|:--------------|:---------------------------------------------------------------------------------------|
| _rien_        | Lance une session SSH.                                                                 |
| --help        | Affiche un rapide rappel des paramètres.                                               |
| --terminate   | Supprime l'instance EC2 après la session SSH (par défaut).                             |
| --leave       | Garde l'instance EC2 vivante après la session SSH.                                     |
| --stop        | Arrete l'instance EC2 après l'avoir sauvegardée, après la session SSH.                 |
| --detach      | Lance une commande et rend la main immédiatement.                                      |
| --attach      | Se rebranche sur le traitement en cours.                                               | 
| --finish      | Se rebranche sur le traitement en cours et synchronise les résultats à la fin.         | 
| -L <p:host:p> | Transfert un port local sur un port distant de l'instance, le temps de la session SSH. |
| -R <p:host:p> | Transfert un port distant sur un port local de l'instance, le temps de la session SSH. |
| --no-rsync    | Ne synchronise pas les fichiers du répertoire local avant et après le traitement.      |
| --verbose     | Affiche les fichiers synchronisés                                                      |

## Utilisation dans un Makefile
Il suffit de quelques recettes complémentaires dans un fichier `Makefile` pour pouvoir exécuter
tous les traitement sur AWS. Consultez le fichier [Makefile](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/Makefile?raw=true).

Avec ces règles, il suffit de préfixer les recettes d'origine pour les exécuter
sur AWS. Par exemple, s'il existe une recette `train` dans le `Makefile`,
```bash
make ec2-train # Start 'make train' on EC2 ephemeral instance.
```
permet d'exécuter la recette `make train` sur l'instance EC2.

Pour rappel, les AMI de machines learnings possèdent déjà des environnements pré-installés
avec des versions optimisées des différents frameworks.

Les recettes précédentes activent l'environnement conda `cntk_p36` avant le traitement.
Les recettes doivent compléter l'environnement si nécessaire.
Il est conseiller de rédiger des règles capablent de le détecter
pour installer le nécessaire avant le traitement.

# Bonus
De nombreuses recettes utils pour un Datascientist sont présente dans le 
[Makefile](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/Makefile?raw=true)

# Contribution
Toutes les contributions et suggestion sont les bienvenues.
Contactez moi (ppr@octo.com)
