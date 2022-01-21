# aks-flp-perf
This is a set of scripts and tools use to generate a docker image that will have the aks-flp-perf binary used to evaluate your AKS troubleshooting skill.

It uses the shc_script_converter.sh (build using the following tool https://github.com/neurobin/shc) to abstract the lab scripts on binary format and then the use the Dockerfile to pack everyting on a Ubuntu container with az cli and kubectl.

Any time the labs script require an update the github actions can be use to trigger a new build and push of the updated image. This will take care of building a new script binary as well as new docker image that will get pushed to the corresponding registry. The actions will get triggered any time a new release gets published.

Here is the general usage for the image and aks-flp-perf tool:

Run in docker: `docker run -it sturrent/aks-flp-perf:latest`

aks-flp-perf tool usage:
```
$ aks-flp-perf -h
aks-flp-perf usage: aks-flp-perf -l <LAB#> -u <USER_ALIAS> [-v|--validate] [-r|--region] [-h|--help] [--version]


Here is the list of current labs available:

*************************************************************************************
*        1. AKS disk attach issues
*        2. AKS disk multiattach issues
*        3. 
*************************************************************************************

"-l|--lab" Lab scenario to deploy (3 possible options)
"-r|--region" region to create the resources
"--version" print version of aks-flp-perf
"-h|--help" help info
```
