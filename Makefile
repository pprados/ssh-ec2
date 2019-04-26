#!/usr/bin/env make
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

ifdef TERM
normal:=$(shell tput sgr0)
red:=$(shell tput setaf 1)
green:=$(shell tput setaf 2)
yellow:=$(shell tput setaf 3)
blue:=$(shell tput setaf 4)
purple:=$(shell tput setaf 5)
cyan:=$(shell tput setaf 6)
white:=$(shell tput setaf 7)
gray:=$(shell tput setaf 8)
endif

PRJ:=$(shell basename $(shell pwd))
VENV ?= $(PRJ)
KERNEL ?=$(VENV)
PRJ_PACKAGE:=$(PRJ)$(USE_GPU)
PYTHON_VERSION:=3.6

CONDA_BASE=$(shell conda info --base)
CONDA_PACKAGE:=$(CONDA_PREFIX)/lib/python$(PYTHON_VERSION)/site-packages
CONDA_PYTHON:=$(CONDA_PREFIX)/bin/python
PIP_PACKAGE:=$(CONDA_PACKAGE)/$(PRJ_PACKAGE).egg-link

## ---------------------------------------------------------------------------------------
.PHONY : help \
	configure \
	prepare \
	requirements \
	nltk-database spacy-database \
	upgrade-venv upgrade-$(VENV) \
	add_nbconvert_to_git nbconvert \
	clean-notebooks notebook \
	clean clean-all clean-venv clean-$(VENV) clean-pip clean-pyc \
	remove-kernel remove-venv remove-$(VENV) \
	test \
	ec2-*

.DEFAULT: help

help: ## Print all majors target
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(cyan)%-20s$(normal) %s\n", $$1, $$2}'
	printf "$(cyan)%-20s$(normal) %s\n" "build-<dir>" "Execute scripts in scripts/<dir>\n"
	printf "$(cyan)%-20s$(normal) %s\n" "'build-*'" "Execute all scripts\n"
	printf "$(cyan)%-20s$(normal) %s\n" "nbbuild-<dir>" "Execute notebooks in notebooks/<dir>\n"
	printf "$(cyan)%-20s$(normal) %s\n" "'nbbuild-*'" "Execute all notebooks\n"
	printf "$(cyan)%-20s$(normal) %s\n" "ec2-<target>" "Apply <target> receipt on EC2 instance\n"
	printf "$(cyan)%-20s$(normal) %s\n" "ec2-tmux-<target>" "Apply <target> receipt on EC2 instance with tmux activated\n"
	printf "$(cyan)%-20s$(normal) %s\n" "ec2-detach-<target>" "Apply <target> receipt on EC2 instance and detach the shell\n"
	echo -e "Use '$(cyan)make -jn ...$(normal)' for Parallel run"
	echo -e "Use '$(cyan)make -B ...$(normal)' to force the target"
	echo -e "Use '$(cyan)make -n ...$(normal)' to simulate the build"

dump-%:
	@if [ "${${*}}" = "" ]; then
		echo "Environment variable $* is not set";
		exit 1;
	else
		echo "$*=${${*}}";
	fi

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

ifeq ($(shell which jupyter >/dev/null ; echo "$$?"),0)
	# Add rules to manage the output data of notebooks
	@git config --local filter.dropoutput_jupyter.clean "make --silent pipe_clear_jupyter_output"
	@git config --local filter.dropoutput_jupyter.smudge cat
	@[ -e .gitattributes ] && grep -v dropoutput_jupyter .gitattributes >.gitattributes.new 2>/dev/null || true
	@[ -e .gitattributes.new ] && mv .gitattributes.new .gitattributes || true
	@echo "*.ipynb filter=dropoutput_jupyter diff=dropoutput_jupyter -text" >>.gitattributes
endif

	@echo ".gitattributes updated"

## ---------------------------------------------------------------------------------------
# SNIPPET pour vérifier la présence d'un environnement Conda conforme
# avant le lancement d'un traitement.
# Il faut ajouter $(VALIDATE_VENV) dans les recettes
# et choisir la version à appliquer.
# Soit :
# - CHECK_VENV pour vérifier l'activation d'un VENV avant de commencer
# - VALIDATE_VENV pour vérifier l'activation du VENV

CHECK_VENV=@if [[ "base" == "$(CONDA_DEFAULT_ENV)" ]] || [[ -z "$(CONDA_DEFAULT_ENV)" ]] ; \
  then ( echo -e "$(green)Use: $(cyan)conda activate $(VENV)$(green) before using 'make'$(normal)"; exit 1 ) ; fi

ACTIVATE_VENV=source $(CONDA_BASE)/bin/activate $(VENV)
DEACTIVATE_VENV=source $(CONDA_BASE)/bin/deactivate $(VENV)

VALIDATE_VENV=$(CHECK_VENV)

JUPYTER_DATA_DIR:=$(shell jupyter --data-dir 2>/dev/null || echo "~/.local/share/jupyter")

REQUIREMENTS= \
		$(PIP_PACKAGE) \
		.gitattributes
requirements: $(REQUIREMENTS)

$(CONDA_PYTHON):
	$(VALIDATE_VENV)
	conda install "python=$(PYTHON_VERSION).*" -y -q

$(PIP_PACKAGE): $(CONDA_PYTHON) setup.py | .git # Install pip dependencies
	$(VALIDATE_VENV)
	pip install -e '.[tests]' | grep -v 'already satisfied' || true
	@touch $(PIP_PACKAGE)

# Règle d'installation du Kernel pour Jupyter
$(JUPYTER_DATA_DIR)/kernels/$(KERNEL): $(PIP_PACKAGE)
	$(VALIDATE_VENV)
	python -m ipykernel install --user --name $(KERNEL)

configure: ## Prepare the environment (conda venv, kernel, ...)
	@conda create --name "$(VENV)" python=$(PYTHON_VERSION) -y
	echo -e "Use: $(cyan)conda activate $(VENV)$(normal)"

remove-venv remove-$(VENV): ## Remove venv
	@$(DEACTIVATE_VENV)
	conda env remove --name "$(VENV)" -y
	echo -e "Use: $(cyan)conda deactivate$(normal)"

## ---------------------------------------------------------------------------------------
# SNIPPET pour executer jupyter notebook, mais en s'assurant de la bonne application des dépendances.
# Utilisez 'make notebook' à la place de 'jupyter notebook'.
notebook: $(REQUIREMENTS) $(JUPYTER_DATA_DIR)/kernels/$(KERNEL) ## Start jupyter notebooks
	$(VALIDATE_VENV)
	jupyter notebook

clean-pyc: # Clean pre-compiled files
	-/usr/bin/find . -name '*.pyc' -exec rm -f {} +
	-/usr/bin/find . -name '*.pyo' -exec rm -f {} +

clean-notebooks: ## Remove all results of notebooks
	@[ -e notebooks ] && find notebooks -name '*.ipynb' -exec jupyter nbconvert --ClearOutputPreprocessor.enabled=True --inplace {} \;
	@echo "Notebooks cleaned"
clean-pip: ## Remove all the pip package
	$(VALIDATE_VENV)
	pip freeze | grep -v "^-e" | xargs pip uninstall -y

clean-venv clean-$(VENV): remove-venv ## Set the current VENV empty
	@echo -e "$(cyan)Re-create virtualenv $(VENV)...$(normal)"
	conda create -y -q -n $(VENV)
	touch setup.py
	echo -e "$(yellow)Warning: Conda virtualenv $(VENV) is empty.$(normal)"

clean: clean-pyc clean-notebooks ## Clean current environment

clean-all: clean remove-venv remove-kernel ## Clean all environments

test: requirements ## Run all tests
	$(VALIDATE_VENV)
	python -m unittest discover -s tests -b

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
#EC2_LIFE_CYCLE=--terminate
EC2_LIFE_CYCLE=--leave

# Recette permettant un 'make ec2-test'
ec2-%: ## call make recipe on EC2
	$(VALIDATE_VENV)
	ssh-ec2 $(EC2_LIFE_CYCLE) "source activate $(VENV_AWS) ; VENV=$(VENV_AWS) make $(*:ec2-%=%)"

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


