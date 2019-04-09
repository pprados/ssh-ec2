#!/usr/bin/env make
# SNIPPET Le shebang précédant permet de creer des alias des cibles du Makefile.
# Il faut que le Makefile soit executable
# 	chmod u+x Makefile
# 	git update-index --chmod=+x Makefile
# Puis, par exemple
# 	ln -s Makefile configure
# 	ln -s Makefile test
# 	ln -s Makefile train
# 	./configure		# Execute make test
# 	./test 			# Execute make test
#   ./train 		# Train the model
# Attention, il n'est pas possible de passer les paramètres aux liens

# SNIPPET pour changer le mode de gestion du Makefile.
# Avec ces trois paramètres, toutes les lignes d'une recette sont invoquées dans le même shell.
# Ainsi, il n'est pas nécessaire d'ajouter des '&&' ou des '\' pour regrouper les lignes.
# Comme Make affiche l'intégralité du block de la recette avant de l'exécuter, il n'est
# pas toujours facile de savoir quel est la ligne en échec.
# Je vous conseille dans ce cas d'ajouter au début de la recette 'set -x'
# Attention : il faut une version > 4 de  `make` (`make -v`).
# Sur Mac : https://stackoverflow.com/questions/38901894/how-can-i-install-a-newer-version-of-make-on-mac-os
# Les versions CentOS d'Amazone ont une version 3.82.
# Utilisez `conda install -n $(VENV_AWS) make>=4 -y`
SHELL=/bin/bash
.SHELLFLAGS = -e -c
.ONESHELL:


## ---------------------------------------------------------------------------------------
# SNIPPET pour détecter l'OS d'exécution.
ifeq ($(OS),Windows_NT)
    OS := Windows
else
    OS := $(shell sh -c 'uname 2>/dev/null || echo Unknown')
endif

## ---------------------------------------------------------------------------------------
# SNIPPET pour détecter la présence d'un GPU afin de modifier le nom du projet
# et ses dépendances si nécessaire.
ifdef GPU
USE_GPU:=$(shell [[ "$$GPU" == yes ]] && echo "-gpu")
else ifneq ("$(wildcard /proc/driver/nvidia)","")
USE_GPU:=-gpu
else ifdef CUDA_PATH
USE_GPU:=-gpu
endif

## ---------------------------------------------------------------------------------------
# SNIPPET pour récupérer les séquences de caractères pour les couleurs
# Manage colors...
normal:=$(shell tput sgr0)
red:=$(shell tput setaf 1)
green:=$(shell tput setaf 2)
yellow:=$(shell tput setaf 3)
blue:=$(shell tput setaf 4)
purple:=$(shell tput setaf 5)
cyan:=$(shell tput setaf 6)
white:=$(shell tput setaf 7)
gray:=$(shell tput setaf 8)

## ---------------------------------------------------------------------------------------
# SNIPPET pour gérer le projet, le virtualenv et le kernel
# Par convention, les noms du projet, de l'environnement Conda ou le Kernel Jupyter
# correspondent au nom du répertoire du projet.
# Il est possible de modifier cela, en valorisant les variables VENV et/ou KERNEL
# avant le lancement du Makefile (`VENV=cntk_p36 make`)

PRJ:=$(shell basename $(shell pwd))
VENV ?= $(PRJ)
KERNEL ?=$(VENV)
PRJ_PACKAGE:=$(PRJ)$(USE_GPU)
PYTHON_VERSION:=3.6

## ---------------------------------------------------------------------------------------
# SNIPPET pour reconstruire tous les répertoires importants permettant
# de gérer correctement les dépendances des modules.
# Cela servira à gérer automatiquement les environnements.
# Pour que cela fonctionne, il faut avoir un environement Conda actif,
# identifié par la variable CONDA_PREFIX.
CONDA_BASE=$(shell conda info --base)
CONDA_PACKAGE:=$(CONDA_PREFIX)/lib/python$(PYTHON_VERSION)/site-packages
CONDA_PYTHON:=$(CONDA_PREFIX)/bin/python
PIP_PACKAGE:=$(CONDA_PACKAGE)/$(PRJ_PACKAGE).egg-link

## ---------------------------------------------------------------------------------------
# SNIPPET pour ajouter des repositories complémentaires à PIP
EXTRA_INDEX:=--extra-index-url=https://pypi.anaconda.org/octo/label/dev/simple

## ---------------------------------------------------------------------------------------
# Ici, il faut indiquer toutes les règles du Makefile n'étant pas
# reliée à un fichier. Ainsi, l'absence d'un ficheir 'help' par exemple, n'est pas
# le signe qu'il faut appliquer la règle.
.PHONY : help \
	configure \
	prepare \
	requirements \
	nltk-database spacy-database \
	upgrade-venv upgrade-$(VENV) \
	clean-notebooks notebook \
	clean clean-all clean-venv clean-$(VENV) clean-pip clean-pyc \
	remove-kernel remove-venv remove-$(VENV) \
	test \
	ec2-*

## ---------------------------------------------------------------------------------------
# SNIPPET pour gérer automatiquement l'aide du Makefile.
# Il faut utiliser des commentaires commençant par '##' sur la ligne des règles,
# pour une production automatique de l'aide.
# Pour cela, il faut utiliser un double commentaire '##' sur la même ligne que la recette.
.DEFAULT: help

help: ## Print all majors target
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(cyan)%-20s$(normal) %s\n", $$1, $$2}'
	printf "$(cyan)%-20s$(normal) %s\n" "build-<dir>" "Execute notebooks in notebooks/<dir>\n"
	printf "$(cyan)%-20s$(normal) %s\n" "'build-*'" "Execute all notebooks\n"
	printf "$(cyan)%-20s$(normal) %s\n" "ec2-<target>" "Apply <target> receipt on EC2 instance\n"
	printf "$(cyan)%-20s$(normal) %s\n" "ec2-tmux-<target>" "Apply <target> receipt on EC2 instance with tmux activated\n"
	printf "$(cyan)%-20s$(normal) %s\n" "ec2-detach-<target>" "Apply <target> receipt on EC2 instance and detach the shell\n"
	echo -e "Use '$(cyan)make -jn ...$(normal)' for Parallel run"
	echo -e "Use '$(cyan)make -B ...$(normal)' to force the target"
	echo -e "Use '$(cyan)make -n ...$(normal)' to simulate the build"

## ---------------------------------------------------------------------------------------
# SNIPPET pour affichier la valeur d'une variable d'environnement
# tel quelle est vue par le Makefile. Par exemple 'make dump-CONDA_PACKAGE'
dump-%:
	@if [ "${${*}}" = "" ]; then
		echo "Environment variable $* is not set";
		exit 1;
	else
		echo "$*=${${*}}";
	fi

## ---------------------------------------------------------------------------------------
# SNIPPET pour gérer les Notebooks avec GIT.
# Les règles suivantes s'assure que git est bien initialisé
# et ajoute des règles pour les fichiers *.ipynb
# et eventuellement pour les fichiers *.csv.
#
# Pour cela, un fichier .gitattribute est maintenu à jour.
# Les règles pour les notebooks se chargent de les nettoyer avant de les commiter.
# Pour cela, elles appliquent `jupyter nbconvert` à la volée. Ainsi, les comparaisons
# de version ne sont plus parasités par les datas.
#
# Les règles pour les CSV utilisent le composant `daff` (pip install daff)
# pour comparer plus efficacement les évolutions des fichiers csv.
# Un `git diff toto.csv` est plus clair.

# S'assure de la présence de git (util en cas de synchronisation sur le cloud par exemple)
.git:
	@git init

# Purge notebook for git. Used by .gitattribute
pipe_clear_jupyter_output:
	jupyter nbconvert --to notebook --ClearOutputPreprocessor.enabled=True <(cat <&0) --stdout 2>/dev/null

# Initialiser la configuration de Git
.gitattributes: | .git  # Configure git
	@git config --local core.autocrlf input
	# Set tabulation to 4 when use 'git diff'
	@git config --local core.page 'less -x4'
	@git lfs install

	# Add rules to manage the output data of notebooks
	@git config --local filter.dropoutput_jupyter.clean "make --silent pipe_clear_jupyter_output"
	@git config --local filter.dropoutput_jupyter.smudge cat
	@[ -e .gitattributes ] && grep -v dropoutput_jupyter .gitattributes >.gitattributes.new 2>/dev/null || true
	@[ -e .gitattributes.new ] && mv .gitattributes.new .gitattributes || true
	@echo "*.ipynb filter=dropoutput_jupyter diff=dropoutput_jupyter -text" >>.gitattributes

ifeq ($(shell which daff >/dev/null ; echo "$$?"),0)
	# Add rules to manage diff with daff for CSV file
	@git config --local diff.daff-csv.command "daff.py diff --git"
	@git config --local merge.daff-csv.name "daff.py tabular merge"
	@git config --local merge.daff-csv.driver "daff.py merge --output %A %O %A %B"
	@[ -e .gitattributes ] && grep -v daff-csv .gitattributes >.gitattributes.new 2>/dev/null
	@[ -e .gitattributes.new ] && mv .gitattributes.new .gitattributes
	@echo "*.[tc]sv diff=daff-csv merge=daff-csv -text" >>.gitattributes
endif
	@echo ".gitattributes updated"

## ---------------------------------------------------------------------------------------
# SNIPPET pour vérifier la présence d'un environnement Conda conforme
# avant le lancement d'un traitement.
# Il faut ajouter $(VALIDATE_VENV) dans les recettes
# et choisir la version à appliquer.
# Soit :
# - CHECK_VENV pour vérifier l'activation d'un VENV avant de commencer
# - VALIDATE_VENV pour forcer l'activation d'un VENV si besoin

CHECK_VENV=if [[ "base" == "$(CONDA_DEFAULT_ENV)" ]] || [[ -z "$(CONDA_DEFAULT_ENV)" ]] ; \
  then ( echo -e "$(green)Use: $(cyan)conda activate $(VENV)$(green) before using 'make'$(normal)"; exit 1 ) ; fi

ACTIVATE_VENV=source activate $(VENV)
DEACTIVATE_VENV=source deactivate $(VENV)

VALIDATE_VENV=$(CHECK_VENV)
#VALIDATE_VENV=$(ACTIVATE_VENV)

JUPYTER_DATA_DIR:=$(shell jupyter --data-dir 2>/dev/null || echo "~/.local/share/jupyter")
#JUPYTER_DATA_DIR:=~/.local/share/jupyter

## ---------------------------------------------------------------------------------------
# SNIPPET pour gérer correctement toute les dépendances python du projet.
# La cible `requirements` se charge de gérer toutes les dépendances
# d'un projet Python. Dans le SNIPPET présenté, il y a de quoi gérer :
# - les dépendances PIP
# - l'import de données pour spacy
# - l'import de données pour nltk
# - la gestion d'un kernel pour Jupyter
#
# Il suffit, dans les autres de règles d'ajouter la dépendances sur `requirements`
# pour qu'un simple `make test` garantie la mise à jour de l'environnement avant
# le lancement des tests.
#
# Pour cela, il faut indiquer dans le fichier setup.py, toutes les dépendances
# de run et de test (voir l'exemple `setup.py`)

# Toutes les dépendances du projet à regrouper ici
requirements: \
		$(PIP_PACKAGE) \
		.gitattributes \
		nltk-database \
		spacy-database


# Règle de vérification de la bonne installation de la version de python dans l'environnement Conda
$(CONDA_PYTHON):
	$(VALIDATE_VENV)
	conda install "python=$(PYTHON_VERSION).*" -y -q

# Règle de mise à jour de l'environnement actif à partir
# des dépendances décrites dans `setup.py`
$(PIP_PACKAGE): $(CONDA_PYTHON) setup.py | .git # Install pip dependencies
	$(VALIDATE_VENV)
	pip install -e '.[tests]' | grep -v 'already satisfied' || true
	@touch $(PIP_PACKAGE)

# Règle d'installation du Kernel pour Jupyter
$(JUPYTER_DATA_DIR)/kernels/$(KERNEL): $(PIP_PACKAGE)
	$(VALIDATE_VENV)
	python -m ipykernel install --user --name $(KERNEL)

# Règle de suppression du kernel
remove-kernel:
	@echo y | jupyter kernelspec uninstall $(KERNEL) 2>/dev/null || true
	echo -e "$(yellow)Warning: Kernel $(KERNEL) uninstalled$(normal)"

## ---------------------------------------------------------------------------------------
# SNIPPET pour récupérer les bases de données de nltk.
# Ci-dessous, la recette pour lister toutes les bases.
# Vous pouvez valoriser NLTK_DATA https://www.nltk.org/data.html

ifndef NLTK_DATA
# La ligne suivante ralentie le Makefile. A activer qu'avec des env. spécifiques.
#NLTK_DATA:=$(shell python -c "import nltk.data; print(nltk.data.path[0])" 2>/dev/null || true)
export NTLK_DATA
ifeq ($(NLTK_DATA),)
ifeq ($(OS),Darwin)
NLTK_DATA=/usr/local/share/nltk_data
else ifeq ($(OS),Windows)
NLTK_DATA=C:/nltk_data
else
NLTK_DATA=~/nltk_data
endif
endif
endif

# Ajoutez ici les bases de données supplémentaires.
# Par exemple, ajoutez
# $(NLTK_DATA)/corpora/wordnet
# et c'est tout.
nltk-database: $(PIP_PACKAGE) \
	$(NLTK_DATA)/tokenizers/punkt \
	$(NLTK_DATA)/corpora/stopwords

# Les recettes génériques de downloads
$(NLTK_DATA)/tokenizers/%: $(PIP_PACKAGE)
	$(VALIDATE_VENV)
	python -m nltk.downloader $*
	touch ~/nltk_data/tokenizers/$*

$(NLTK_DATA)/corpora/%: $(PIP_PACKAGE)
	$(VALIDATE_VENV)
	python -m nltk.downloader $*
	touch ~/nltk_data/corpora/$*


## ---------------------------------------------------------------------------------------
# SNIPPET pour récupérer les bases de données de spacy.
# Ci-dessous, la recette pour lister toutes les bases
# Ajoutez les bases complémentaires.
# Par exemple :
# $(CONDA_PACKAGE)/spacy/data/fr
# et c'est tout.
spacy-database: $(PIP_PACKAGE) \
	$(CONDA_PACKAGE)/spacy/data/en

# La recette générique de téléchargement
$(CONDA_PACKAGE)/spacy/data/%: $(PIP_PACKAGE)
	$(VALIDATE_VENV)
	python -m spacy download $*
	@touch $(CONDA_PACKAGE)/spacy/data/$*

## ---------------------------------------------------------------------------------------
# SNIPPET pour préparer l'environnement d'un projet juste après un `git clone`
configure: ## Prepare the environment (conda venv, kernel, ...)
	@conda create --name "$(VENV)" python=$(PYTHON_VERSION) -y
	echo -e "Use: $(cyan)conda activate $(VENV)$(normal)"

## ---------------------------------------------------------------------------------------
# SNIPPET pour supprimer l'environnement conda
remove-venv remove-$(VENV): ## Remove venv
	@$(DEACTIVATE_VENV)
	conda env remove --name "$(VENV)" -y
	echo -e "Use: $(cyan)conda deactivate$(normal)"

## ---------------------------------------------------------------------------------------
# SNIPPET de mise à jour des dernières versions des composants.
# Après validation, il est nécessaire de modifier les versions dans le fichier `setup.py`
# pour tenir compte des mises à jours
upgrade-venv upgrade-$(VENV): ## Upgrade packages to last versions
	$(VALIDATE_VENV)
	conda update --all
	pip list --format freeze --outdated | sed 's/(.*//g' | xargs -r -n1 pip install -U
	echo -e "$(cyan)After validation, upgrade the setup.py$(normal)"

## ---------------------------------------------------------------------------------------
# SNIPPET de validation des notebooks en les ré-executants.
# L'idée est d'avoir un sous répertoire par phase, dans le répertoire `notebooks`.
# Ainsi, il suffit d'un `make build-phase1` pour valider tous les notesbooks du répertoire `notebooks/phase1`.
# Pour valider toutes les phases : `make build-*`.
# L'ordre alphabétique est utilisé. Il est conseillé de préfixer chaque notebook d'un numéro.
build-%: requirements
	$(VALIDATE_VENV)
	time jupyter nbconvert \
	  --ExecutePreprocessor.timeout=-1 \
	  --execute \
	  --inplace notebooks/$*/*.ipynb


## ---------------------------------------------------------------------------------------
# SNIPPET pour executer jupyter notebook, mais en s'assurant de la bonne application des dépendances.
# Utilisez 'make notebook' à la place de 'jupyter notebook'.
notebook: requirements $(JUPYTER_DATA_DIR)/kernels/$(KERNEL) ## Start jupyter notebooks
	$(VALIDATE_VENV)
	jupyter notebook

## ---------------------------------------------------------------------------------------
# SNIPPET pour nettoyer tous les fichiers générés par le compilateur Python.
clean-pyc: # Clean pre-compiled files
	-/usr/bin/find . -name '*.pyc' -exec rm --force {} +
	-/usr/bin/find . -name '*.pyo' -exec rm --force {} +

## ---------------------------------------------------------------------------------------
# SNIPPET pour nettoyer tous les notebooks
clean-notebooks: ## Remove all results of notebooks
	@[ -e notebooks ] && find notebooks -name '*.ipynb' -exec jupyter nbconvert --ClearOutputPreprocessor.enabled=True --inplace {} \;
	@echo "Notebooks cleaned"

## ---------------------------------------------------------------------------------------
clean-pip: # Remove all the pip package
	$(VALIDATE_VENV)
	pip freeze | grep -v "^-e" | xargs pip uninstall -y

## ---------------------------------------------------------------------------------------
# SNIPPET pour nettoyer complètement l'environnement Conda
clean-venv clean-$(VENV): remove-venv ## Set the current VENV empty
	@echo -e "$(cyan)Re-create virtualenv $(VENV)...$(normal)"
	conda create -y -q -n $(VENV)
	touch setup.py
	echo -e "$(yellow)Warning: Conda virtualenv $(VENV) is empty.$(normal)"

## ---------------------------------------------------------------------------------------
# SNIPPET pour faire le ménage du projet (hors environnement)
clean: clean-pyc clean-notebooks ## Clean current environment

## ---------------------------------------------------------------------------------------
# SNIPPET pour faire le ménage du projet (hors environnement)
clean-all: clean remove-venv remove-kernel ## Clean all environments

## ---------------------------------------------------------------------------------------
# SNIPPET pour déclencher les tests unitaires
test: requirements ## Run all tests
	$(VALIDATE_VENV)
	python -m unittest discover -s tests -b

# SNIPPET pour vérifier les TU et le recalcule de tous les notebooks
validate: test build-* ## Validate the version before commit

## ---------------------------------------------------------------------------------------
# SNIPPET pour ajouter la capacité d'exécuter des recettes sur une instance éphémère EC2.
# L'utilisation de `requirements` dans chaque règle, permet de s'assurer de la bonne
# mise en place de l'environnement nécessaire à l'exécution de la recette,
# même lorsqu'elle est exécuté sur EC2.
# Par exemple :
# - `make on-ec2-test` execute les TU sur EC2
# - `make detach-build-all` détache le recalcule tous les notebooks sur EC2

# Quel venv utilisé sur l'instance EC2 ?
VENV_AWS=cntk_p36

# Initialisation de l'instance
export AWS_USER_DATA
# Les deux premières lignes permettent d'avoir une trace de l'initialisation
# de l'instance EC2 sur /tmp/user-data.log
# C'est pratique pour le debug
define AWS_USER_DATA
#!/bin/bash -x
exec > /tmp/user-data.log 2>&1
sudo su - ec2-user -c "conda install -n $(VENV_AWS) make>=4 -y"
endef

# Quel est le cycle de vie par défaut des instances, via ssh-ec2 ?
EC2_LIFE_CYCLE=--leave

# Recette permettant un 'make ec2-test'
ec2-%: ## call make recipe on EC2
	$(VALIDATE_VENV)
	DEBUG=y ssh-ec2 --verbose $(EC2_LIFE_CYCLE) "source activate $(VENV_AWS) ; VENV=$(VENV_AWS) make $(*:ec2-%=%)"

# Recette permettant d'exécuter une recette avec un tmux activé.
# Par exemple `make ec2-tmux-train`
ec2-tmux-%: ## call make recipe on EC2 with a tmux session
	$(VALIDATE_VENV)
	NO_RSYNC_END=n ssh-ec2 --multi tmux --leave "source activate $(VENV_AWS) ; VENV=$(VENV_AWS) make $(*:ec2-tmux-%=%)"

# Recette permettant un 'make ec2-detach-test'
# Il faut faire un ssh-ec2 --finish pour rapatrier les résultats à la fin
ec2-detach-%: ## call make recipe on EC2 and detach immediatly
	$(VALIDATE_VENV)
	ssh-ec2 --detach $(EC2_LIFE_CYCLE) "source activate $(VENV_AWS) ; VENV=$(VENV_AWS) make $(*:ec2-detach-%=%)"

# Recette pour lancer un jupyter notebook sur EC2
ec2-notebook: ## Start jupyter notebook on EC2
	$(VALIDATE_VENV)
	ssh-ec2 --stop -L 8888:localhost:8888 "jupyter notebook --NotebookApp.open_browser=False"

# Recette pour lancer ssh-ec2 avec les paramètres AWS du Makefile (`make ec2-ssh`)
ec2-ssh: ## Start ssh session on EC2 with parameters in current Makefile
	ssh-ec2 --leave

## ---------------------------------------------------------------------------------------
#TARGET_INSTALL:=~/.local/bin
TARGET_INSTALL:=/usr/local/bin
install: uninstall ## Installe une copie de ssh-ec2 dans /usr/local/bin
	@sudo cp ssh-ec2 $(TARGET_INSTALL)
	@sudo chmod go+rx $(TARGET_INSTALL)/ssh-ec2
	@echo "ssh-ec2 is installed in '$(TARGET_INSTALL)'"
	@which ssh-ec2 >/dev/null || echo "$(red)Add '$(TARGET_INSTALL)' at the begin of 'PATH' in your .bashrc ou .zshrc"

install-with-ln: uninstall ## Installe dans /usr/local/bin, un lien vers le source de ssh-ec2
	@sudo ln -s $(shell pwd)/ssh-ec2 $(TARGET_INSTALL)/ssh-ec2
	@echo "ssh-ec2 is installed in '$(TARGET_INSTALL)'."
	@which ssh-ec2 >/dev/null || echo "$(red)Add '$(TARGET_INSTALL)' at the begin of 'PATH' in your .bashrc ou .zshrc"

uninstall: ## Supprime de /usr/local/bin
	@sudo rm -f $(TARGET_INSTALL)/ssh-ec2

## ---------------------------------------------------------------------------------------
# Simulation d'un train qui prend du temps
train: requirements ## Train the model
	for i in $$(seq 1 120); do echo thinking; sleep 1 ; done
