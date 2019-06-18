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
    - Un role [EC2ReadOnlyAccessToS3](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/EC2ReadOnlyAccessToS3.png),
    pour le service **EC2**, avec la stratégie `AmazonEC2ReadOnlyAccess` (utilisé par défaut par `ssh-ec2`)

    ![AmazonEC2ReadOnlyAccess](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/EC2ReadOnlyAccessToS3.png)
    - Un role [EC2FullAccessToS3](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/EC2FullAccessToS3.png), pour le service **EC2**,
    avec la stratégie `AmazonEC2FullAccess`

    ![EC2FullAccessToS3](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/EC2FullAccessToS3.png)
    - Un role pour le service EC2, limité aux certains _buckets_
    - ...
    - Un groupe `SshEc2` avec la stratégie/policy `SshEc2Access`,

![CreateNewGroup](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/CreateNewGroup.png)

    - puis y associer les utilisateurs habilités à utiliser l'outil.

![AssociateGroups](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/AssociateGroups.png)
- Dans EC2 sur chaque région
    - Créer un group de sécurité `SshEC2`. Il sera associé aux instances EC2 créées.

![CreateSecurityGroup](https://gitlab.octo.com/pprados/ssh-ec2/raw/master/img/CreateSecurityGroup.png)

