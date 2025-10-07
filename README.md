# Brieflow Analysis Template

Template repository for storing processing optical pooled screen data with [Brieflow](https://github.com/cheeseman-lab/brieflow).

**Notes**: 
- Read [brieflow.readthedocs.io](https://brieflow.readthedocs.io/) before starting to get a good grasp of brieflow and brieflow-analysis!
- We aim to keep brieflow-related issues in the main brieflow repository ([here](https://github.com/cheeseman-lab/brieflow/issues)).
- Join the brieflow [Discord](https://discord.gg/yrEh6GP8JJ) to ask questions, share ideas, and get help from other users and developers.


## Set Up

This repository is designed to work with Brieflow to analyze optical pooled screens.
Follow these steps to get set up for a screen analysis!

### 1. Screen Analysis Repository Setup

Brieflow-analysis is a template for each screen analysis.
Create a new respository for a screen to get started.

1) Create a new screen repository wih the "Use this template" button for each new screen analysis.

![use template](images/template_button.png)

2) Clone the newly created repository to your local machine:

```sh
git clone https://github.com/YOUR-USERNAME/YOUR-SCREEN-REPO.git
cd YOUR-SCREEN-REPO
```

See the GitHub documentation for [using a template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template) for more information.

### 2. Brieflow Setup

We use [brieflow](https://github.com/cheeseman-lab/brieflow) to process data on a very large scale from each screen.
We use brieflow as a git submodule in this repository.
Please see the [Git Submodules basic explanation](https://gist.github.com/gitaarik/8735255) for information on how to best install, use, and update this submodule.
We recommend using a forked version of brieflow and provide instructions for doing this below.
We **highly recommend** reading the GitHub documentation for explanation of forks to understand how your fork of brieflow syncs with the `cheeseman-lab` brieflow.
From the documentation:

> A fork is a new repository that shares code and visibility settings with the original “upstream” repository. Forks are often used to iterate on ideas or changes before they are proposed back to the upstream repository, such as in open source projects or when a user does not have write access to the upstream repository. For more information, see [Working with forks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks).

To get started:

1) Create a fork of brieflow as described [here](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo).

2) Clone the brieflow package into this repo using the following git submodule commands:

```sh
# enter brieflow dir
cd brieflow/
# set url to forked brieflow
git submodule set-url brieflow https://github.com/YOUR-USERNAME/brieflow.git
# init submodule
git submodule update --init --recursive
```

3) Configure the remote repository for your fork (more info [here](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/configuring-a-remote-repository-for-a-fork)).

```sh
# set remote upstream repo
git remote add upstream https://github.com/cheeseman-lab/brieflow.git

# check origin and upstream repos
git remote -v
# Confirm you see the below output
> origin    https://github.com/YOUR-USERNAME/brieflow.git (fetch)
> origin    https://github.com/YOUR-USERNAME/brieflowgit (push)
> upstream  https://github.com/cheeseman-lab/brieflow.git (fetch)
> upstream  https://github.com/cheeseman-lab/brieflow.git (push)
```

Follow the [GitHub documentation](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/syncing-a-fork) to to sync changes between your fork and `cheeseman-lab/brieflow` (ex, to pull a new branch).

4) Set up brieflow following the [setup instructions](https://github.com/cheeseman-lab/brieflow#brieflow-setup).

Use the following commands to set up the brieflow Conda environment (~10 min):

```sh
# enter breiflow dir
cd brieflow/
# create and activate brieflow_SCREEN_NAME conda environment
# NOTE: replace brieflow_SCREEN_NAME with the name of your screen to ensure a screen-specific installation
# using this screen-specific installation will refer to library code in ./brieflow/workflow/lib
conda create -n brieflow_SCREEN_NAME -c conda-forge python=3.11 uv pip -y
conda activate brieflow_SCREEN_NAME
# install external packages
uv pip install -r pyproject.toml
# install editable version of brieflow
uv pip install -e .
# install conda-only packages
conda install -c conda-forge micro_sam -y # skip if not using micro-sam for segmentation
```

**Notes:**
- We recommend a screen-specific installation because changes to this particular `./brieflow/workflow/lib` code will live within this specific installation of brieflow, and an explicit name helps keep track of different brieflow installations.
One could also install one version of brieflow that is used across brieflow-analysis repositories.
- For a rule-specific package consider creating a separate conda environment file and using it for the particular rule as described in the [Snakemake integrated package management notes](https://snakemake.readthedocs.io/en/stable/snakefiles/deployment.html#integrated-package-management).

We use the HPC integration for Slurm as detailed in the setup instructions.
To use the Slurm integration for Brieflow configure the Slurm resources in [analysis/slurm/config.yaml](analysis/slurm/config.yaml).

5) *Optional*: Contribute back to brieflow:

Track changes to computational processing in a new branch on your fork.
Contribute these changes to `cheeseman-lab/brieflow` with a pull request.
See GitHub's documentation for [contributing to a project](https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project) and brieflow's [contribution notes](https://github.com/cheeseman-lab/brieflow?tab=readme-ov-file#contribution-notes) for more info.

### 3. Brieflow Test

Run the following commands to ensure your Brieflow is set up correctly:
This will test Brieflow on a small limited subset of example data that we provide, and functions only with the main branch of Brieflow. This is **not** the optimal location for analyzing your data.
```sh
# activate brieflow env
conda activate brieflow_SCREEN_NAME
# set up small test analysis
cd brieflow/tests/small_test_analysis
python small_test_analysis_setup.py
# run brieflow
sh run_brieflow.sh
# run tests
cd ../../
pytest
```

### 4. Start Analysis

**Note:** Before beginning analysis, it is strongly recommended that you fill out the `screen.yaml` file to track all of your experimental metadata.

`analysis/` contains configuration notebooks used to configure processes and slurm scripts used to run full modules.
By default, results are output to `analysis/brieflow_output` and organized by analysis module (preprocess, sbs, phenotype, etc).

Follow the full instructions below to run an analysis.


## Analysis Steps

Follow the instructions below to configure parameters and run modules.
All of these steps are done in the example analysis.
Use the following commands to enter this folder and activate the conda env:

```sh
# enter analysis directory
cd analysis/
# activate brieflow_main_env conda environment
conda activate brieflow_SCREEN_NAME
```

***Notes**: 

- Use `brieflow_SCREEN_NAME` Conda environment for each configuration notebook.
- How you use `brieflow` should depend on your workload.
    - Runs that can be done with local compute can be run with the `.sh` scripts, which are set up to run all rules for a module.
    Note that these scripts are currently set up to do a dry run with the `-n` parameter, which will need to be removed for a local run`.
    - Runs that need HPC compute should be run with the `_slurm.sh` scripts.
    Right now, these are set up to log run information and break the larger steps (preprocessing, sbs, phenotype) into plate-level runs.
    The local `.sh` scripts can still be used to do a dry run preview with `-n` (already set up).

### Step 0: Configure preprocess parameters

Follow the steps in [0.configure_preprocess_params.ipynb](analysis/0.configure_preprocess_params.ipynb) to configure preprocess params.

**Note:** This step determines where ND2 data is loaded from (can be from anywhere) and where intermediate/output data is saved (can also be anywhere).
By default, results are output to `analysis/brieflow_output`.

### Step 1: Run preprocessing module

**Local**:
```sh
sh 1.run_preprocessing.sh
```

**Slurm**:

Change `NUM_PLATES` in [1.run_preprocessing_slurm.sh](1.run_preprocessing_slurm.sh) to the number of plates you are processing (to process each plate separately).

```sh
# start a tmux session: 
tmux new-session -s preprocessing
# in the tmux session:
bash 1.run_preprocessing_slurm.sh
```

***Note**: For testing purposes, users may only have generated sbs or phenotype images.
It is possible to test only SBS/phenotype preprocessing in this notebook.
See notebook instructions for more details.

### Step 2: Configure SBS parameters

Follow the steps in [2.configure_sbs_params.ipynb](analysis/2.configure_sbs_params.ipynb) to configure SBS module parameters.

### Step 3: Configure phenotype parameters

Follow the steps in [3.configure_phenotype_params.ipynb](analysis/3.configure_phenotype_params.ipynb) to configure phenotype module parameters.

### Step 4: Run SBS/phenotype modules

**Local**:
```sh
sh 4.run_sbs_phenotype.sh
```
**Slurm**:

Change `NUM_PLATES` [4a.run_sbs_slurm.sh](4a.run_sbs_slurm.sh) and [4b.run_phenotype_slurm.sh](4b.run_phenotype_slurm.sh) to the number of plates you are processing (to process each plate separately).
These two modules can be run simultaneously or separately.

```sh
# start a tmux session: 
tmux new-session -s sbs_phenotype
# in the tmux session:
bash 4a.run_sbs_slurm.sh
bash 4b.run_phenotype_slurm.sh
```

### Step 5: Configure merge process params

Follow the steps in [5.configure_merge_params.ipynb](analysis/5.configure_merge_params.ipynb) to configure merge process params.

### Step 6: Run merge process

**Local**:
```sh
sh 6.run_merge.sh
```
**Slurm**:
```sh
# start a tmux session: 
tmux new-session -s merge
# in the tmux session:
bash 6.run_merge_slurm.sh
```

### Step 7: Configure aggregate process params

Follow the steps in [7.configure_aggregate_params.ipynb](analysis/7.configure_aggregate_params.ipynb) to configure aggregate process params.

### Step 8: Run aggregate process

**Local**:
```sh
sh 8.run_aggregate.sh
```
**Slurm**:
```sh
# start a tmux session: 
tmux new-session -s aggregate
# in the tmux session:
bash 8.run_aggregate_slurm.sh
```

### Step 9: Configure cluster process params

Follow the steps in [9.configure_cluster_params.ipynb](analysis/9.configure_cluster_params.ipynb) to configure cluster process params.

### Step 10: Run cluster process

**Local**:
```sh
sh 10.run_cluster.sh
```
**Slurm**:
```sh
# start a tmux session: 
tmux new-session -s cluster
# in the tmux session:
bash 10.run_cluster_slurm.sh
```

### Step 11: Notebook analysis

Run the [11.analyze.ipynb](analysis/11.analyze.ipynb) notebook to evaluate the biological relevance of your clusters using a [LLM wrapper](https://github.com/cheeseman-lab/mozzarellm) and to generate simple plots of your features.

### Step 12: Brieflow Visualization

Brieflow includes a native visualizer for a screen's experimental overview, analysis overview, quality control, and cluster analysis.
Run the following command to start this visualization:

```sh
sh 12.run_visualization.sh
```

***Note**: Many users will want to only run SBS or phenotype processing, independently.
It is possible to restrict the SBS/phenotype processing with the following:
1) If either of the sample dataframes defined in [0.configure_preprocess_params.ipynb](analysis/0.configure_preprocess_params.ipynb) are empty then no samples will be processed.
See the notebook for more details.
2) By varying the tags in the `4.run_sbs_phenotype` sh files (`--until all_sbs` or `--until all_phenotype`), the analysis will only run only the analysis of interest.

## Generate Rulegraph

Run the following script to generate a rulegraph of Brieflow:

```sh
sh generate_rulegraph.sh
```

## Contributing

- Core improvements should be contributed back to Brieflow
- If you have analyzed any of your optical pooled screening data using brieflow-analysis, please reach out and we will include you in the table below!

## Examples of brieflow-analysis usage:

| Study | Description | Analysis Repository | Publication |
|-------|-------------|---------------------|-------------|
| _Coming soon_ | | | |