import os

from setuptools import setup, find_packages

# USE_GPU="-gpu" ou "" si le PC possède une carte NVidia
# ou suivant la valeur de la variable d'environnement GPU (export GPU=yes)
USE_GPU = "-gpu" if (os.environ['GPU'].lower() in ( 'yes')
                     if "GPU" in os.environ
                     else os.path.isdir("/proc/driver/nvidia")
                          or "CUDA_PATH" in os.environ) else ""
setup(
    name='PRJ' + USE_GPU,               # FIXME: Modifier le nom du projet
    author="Octo Technology",
    use_scm_version=True,               # Gestion des versions à partir des commits Git
    python_requires='~=3.6',            # Version de Python
    packages=find_packages(),
    setup_requires=['setuptools_scm'],  # Pour utiliser Git pour gérer les versions
    extras_require={                    # Package nécessaires aux builds et tests mais pas au run
        'tests':
            ['mock',
             'unittest2',
             'daff',
             'awscli',
             ]
    },
    install_requires=                   # Exemples de packages nécessaires au run
    [
        'tensorflow' + USE_GPU + '~=0.5', # Exemple avec une alternative GPU
        'jupyter~=1.0',                 # Ouvre les add-on Jupyter
        'numpy~=1.14',
        'pandas~=0.22',
        'plotly~=2.7',
        'scikit-learn~=0.19',
        'spacy~=2.0',                   # Exemple de Spacy avec téléchargement de datas
        'nltk~=3.3',                    # Exemple de NLTK avec téléchargement de datas
    ],
    #test_suite="tests",
)
