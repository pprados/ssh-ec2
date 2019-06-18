## Pré-requis sur AWS pour l'utilisateur
L'utilisateur de `ssh-ec2` doit :
- avoir un compte AWS pour un accès à la [console Web](https://console.aws.amazon.com/console/home)
via un user (format email Octo) et un mot de passe.
Vous devez avoir reçu un fichier de la DSI avec:
    - Un couple user/password
    - Un couple API tokens

- appartenir au group `SshEc2` (à demander à la DSI)
- valoriser une variable `TRIGRAM` dans son `.bashrc` ou équivalent

```bash
# Etape 1: A copier, ajuster et executer dans un shell
export TRIGRAM=_mon trigrame_' # /!\ _mon trigrame_ est a ajuster !

# Etape 2: A copier et executer dans un shell
[ $OSTYPE == 'linux-gnu' ] && RC=~/.bashrc
[ $OSTYPE == darwin* ] && RC=~/.bash_profile
[ -e ~/.zshrc ] && RC=~/.zshrc
echo export TRIGRAM=$TRIGRAM >>${RC} 
source ${RC}   # Important pour la suite.
```
- installer le [CLI AWS](https://tinyurl.com/yd4ru2nu)

```bash
$ pip3 install awscli --upgrade --user
$ aws --version
```
- vérifiez d'avoir ~/.config/bin dans le PATH (voir `.bashrc` ou `.zshrc` ou `.bash_profile`)
pour pouvoir executer `aws`

```bash
export PATH=~/.config/bin:$PATH
```

- [configurer aws](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
avec les clés d'API fourni par la DSI
```bash
$ aws configure
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]:
Default output format [None]: json
```
Ces clés d'API permettront d'utiliser `aws cli` dans `ssh-ec2`
Pour le vérifier :
```bash
$ aws s3 ls
```

- Créer une [pair de clé SSH](https://docs.aws.amazon.com/fr_fr/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
Elle servira à se connecter aux instances EC2 créées. Elle doit absolument être installé dans les différentes
régions d'AWS pour permettre la connexion aux instances.
Attention, ne pas confondre la pair de clé SSH avec l'authentification à la console AWS ou avec les clés d'Api.

```
$ ssh-keygen -f ~/.ssh/$TRIGRAM -t rsa -b 4096

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
- Ouvrir la [console AWS](https://eu-central-1.signin.aws.amazon.com) et se logger avec l'email
et le mot de passe recu de la DSI
- Dans le service *EC2*, menu *Réseau et sécurité* / *Pair de clés*,
importez la pair de clé SSH avec le nom du trigram en majuscule dans les différentes régions
que vous souhaitez utiliser (Probablement toute l'europe, à sélectionner en haut à droite).

![ImportKeyPair](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/ImportKeyPair.png?raw=true "ImportKeyPair")

- Sous Linux, toutes les clés dans `~/.ssh` sont automatiquement disponibles avec les sessions X/Gnome.
- Sous Mac, ajoutez ou modifiez le fichier `~/.ssh/config` ainsi :

```bash
echo >>~/.ssh/config "
Host *
  UseKeychain yes
  AddKeysToAgent yes
  IdentityFile ~/.ssh/$TRIGRAM
"  
```
Vous pouvez ajouter d'autres `IdentityFile` si besoin.

Lors de la première connexion, la passphrase de clé privée sera demandée ;
plus par la suite ( [Référence](https://apple.stackexchange.com/questions/48502/how-can-i-permanently-add-my-ssh-private-key-to-keychain-so-it-is-automatically) ).

À défaut de `TRIGRAM`, c'est le nom de l'utilisateur Linux (`$USER`) qui est utilisé comme clé
ou la valeur de la variable d'environnement `AWS_KEY_NAME`.

Si vous avez des erreurs étrange en utilisant `ssh-ec2`, regardez la FAQ.