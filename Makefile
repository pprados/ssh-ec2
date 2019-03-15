# SNIPPET pour changer le mode de gestion du Makefile.
# Avec ces trois paramètres, toutes les lignes d'une recette sont invoquées dans le même shell.
# Ainsi, il n'est pas nécessaire d'ajouter des '&&' ou des '\' pour regrouper les lignes.
# Comme Make affiche l'intégralité du block de la recette avant de l'exécuter, il n'est
# pas toujours facile de savoir quel est la ligne en échec.
# Je vous conseille dans ce cas d'ajouter au début de la recette 'set -x'
SHELL=/bin/bash
.SHELLFLAGS = -e -c
.ONESHELL:


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
# SNIPPET pour gérer le projet, le virtualenv et le kernel
# Par convention, le nom du projet, de l'environnement Conda ou le Kernel Jupyter
# corresponde au nom du répertoire du projet.
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
CONDA_PACKAGE:=$(CONDA_PREFIX)/lib/python$(PYTHON_VERSION)/site-packages
CONDA_PYTHON:=$(CONDA_PREFIX)/bin/python
PIP_PACKAGE:=$(CONDA_PACKAGE)/$(PRJ_PACKAGE).egg-link

## ---------------------------------------------------------------------------------------
# SNIPPET pour ajouter des repositories complémentaires à PIP
EXTRA_INDEX:=--extra-index-url=https://pypi.anaconda.org/octo/label/dev/simple

# Ici, il faut indiquer toutes les règles du Makefile n'étant pas
# reliée à un fichier. Ainsi, l'absence d'un ficheir 'help' par exemple, n'est pas
# le signe qu'il faut appliquer la règle.
.PHONY : help \
	prepare remove_env upgrade-env \
	remove-kernel \
	clean-notebooks notebook \
	git-config \
	requirements

## ---------------------------------------------------------------------------------------
# SNIPPET pour gérer automatiquement l'aide du Makefile.
# Il faut utiliser des commentaires commençant par '##' sur la ligne des règles,
# pour une production automatique de l'aide.
.DEFAULT: help

help: # Print all majors target
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
	printf "\033[36m%-15s\033[0m %s\n" "build-<dir>" "Execute notebooks in notebooks/<dir>\n"
	printf "\033[36m%-15s\033[0m %s\n" "build-all" "Execute all notebooks\n"
	printf "\033[36m%-15s\033[0m %s\n" "ec2-<target>" "Apply <target> receipt on EC2 instance\n"
	printf "\033[36m%-15s\033[0m %s\n" "ec2-tmux-<target>" "Apply <target> receipt on EC2 instance with tmux activated\n"
	printf "\033[36m%-15s\033[0m %s\n" "ec2-detach-<target>" "Apply <target> receipt on EC2 instance and detach the shell\n"
	echo -e "Use '\033[36mmake -B ...\033[0m' to force the target"
	echo -e "Use '\033[36mmake -n ...\033[0m' to simulate the build"

## ---------------------------------------------------------------------------------------
# SNIPPET pour affichier la valeur d'une variable d'environnement
# tel quelle est vue par le Makefile. Par exemple 'make dump-CONDA_PACKAGE'
dump-%:
	@ if [ "${${*}}" = "" ]; then
		echo "Environment variable $* not set";
		exit 1;
	else
		echo "$*=${${*}}";
	fi

## ---------------------------------------------------------------------------------------
# SNIPPET pour gérer les Notebooks avec GIT.
# Les règles suivantes s'assure que git est bien initialisé
# et ajoute des règles pour les fichiers *.ipynb
# et eventuellement pour les fichiers *.csv.
# Pour cela, un fichier .gitattribute est maintenu à jour.
# Les règles pour les notebooks se charge de les nettoyer avant de les commité.
# Pour cela, elles appliquent `jupyter nbconvert` à la volée. Ainsi, les comparaisons
# de version ne sont plus parasités par les datas.
# Les règles pour les CSV utilisent le composant `daff` (pip install daff)
# pour comparer plus efficacement les évolutions des fichiers csv.
# Un `git diff toto.csv` est plus clair.
.git:
	git init

# Purge notebook for git
pipe_clear_jupyter_output:
	jupyter nbconvert --to notebook --ClearOutputPreprocessor.enabled=True <(cat <&0) --stdout 2>/dev/null

# Check presence of DAFF
git-config .gitattributes: | .git  # Configure git
	@git config --local core.autocrlf input
	# Set tabulation to 4 when use 'git diff'
	@git config --local core.page 'less -x4'

	# Add rules to manage the output data of notebooks
	@git config --local filter.dropoutput_jupyter.clean "make --silent pipe_clear_jupyter_output"
	@git config --local filter.dropoutput_jupyter.smudge cat
	@[ -e .gitattributes ] && grep -v dropoutput_jupyter .gitattributes >.gitattributes.new 2>/dev/null || true
	@[ -e .gitattributes.new ] && mv .gitattributes.new .gitattributes || true
	@echo "*.ipynb filter=dropoutput_jupyter" >>.gitattributes
	@echo "*.ipynb diff=dropoutput_jupyter" >>.gitattributes

ifeq ($(shell which daff >/dev/null ; echo "$$?"),0)
	# Add rules to manage diff with daff for CSV file
	@git config --local diff.daff-csv.command "daff.py diff --git"
	@git config --local merge.daff-csv.name "daff.py tabular merge"
	@git config --local merge.daff-csv.driver "daff.py merge --output %A %O %A %B"
	@[ -e .gitattributes ] && grep -v daff-csv .gitattributes >.gitattributes.new 2>/dev/null
	@[ -e .gitattributes.new ] && mv .gitattributes.new .gitattributes
	@echo "*.[tc]sv diff=daff-csv" >>.gitattributes
	@echo "*.[tc]sv merge=daff-csv" >>.gitattributes
endif
	@echo ".gitattributes updated"

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
# pour qu'un simple `git clone http://... && cd toto && make test` fonctionne.
#
# Pour cela, il faut indiquer dans le fichier setup.py, toutes les dépendances
# de run et de test (voir l'exemple `setup.py`)

# Script à ajuster de vérification du VENV actif
CHECK_VENV=if [[ "base" == "$(CONDA_DEFAULT_ENV)" ]] ; then ( echo -e "\e[91mUse: conda activate $(VENV) before using 'make'\e[0m"; exit 1 ) ; fi

# Toutes les dépendances du projet à regrouper ici
requirements: \
		$(PIP_PACKAGE) \
		.gitattributes \
		$(CONDA_PACKAGE)/spacy/data/en \
		~/nltk_data/tokenizers/punkt \
		~/.local/share/jupyter/kernels/$(KERNEL)

# Règle de vérification de la bonne installation de la version de python dans l'environnement Conda
$(CONDA_PYTHON):
	$(CHECK_VENV)
	conda install "python=$(PYTHON_VERSION).*" -y -q

# Règle de mise à jour de l'environnement actif à partir
# des dépendances décrites dans `setup.py`
$(PIP_PACKAGE): $(CONDA_PYTHON) setup.py | .git # Install pip dependencies
	$(CHECK_VENV)
	pip install -e .[tests] | grep -v 'already satisfied' || true
	@touch $(PIP_PACKAGE)

# Règle d'installation du Kernel pour Jupyter
~/.local/share/jupyter/kernels/$(KERNEL): $(PIP_PACKAGE)
	$(CHECK_VENV)
	python -m ipykernel install --user --name $(KERNEL)

# Règle de suppression du kernel
remove-kernel:
	$(CHECK_VENV)
	jupyter kernelspec uninstall $(KERNEL)

# Download punkt databases
~/nltk_data/tokenizers/punkt: $(PIP_PACKAGE)
	$(CHECK_VENV)
	python -m nltk.downloader punkt stopwords wordnet
	@touch ~/nltk_data/tokenizers/punkt

# Download spacy databases
$(CONDA_PACKAGE)/spacy/data/en: $(PIP_PACKAGE)
	$(CHECK_VENV)
	# FIXME python -m spacy download en
	@touch $(CONDA_PACKAGE)/spacy/data/en

## ---------------------------------------------------------------------------------------
# SNIPPET pour préparer l'environnement d'un projet juste après un `git clone`
configure: ## Prepare the environment (conda venv, kernel, ...)
	@conda create -n "$(VENV)" python=$(PYTHON_VERSION) -y
	source activate "$(VENV)"
	$(MAKE) requirements
	echo "Use: conda activate $(VENV)"

remove-env: ## Remove venv
	conda deactivate
	conda env remove --name "$(VENV)" -y
	echo "Use: conda deactivate"

## ---------------------------------------------------------------------------------------
# SNIPPET de mise à jour des dernières versions des composants.
# Après validation, il est nécessaire de modifier les versions dans le fichier `setup.py`
upgrade-env: ## Upgrade packages to last versions
	$(CHECK_VENV)
	conda update --all
	pip list --format freeze --outdated | sed 's/(.*//g' | xargs -r -n1 pip install -U


## ---------------------------------------------------------------------------------------
# SNIPPET de validation des notebooks en les ré-executants.
# L'idée est d'avoir un sous répertoire par phase, dans le répertoire `notebooks`.
# Ainsi, il suffit d'un `make build-phaseX` pour valider tous les notesbooks du répertoire `notebooks/phaseX`.
# Pour gérer l'ordre d'exécution, il faut appliquer un ordre alphabétique, en préfixant chaque notebook d'un
# numéro par exemple.
build-%: requirements
	$(CHECK_VENV)
	time find notebooks/$* -name '*.ipynb' -not -path '*/\.*' -print0 | sort -z | xargs -r -0 jupyter nbconvert \
	  --ExecutePreprocessor.timeout=-1 \
	  --execute \
	  --inplace

build-all: build-* ## Re-build all notebooks

## ---------------------------------------------------------------------------------------
# SNIPPET pour executer jupyter notebook, mais en s'assurant de la bonne application des dépendances.
# Utilisez 'make notebook' à la place de 'jupyter notebook'.
notebook: requirements ## Start jupyter notebooks
	$(CHECK_VENV)
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
# SNIPPET pour faire le ménage du projet
clean: clean-pyc clean-notebooks ## Clean current environment

## ---------------------------------------------------------------------------------------
# SNIPPET pour déclencher les tests unitaires
test: requirements ## Run all tests
	$(CHECK_VENV)
	python -m unittest discover -s tests -b

validate: test build-all ## Validate the version

## ---------------------------------------------------------------------------------------
# SNIPPET pour ajouter la capacité d'exécuter des recettes sur une instance éphémère EC2.
# L'utilisation de `requirements` dans chaque règle, permet de s'assurer de la bonne
# mise en place de l'environnement nécessaire à l'exécution de la recette,
# même lorsqu'elle est exécuté sur EC2.
# Par exemple :
# - `make on-ec2-test` execute les TU sur EC2
# - `make detach-build-all` détache le recalcule tous les notebooks sur EC2

# Quel venv utilisé sur l'instance EC2 ?
AWS_INSTANCE_TYPE=t2.small
VENV_AWS=cntk_p36

# Quel est le cycle de vie par défaut des instances, via ssh-ec2 ?
EC2_LIFE_CYCLE=--terminate

# Recette permettant un 'make ec2-test'
ec2-%: ## call make recipe on EC2
	ssh-ec2 $(EC2_LIFE_CYCLE) "source activate $(VENV_AWS) ; make $(*:ec2-%=%)"

# Recette permettant un 'make ec2-tmux-test'
ec2-tmux-%: ## call make recipe on EC2 with a tmux session
	NO_RSYNC_END=n ssh-ec2 --multi tmux --leave "source activate $(VENV_AWS) ; make $(*:ec2-tmux-%=%)"

# Recette permettant un 'make ec2-detach-test'
# Il faut faire un ssh-ec2 --finish pour rapatrier les résultats à la fin
ec2-detach-%: ## call make recipe on EC2 and detach immediatly
	ssh-ec2 --detach $(EC2_LIFE_CYCLE) "source activate $(VENV_AWS) ; make $(*:ec2-detach-%=%)"

# Recette pour lancer un jupyter notebook sur EC2
ec2-notebook: ## Start jupyter notebook on EC2
	ssh-ec2 --stop -L 8888:localhost:8888 "jupyter notebook --NotebookApp.open_browser=False"


## ---------------------------------------------------------------------------------------
install: ## Installe une copie de ssh-ec2 dans /usr/bin
	sudo rm -f /usr/bin/ssh-ec2
	sudo cp ssh-ec2 /usr/bin
	sudo chmod go+rx /usr/bin/ssh-ec2

install-with-link: ## Installe dans /usr/bin, un lien vers le source de ssh-ec2
	sudo rm -f /usr/bin/ssh-ec2
	sudo ln -s $(shell pwd)/ssh-ec2 /usr/bin/ssh-ec2

# Ici, quelquels exemples de recettes bidons
train: requirements ## Train the model
	for i in $(seq 1 120); do echo thinking; while sleep 1 ; done

