#!/bin/bash
 
if [ -f docker.flag ]; then
    if [ ! -e /mnt/homo_sapiens ]; then
        cp -r /opt/vep/.vep/homo_sapiens /mnt
    fi
 
    for file in human_ancestor.fa.rz human_ancestor.fa.rz.fai LoFtool_scores.txt phylocsf.sql; do
        if  [ ! -f /mnt/$file ]; then
            cp $file /mnt
        fi
    done
else
    # get human genome assembly using command line parameters
    OPTIND=1
    while getopts "a:" opt; do
        case $opt in
            a) assembly=$OPTARG
            ;;
        esac
    done
    shift "$((OPTIND-1))"

    # link $HOME to container /mnt
    ln -s $HOME/.vep/homo_sapiens /mnt/homo_sapiens
    cd /mnt

    # Download cache files and genome reference 
    perl /opt/vep/src/ensembl-vep/INSTALL.pl -n --CACHE_VERSION 93 --VERSION 93 -a cf -s homo_sapiens -y $assembly

    # Download plug-in dependencies
    wget https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/90/LoFtool_scores.txt
fi
wait
touch /mnt/completeness.flag
echo "Dependency files are now in the volume. Ready to start ClinicalReportR service" >> /mnt/complete.flag